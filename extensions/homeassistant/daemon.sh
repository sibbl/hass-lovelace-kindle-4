#!/bin/bash

DAEMON_PATH="/mnt/us/extensions/homeassistant"
NAME=homeassistant
PIDFILE="$DAEMON_PATH/$NAME.pid"
LOCKDIR="$PIDFILE.lock"

# A PID file alone is not proof of ownership: it may be stale or malformed.
daemon_running() {
    [ -f "$PIDFILE" ] || return 1
    PID=$(cat "$PIDFILE")
    case "$PID" in
        ''|*[!0-9]*|0*|1) return 1 ;;
    esac
    kill -0 "$PID" 2>/dev/null || return 1
    [ "$(readlink "/proc/$PID/cwd")" = "$DAEMON_PATH" ] || return 1
    # Accept both the new absolute invocation and the old ./script.sh form.
    COMMAND=$(tr '\000' '\n' < "/proc/$PID/cmdline" | sed -n '1,2p')
    case "$COMMAND" in
        "sh
$DAEMON_PATH/script.sh"|"/bin/sh
$DAEMON_PATH/script.sh"|"/bin/sh
./script.sh") return 0 ;;
    esac
    return 1
}

start_daemon() {
    if daemon_running; then
        echo "$NAME already running"
        return 0
    fi
    cd "$DAEMON_PATH" || return 1
    # Invoke the shell explicitly: files copied over USB may not be executable.
    sh "$DAEMON_PATH/script.sh" </dev/null >/dev/null 2>&1 &
    PID=$!
    if ! echo "$PID" > "$PIDFILE"; then
        kill "$PID" 2>/dev/null
        return 1
    fi
    # Keep the control lock until the child has entered its shell invocation.
    sleep 1
    if ! daemon_running; then
        echo "$NAME failed to start or process ownership could not be verified" >&2
        # Preserve the PID for diagnosis; never signal an unverified process.
        return 1
    fi
    echo "Started $NAME"
}

stop_daemon() {
    if daemon_running; then
        kill "$PID" || return 1
        # Do not allow a replacement loop while the old shell is still exiting.
        ATTEMPTS=0
        while daemon_running; do
            if [ "$ATTEMPTS" -ge 10 ]; then
                echo "$NAME is still stopping; retry later" >&2
                return 1
            fi
            sleep 1
            ATTEMPTS=$((ATTEMPTS + 1))
        done
        echo "Stopped $NAME"
    else
        echo "$NAME not running (missing, stale or invalid pidfile)"
    fi
    rm -f "$PIDFILE"
}

case "$1" in
    status)
        if daemon_running; then
            echo "$NAME running"
            exit 0
        fi
        echo "$NAME not running"
        exit 1
        ;;
    start|stop|restart) ;;
    *) echo "Usage: $0 {status|start|stop|restart}"; exit 1 ;;
esac

# Serialize start/stop requests, including simultaneous KUAL and boot starts.
if ! mkdir "$LOCKDIR" 2>/dev/null; then
    echo "$NAME control operation already in progress ($LOCKDIR)" >&2
    exit 1
fi
trap 'rmdir "$LOCKDIR"' 0
trap 'exit 1' HUP INT TERM

case "$1" in
    start) start_daemon ;;
    stop) stop_daemon ;;
    restart) stop_daemon && start_daemon ;;
esac
