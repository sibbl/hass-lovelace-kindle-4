#!/bin/sh

INTERVAL=60 # (sec) - how often to update the script
IMAGE_URI="http://example.org/test.png" # URL of image to fetch. Keep in mind that the Kindle 4 does not support SSL/TLS requests
CLEAR_SCREEN_BEFORE_RENDER=0 # If "1", then the screen is completely cleared before rendering the newly fetched image to avoid "shadows".
INTERVAL_ON_ERROR=30   # In case of errors, the device waits this long until the next loop.
BATTERYALERT=15   # if the battery level is equal to or below this threshold, a info will be displayed
BATTERYLOW=5      # if the battery level is equal to or below this threshold, the "please charge" image will be shown and the device will sleep for a long time until it checks again (or boots up and starts the script again)
BATTERYSLEEP=3600 # 1 day sleep time when Battery Level is equal or below the "BATTERYLOW" threshold, see above.
ROUTERIP="192.168.0.1" # router gateway IP. The Kindle appears to sometimes forget the gateway's IP and we need to set this manually.
LOGGING=1 # if enabled, the script logs into a file
DELAY_BEFORE_SUSPEND=10 # seconds to wait between drawing image and suspending. This gives you time to SSH into your device if it's inside the photo frame and stop the daemon

NAME=homeassistant
NAMEOLD=homeassistant_old
SCRIPTDIR="/mnt/us/extensions/homeassistant"
LOGFILE="${SCRIPTDIR}/${NAME}.log"

NET="wlan0"
RTC=1

LIMG="${SCRIPTDIR}"
LIMGBATT="${SCRIPTDIR}/low_battery.png"
LIMGERR="${SCRIPTDIR}/error.png"
LIMGERRWIFI="${SCRIPTDIR}/wifi.png"

TMPFILE="${SCRIPTDIR}/cover.temp.png"
SCREENSAVERFILE="${SCRIPTDIR}/cover.png"


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
    mkdir /mnt/us/update.bin.tmp.partial  -f # prevent from Amazon updates
    touch /mnt/us/WIFI_NO_NET_PROBE # do not perform a WLAN test
}

wait_wlan() {
    return $(lipc-get-prop com.lab126.wifid cmState | grep CONNECTED | wc -l)
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

kill_kindle
customize_kindle

while true; do
    echo "Starting new loop"
    logger "START NEW LOOP"

    logger "Set CPU scaling governer to powersave"
    echo powersave >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

    logger "Set prevent screen saver to true"
    lipc-set-prop com.lab126.powerd preventScreenSaver 1

    echo "Check battery levle"
    CHECKBATTERY=$(gasgauge-info -s | sed 's/.$//')
    if [ ${CHECKBATTERY} -le ${BATTERYLOW} ]; then
        logger "Battery below ${BATTERYLOW}"
        eips -f -g "${LIMGBATT}"
        ./rtcwake -d rtc$RTC -s $BATTERYSLEEP -m mem
        sleep 30 # waiting time when charging until battery level is higher than "BATTERYLOW" otherwise it will fall into sleep again
    else
        logger "Remaining battery ${CHECKBATTERY}"
    fi

    ### activate WLAN
    logger "Enabling and checking wifi"
    lipc-set-prop com.lab126.wifid enable 1

    echo "Check wifi connection"
    WLANNOTCONNECTED=0
    WLANCOUNTER=0
    ERROR_SUSPEND=0

    ### wait for WLAN
    while wait_wlan; do
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

        ### lost Standard Gateway if WLAN`s not available
        GATEWAY=$(ip route | grep default | grep ${NET} | awk '{print $3}')
        logger "Found default gateway ${GATEWAY}"
        if [ -z "${GATEWAY}" ]; then
            route add default gw ${ROUTERIP}
            logger "Default gateway lost after sleep"
            logger "Setting default gateway to ${ROUTERIP}"
        fi

        ### download using cURL

        echo "Downloading and drawing image"
        rm $TMPFILE -f
        if wget -q "$IMAGE_URI" -O $TMPFILE; then
            mv $TMPFILE $SCREENSAVERFILE
            logger "Screen saver image file updated"
            if [ ${CLEAR_SCREEN_BEFORE_RENDER} -eq 1 ]; then
                eips -c
                sleep 1
            fi
            eips -f -g ${SCREENSAVERFILE} #load picture to screen
        else
            logger "Error updating screensaver"
            if [ ${CLEAR_SCREEN_BEFORE_RENDER} -eq 1 ]; then
                eips -c
                sleep 1
            fi
            eips -f -g ${LIMGERR}   #show error picture
            ERROR_SUSPEND=1          #short sleep time will be activated
        fi

        ### delete temp. files
        rm ${TMPFILE} -f
        logger "Removed temporary files"

        if [ ${CHECKBATTERY} -le ${BATTERYALERT} ]; then
            eips 2 2 -h " Akku bei 10 Prozent, bitte aufladen "
        fi

    fi
    
    sleep $DELAY_BEFORE_SUSPEND

    echo "Calculate next timer and going to sleep"
    ### calculate and set WAKEUPTIMER
    if [ ${ERROR_SUSPEND} -eq 1 ]; then
        TODAY=$(date +%s)
        WAKEUPTIME=$((${TODAY} + ${INTERVAL_ON_ERROR} - ${DELAY_BEFORE_SUSPEND}))
        logger "An error has occurred, will try again on ${WAKEUPTIME}"
        ./rtcwake -d rtc$RTC -s $INTERVAL_ON_ERROR -m mem
    else
        TODAY=$(date +%s)
        WAKEUPTIME=$((${TODAY} + ${INTERVAL} - ${DELAY_BEFORE_SUSPEND}))
        logger "SUCCESS, will update again on ${WAKEUPTIME}"
        ./rtcwake -d rtc$RTC -s $INTERVAL -m mem
    fi
done
