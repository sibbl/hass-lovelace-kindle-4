#!/bin/sh

# load config
if [ -e "config.sh" ]; then
    source ./config.sh
else
    logger "Could not find config.sh in $(pwd)"
    echo "Could not find config.sh in $(pwd)"
    exit
fi

# load utils
if [ -e "utils.sh" ]; then
    source ./utils.sh
else
    logger "Could not find utils.sh in $(pwd)"
    echo "Could not find utils.sh in $(pwd)"
    exit
fi

kill_kindle
customize_kindle

GLOBAL_ERROR_COUNT=0

while true; do
    echo "Starting new loop"
    logger "START NEW LOOP"

    logger "Set CPU scaling governer to powersave"
    echo powersave >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

    logger "Set prevent screen saver to true"
    lipc-set-prop com.lab126.powerd preventScreenSaver 1

    echo "Check battery level"
    CHECKBATTERY=$(gasgauge-info -s | sed 's/.$//')
    if [ ${CHECKBATTERY} -le ${BATTERYLOW} ]; then
        logger "Battery below ${BATTERYLOW}"
        eips -f -g "${LIMGBATT}"
        ./rtcwake -d rtc$RTC -s $BATTERYSLEEP -m mem
        sleep 30 # waiting time when charging until battery level is higher than "BATTERYLOW" otherwise it will fall into sleep again
    else
        logger "Remaining battery ${CHECKBATTERY}"
    fi

    ### activate wifi
    logger "Enabling and checking wifi"
    lipc-set-prop com.lab126.wifid enable 1

    echo "Check wifi connection"
    WLANNOTCONNECTED=0
    WLANCOUNTER=0
    PINGNOTWORKING=0
    PINGCOUNTER=0
    ERROR_SUSPEND=0

    ### wait for wifi
    while wait_wlan; do
        if [ ${WLANCOUNTER} -gt 5 ]; then
            logger "Trying Wifi reconnect"
            /usr/bin/wpa_cli -i $NET reconnect
        fi
        if [ ${WLANCOUNTER} -gt 30 ]; then
            logger "No known wifi found"
            logger "DEBUG ifconfig $(ifconfig ${NET})"
            logger "DEBUG cmState $(lipc-get-prop com.lab126.wifid cmState)"
            logger "DEBUG signalStrength $(lipc-get-prop com.lab126.wifid signalStrength)"
            eips -f -g "${LIMGERRWIFI}"
            WLANNOTCONNECTED=1
            ERROR_SUSPEND=1 #short sleeptime will be activated
            break 1
        fi
        let WLANCOUNTER=WLANCOUNTER+1
        logger "Waiting for wifi ${WLANCOUNTER}"
        sleep $WLANCOUNTER
    done

    if [ ${WLANNOTCONNECTED} -eq 0 ]; then
        logger "Connected to wifi"

        ### lost standard gateway if wifi is not available
        GATEWAY=$(ip route | grep default | grep ${NET} | awk '{print $3}')
        logger "Found default gateway ${GATEWAY}"
        if [ -z "${GATEWAY}" ]; then
            route add default gw ${ROUTERIP}
            logger "Default gateway lost after sleep"
            logger "Setting default gateway to ${ROUTERIP}"
        fi

        echo "ping"

        ### wait for working ping
        while wait_ping; do
            if [ ${PINGCOUNTER} -gt 5 ]; then
                logger "Trying Wifi reconnect"
                /usr/bin/wpa_cli -i $NET reconnect
            fi
            if [ ${PINGCOUNTER} -gt 10 ]; then
                logger "Ping not working"
                logger "DEBUG ifconfig $(ifconfig ${NET})"
                CMSTATE=$(lipc-get-prop com.lab126.wifid cmState)
                logger "DEBUG cmState ${CMSTATE}"
                logger "DEBUG signalStrength $(lipc-get-prop com.lab126.wifid signalStrength)"
                eips -f -g "${LIMGERRWIFI}"
                PINGNOTWORKING=1
                SHORTSUSPEND=1 #short sleeptime will be activated
                break 1
            fi
            let PINGCOUNTER=PINGCOUNTER+1
            logger "Waiting for working ping ${PINGCOUNTER}"
            logger "Trying to set route gateway to ${ROUTERIP}"
            route add default gw ${ROUTERIP}
            sleep $PINGCOUNTER
        done

        if [ ${PINGNOTWORKING} -eq 0 ]; then
            logger "Ping worked successfully"

            echo "Downloading and drawing image"
            DOWNLOADRESULT=$(wget -q "$IMAGE_URI" -O $TMPFILE)
            logger "Download result ${DOWNLOADRESULT}"
            echo $DOWNLOADRESULT
            if $DOWNLOADRESULT; then
                mv $TMPFILE $SCREENSAVERFILE
                logger "Screen saver image file updated"
                if [ ${CLEAR_SCREEN_BEFORE_RENDER} -eq 1 ]; then
                    eips -c
                    sleep 1
                fi
                eips -f -g ${SCREENSAVERFILE}
            else
                logger "Error updating screensaver"
                if [ ${CLEAR_SCREEN_BEFORE_RENDER} -eq 1 ]; then
                    eips -c
                    sleep 1
                fi
                eips -f -g ${LIMGERR} #show error picture
                ERROR_SUSPEND=1       #short sleep time will be activated
            fi

            rm ${TMPFILE} -f
            logger "Removed temporary files"

            if [ ${CHECKBATTERY} -le ${BATTERYALERT} ]; then
                eips 2 2 -h " Battery at ${CHECKBATTERY}%, please charge "
            fi
        fi
    fi

    sleep $DELAY_BEFORE_SUSPEND

    echo "Calculate next timer and going to sleep"

    if [ ${ERROR_SUSPEND} -eq 1 ]; then
        let GLOBAL_ERROR_COUNT=GLOBAL_ERROR_COUNT+1
        TODAY=$(date +%s)
        WAKEUPTIME=$((${TODAY} + ${INTERVAL_ON_ERROR} - ${DELAY_BEFORE_SUSPEND}))
        logger "An error has occurred, will try again on ${WAKEUPTIME}"

        if [ ${GLOBAL_ERROR_COUNT} -ge 10 ]; then
            logger "REBOOT BECAUSE OF 10 ERRORS"
            reboot
        fi

        if [ ${USE_RTC} -eq 1 ]; then
            ./rtcwake -d rtc$RTC -s $INTERVAL_ON_ERROR -m mem
        else
            sleep $INTERVAL_ON_ERROR
        fi
    else
        GLOBAL_ERROR_COUNT=0
        TODAY=$(date +%s)
        WAKEUPTIME=$((${TODAY} + ${INTERVAL} - ${DELAY_BEFORE_SUSPEND}))
        logger "SUCCESS, will update again on ${WAKEUPTIME}"

        if [ ${USE_RTC} -eq 1 ]; then
            ./rtcwake -d rtc$RTC -s $INTERVAL -m mem
        else
            sleep $INTERVAL
        fi
    fi

done
