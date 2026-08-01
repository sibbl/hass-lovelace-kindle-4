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

wait_ping() {
    CONNECTED=0
    PING_TIMEOUT_SECONDS=${PING_TIMEOUT:-10}
    /bin/ping -c 1 "$PINGHOST" >/dev/null 2>&1 &
    PING_PID=$!
    (
        sleep "$PING_TIMEOUT_SECONDS"
        kill "$PING_PID" >/dev/null 2>&1
    ) &
    PING_WATCHDOG_PID=$!

    wait "$PING_PID"
    PING_STATUS=$?
    kill "$PING_WATCHDOG_PID" >/dev/null 2>&1
    wait "$PING_WATCHDOG_PID" 2>/dev/null

    [ "$PING_STATUS" -eq 0 ] && CONNECTED=1
    return $CONNECTED
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

    wget -q "$DOWNLOAD_URI" -O "$TMPFILE" &
    DOWNLOAD_PID=$!
    (
        sleep "$DOWNLOAD_TIMEOUT_SECONDS"
        kill "$DOWNLOAD_PID" >/dev/null 2>&1 && echo "Download timed out after ${DOWNLOAD_TIMEOUT_SECONDS} seconds"
    ) &
    DOWNLOAD_WATCHDOG_PID=$!

    wait "$DOWNLOAD_PID"
    DOWNLOAD_STATUS=$?
    kill "$DOWNLOAD_WATCHDOG_PID" >/dev/null 2>&1
    wait "$DOWNLOAD_WATCHDOG_PID" 2>/dev/null

    return $DOWNLOAD_STATUS
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
