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
    mkdir /mnt/us/update.bin.tmp.partial -f # prevent from Amazon updates
    touch /mnt/us/WIFI_NO_NET_PROBE         # do not perform a WLAN test
}

wait_wlan() {
    return $(lipc-get-prop com.lab126.wifid cmState | grep CONNECTED | wc -l)
}

wait_ping() {
    CONNECTED=0
    /bin/ping -c 1 $PINGHOST >/dev/null && CONNECTED=1
    return $CONNECTED
}

logger() {
    MSG=$1

    # do nothing if logging is not enabled
    if [ "x1" != "x$LOGGING" ]; then
        return
    fi

    # if no logfile is specified, set a default
    if [ -z $LOGFILE ]; then
        $LOGFILE=stdout
    fi

    echo $(date): $MSG >>$LOGFILE
}
