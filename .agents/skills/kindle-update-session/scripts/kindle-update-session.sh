#!/bin/sh

set -u

KINDLE_HOST=${KINDLE_HOST:-192.168.0.172}
KINDLE_USER=${KINDLE_USER:-root}
KINDLE_TARGET="${KINDLE_USER}@${KINDLE_HOST}"
WAIT_TIMEOUT=${WAIT_TIMEOUT:-180}
SLEEP_SECONDS=${SLEEP_SECONDS:-2}
REPO_ROOT=${REPO_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)}
ACTION=${1:-deploy}
KINDLE_SSH_BATCH_MODE=${KINDLE_SSH_BATCH_MODE:-yes}
KINDLE_SSH_EXTRA_OPTS=${KINDLE_SSH_EXTRA_OPTS:-}

SSH_OPTS="-o BatchMode=${KINDLE_SSH_BATCH_MODE} -o ConnectTimeout=3 -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new ${KINDLE_SSH_EXTRA_OPTS}"

usage() {
    cat <<EOF
Usage: $0 [wait|stop|deploy|start|status]

Environment:
  KINDLE_HOST     Kindle IP or hostname (default: 192.168.0.172)
  KINDLE_USER     SSH user (default: root)
  WAIT_TIMEOUT    Seconds to wait for SSH (default: 180)
  SLEEP_SECONDS   Poll interval in seconds (default: 2)
  REPO_ROOT       Repository root (auto-detected by default)
  KINDLE_SSH_BATCH_MODE
                  Use "no" to allow interactive password prompts (default: yes)
  KINDLE_SSH_EXTRA_OPTS
                  Extra options passed to ssh/scp/rsync ssh

Actions:
  wait     Wait until SSH is available.
  stop     Wait for SSH, cancel startup.sh, stop daemon.sh, and print status.
  deploy   Stop, copy this repo's Kindle files, start the daemon, and print status.
  start    Wait for SSH, start daemon.sh, and print status.
  status   Wait for SSH and print process/service/log status.
EOF
}

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

run_ssh() {
    ssh $SSH_OPTS "$KINDLE_TARGET" "$@"
}

wait_for_ssh() {
    START=$(date +%s)
    SSH_ERROR_FILE="/tmp/kindle-update-session-ssh.$$"
    rm -f "$SSH_ERROR_FILE"

    log "Waiting up to ${WAIT_TIMEOUT}s for SSH on ${KINDLE_TARGET}"
    while :; do
        if run_ssh 'true' >/dev/null 2>"$SSH_ERROR_FILE"; then
            rm -f "$SSH_ERROR_FILE"
            log "SSH is available on ${KINDLE_TARGET}"
            return 0
        fi

        if grep -qi 'Permission denied' "$SSH_ERROR_FILE" 2>/dev/null; then
            log "SSH reached ${KINDLE_TARGET}, but authentication failed"
            log "Install/configure an SSH key for ${KINDLE_TARGET}, or rerun with KINDLE_SSH_BATCH_MODE=no for an interactive password prompt"
            cat "$SSH_ERROR_FILE" >&2
            rm -f "$SSH_ERROR_FILE"
            return 2
        fi

        NOW=$(date +%s)
        ELAPSED=$((NOW - START))
        if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
            log "Timed out waiting for SSH on ${KINDLE_TARGET}"
            if [ -s "$SSH_ERROR_FILE" ]; then
                log "Last SSH error:"
                cat "$SSH_ERROR_FILE" >&2
            fi
            rm -f "$SSH_ERROR_FILE"
            return 1
        fi

        sleep "$SLEEP_SECONDS"
    done
}

remote_status() {
    run_ssh '
        echo "== processes =="
        ps | grep "[s]tartup.sh" || true
        ps | grep "[s]cript.sh" || true
        echo "== daemon =="
        sh /mnt/us/extensions/homeassistant/daemon.sh status || true
        echo "== log file =="
        ls -l /mnt/us/extensions/homeassistant/homeassistant.log 2>/dev/null || true
    '
}

remote_stop() {
    run_ssh '
        echo "Canceling pending startup.sh if present"
        PID=$(ps | grep "[s]tartup.sh" | awk "{print \$1}")
        [ -n "$PID" ] && kill -HUP $PID || true

        echo "Stopping homeassistant daemon if present"
        sh /mnt/us/extensions/homeassistant/daemon.sh stop || true

        echo "Stopping leftover script.sh processes if present"
        PIDS=$(ps | grep "[s]cript.sh" | awk "{print \$1}")
        [ -n "$PIDS" ] && kill $PIDS || true
        sleep 1
        PIDS=$(ps | grep "[s]cript.sh" | awk "{print \$1}")
        [ -n "$PIDS" ] && kill -9 $PIDS || true

        echo "Remaining dashboard processes"
        ps | grep "[s]tartup.sh" || true
        ps | grep "[s]cript.sh" || true
    '
}

copy_updates() {
    if command -v rsync >/dev/null 2>&1; then
        log "Copying extensions/homeassistant with rsync"
        rsync -rltv --no-owner --no-group --no-perms -e "ssh $SSH_OPTS" \
            "$REPO_ROOT/extensions/homeassistant/" \
            "$KINDLE_TARGET:/mnt/us/extensions/homeassistant/"

        log "Copying kite with rsync"
        rsync -rltv --no-owner --no-group --no-perms -e "ssh $SSH_OPTS" \
            "$REPO_ROOT/kite/" \
            "$KINDLE_TARGET:/mnt/us/kite/"
    else
        log "rsync not found; copying with scp"
        scp $SSH_OPTS -r "$REPO_ROOT/extensions/homeassistant" "$KINDLE_TARGET:/mnt/us/extensions/"
        scp $SSH_OPTS -r "$REPO_ROOT/kite" "$KINDLE_TARGET:/mnt/us/"
    fi
}

remote_start() {
    run_ssh '
        echo "Starting homeassistant daemon"
        sh /mnt/us/extensions/homeassistant/daemon.sh start </dev/null
        sh /mnt/us/extensions/homeassistant/daemon.sh status || true
    '
}

case "$ACTION" in
wait)
    wait_for_ssh
    ;;
stop)
    wait_for_ssh && remote_stop && remote_status
    ;;
deploy)
    wait_for_ssh && remote_stop && copy_updates && remote_start && remote_status
    ;;
start)
    wait_for_ssh && remote_start && remote_status
    ;;
status)
    wait_for_ssh && remote_status
    ;;
-h|--help|help)
    usage
    ;;
*)
    usage
    exit 2
    ;;
esac
