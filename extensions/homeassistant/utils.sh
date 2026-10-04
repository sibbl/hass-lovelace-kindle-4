#!/bin/sh

kill_kindle() {
    /etc/init.d/framework stop >/dev/null 2>&1
    /etc/init.d/cmd stop >/dev/null 2>&1
    /etc/init.d/phd stop >/dev/null 2>&1
    /etc/init.d/volumd stop >/dev/null 2>&1
    /etc/init.d/tmd stop >/dev/null 2>&1
    /etc/init.d/webreader stop >/dev/null 2>&1
    killall lipc-wait-event >/dev/null 2>&1
}

customize_kindle() {
    mkdir -p /mnt/us/update.bin.tmp.partial # prevent from Amazon updates
    touch /mnt/us/WIFI_NO_NET_PROBE         # do not perform a WLAN test
}

wait_wlan() {
    return $(lipc-get-prop com.lab126.wifid cmState | grep CONNECTED | wc -l)
}

# Redirect the watchdog's descriptors so a successful download cannot leave
# command substitution waiting for an inherited output pipe. Reap its sleep too.
run_with_timeout() (
    TIMEOUT_SECONDS=$1
    shift
    "$@" &
    WORK_PID=$!
    (
        trap 'kill "$TIMER_PID" 2>/dev/null; wait "$TIMER_PID" 2>/dev/null' 0
        trap 'exit 0' HUP INT TERM
        sleep "$TIMEOUT_SECONDS" &
        TIMER_PID=$!
        wait "$TIMER_PID"
        kill "$WORK_PID" 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
    WATCHDOG_PID=$!
    trap 'kill "$WORK_PID" "$WATCHDOG_PID" 2>/dev/null; wait "$WORK_PID" "$WATCHDOG_PID" 2>/dev/null' 0
    trap 'exit 1' HUP INT TERM
    wait "$WORK_PID"
    RESULT=$?
    kill "$WATCHDOG_PID" 2>/dev/null
    wait "$WATCHDOG_PID" 2>/dev/null
    # The worker has been reaped: do not signal its PID again from the exit trap.
    trap - 0
    return "$RESULT"
)

wait_ping() {
    CONNECTED=0
    run_with_timeout "${PING_TIMEOUT:-10}" /bin/ping -c 1 "$PINGHOST" >/dev/null 2>&1 && CONNECTED=1
    return "$CONNECTED"
}

download_image() {
    DOWNLOAD_URI=$IMAGE_URI
    DOWNLOAD_TIMEOUT_SECONDS=${DOWNLOAD_TIMEOUT:-45}
    rm -f "$TMPFILE"

    if [ -n "$BASIC_AUTH_USERNAME" ] || [ -n "$BASIC_AUTH_PASSWORD" ]; then
        case "$IMAGE_URI" in
        http://*)
            DOWNLOAD_URI="http://${BASIC_AUTH_USERNAME}:${BASIC_AUTH_PASSWORD}@${IMAGE_URI#http://}"
            ;;
        *)
            logger "Basic auth is configured, but IMAGE_URI does not start with http://"
            ;;
        esac
    fi

    # Bound disk consumption even if a server streams indefinitely. Shells use
    # 512- or 1024-byte blocks, so this caps the file at no more than 2 MiB.
    # Apply the limit only to wget, not to the dashboard's log files.
    run_with_timeout "$DOWNLOAD_TIMEOUT_SECONDS" sh -c '
        ulimit -f 2048 || exit 1
        exec wget -q "$1" -O "$2"
    ' sh "$DOWNLOAD_URI" "$TMPFILE" >/dev/null 2>&1
    DOWNLOAD_STATUS=$?
    if [ "$DOWNLOAD_STATUS" -ne 0 ] || [ ! -s "$TMPFILE" ]; then
        rm -f "$TMPFILE"
        echo "Image download failed, timed out, or exceeded the size limit"
        return 1
    fi
    return 0
}

rotate_log() {
    LOG_MAX_SIZE_BYTES=${LOG_MAX_SIZE_BYTES:-1048576}
    LOG_ROTATE_COUNT=${LOG_ROTATE_COUNT:-3}

    [ -f "$LOGFILE" ] || return

    case "$LOG_MAX_SIZE_BYTES" in
    ''|*[!0-9]*)
        return
        ;;
    esac

    case "$LOG_ROTATE_COUNT" in
    ''|*[!0-9]*|0)
        return
        ;;
    esac

    LOG_SIZE=$(ls -l "$LOGFILE" 2>/dev/null | awk '{print $5}')
    case "$LOG_SIZE" in
    ''|*[!0-9]*)
        return
        ;;
    esac

    [ "$LOG_SIZE" -lt "$LOG_MAX_SIZE_BYTES" ] && return

    ROTATE_INDEX=$LOG_ROTATE_COUNT
    while [ "$ROTATE_INDEX" -gt 1 ]; do
        PREVIOUS_INDEX=$((ROTATE_INDEX - 1))
        if [ -f "${LOGFILE}.${PREVIOUS_INDEX}" ]; then
            mv -f "${LOGFILE}.${PREVIOUS_INDEX}" "${LOGFILE}.${ROTATE_INDEX}"
        fi
        ROTATE_INDEX=$PREVIOUS_INDEX
    done

    mv -f "$LOGFILE" "${LOGFILE}.1"
}

logger() {
    MSG=$1

    # do nothing if logging is not enabled
    if [ "x1" != "x$LOGGING" ]; then
        return
    fi

    if [ -z "$LOGFILE" ]; then
        echo "$(date): $MSG"
        return
    fi

    rotate_log
    echo "$(date): $MSG" >>"$LOGFILE"
}
