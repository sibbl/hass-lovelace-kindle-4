#!/bin/sh
PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export PATH

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
CHARGING_ERROR_COUNT=0
CHARGING_RECOVERY_FILE="${SCRIPTDIR}/charging-recovery-attempts"
CHARGING_REBOOT_LIMIT=2

while true; do
    echo "Starting new loop"
    logger "START NEW LOOP"

    logger "Set CPU scaling governer to powersave"
    echo powersave >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

    logger "Set prevent screen saver to true"
    lipc-set-prop com.lab126.powerd preventScreenSaver 1

    echo "Check battery level"

    CHARGING_FILE=`kdb get system/driver/charger/SYS_CHARGING_FILE`
    IS_CHARGING=$(cat $CHARGING_FILE)
    CHECKBATTERY=$(gasgauge-info -s | sed 's/.$//')
    CHECKCHARGECURRENT=$(gasgauge-info -l | sed 's/mA//g')
    
	logger "Battery: isCharging=${IS_CHARGING} percentage=${CHECKBATTERY}% current=${CHECKCHARGECURRENT}mA" 

    if [ ${IS_CHARGING} -eq 1 ] && [ ${CHECKBATTERY} -le ${RESTART_POWERD_THRESHOLD} ] && [ ${CHECKCHARGECURRENT} -le 0 ]; then
        let CHARGING_ERROR_COUNT=CHARGING_ERROR_COUNT+1
        logger "Charging current is negative, attempt ${CHARGING_ERROR_COUNT}"
        if [ ${CHECKBATTERY} -le ${BATTERYLOW} ]; then
            logger "Battery is critically low, attempting charging recovery immediately"
            CHARGING_ERROR_COUNT=3
        fi
    else
        CHARGING_ERROR_COUNT=0
        rm -f "${CHARGING_RECOVERY_FILE}"
    fi

    if [ ${CHARGING_ERROR_COUNT} -ge 3 ]; then
        CHARGING_REBOOT_COUNT=0
        if [ -s "${CHARGING_RECOVERY_FILE}" ]; then
            CHARGING_REBOOT_COUNT=$(cat "${CHARGING_RECOVERY_FILE}")
        fi

        case "${CHARGING_REBOOT_COUNT}" in
        ''|*[!0-9]*)
            CHARGING_REBOOT_COUNT=0
            ;;
        esac

        if [ ${CHARGING_REBOOT_COUNT} -lt ${CHARGING_REBOOT_LIMIT} ]; then
            let CHARGING_REBOOT_COUNT=CHARGING_REBOOT_COUNT+1
            echo "${CHARGING_REBOOT_COUNT}" >"${CHARGING_RECOVERY_FILE}"
            logger "Charging did not recover, rebooting device (attempt ${CHARGING_REBOOT_COUNT}/${CHARGING_REBOOT_LIMIT})"
            sync
            /sbin/reboot
            sleep 300
        else
            logger "Charging did not recover after ${CHARGING_REBOOT_COUNT} reboots, sleeping for ${BATTERYSLEEP} seconds"
            ./rtcwake -d rtc$RTC -s $BATTERYSLEEP -m mem
            sleep 30
        fi

        CHARGING_ERROR_COUNT=0
        continue
    fi
    
    if [ ${CHECKBATTERY} -le ${BATTERYLOW} ]; then
        logger "Battery below ${BATTERYLOW}"
        eips -f -g "${LIMGBATT}"
        ./rtcwake -d rtc$RTC -s $BATTERYSLEEP -m mem
        sleep 30 # waiting time when charging until battery level is higher than "BATTERYLOW" otherwise it will fall into sleep again
        continue
    else
        logger "Remaining battery ${CHECKBATTERY}"
    fi

    ### activate wifi
    logger "Enabling and checking wifi"
    lipc-set-prop com.lab126.wifid enable 1

    echo "Check wifi connection"
    WLANNOTCONNECTED=0
    WLANCOUNTER=0
    ERROR_SUSPEND=0

    ### wait for wifi
    while wait_wlan; do
        if [ ${WLANCOUNTER} -eq 5 ]; then
            logger "Trying Wifi reconnect"
            /usr/bin/wpa_cli -i $NET reconnect
        fi
        if [ ${WLANCOUNTER} -gt 15 ]; then
            logger "No known wifi found"
            logger "DEBUG ifconfig $(ifconfig ${NET})"
            logger "DEBUG cmState $(lipc-get-prop com.lab126.wifid cmState)"
            logger "DEBUG signalStrength $(lipc-get-prop com.lab126.wifid signalStrength)"
            if [ -s "${SCREENSAVERFILE}" ]; then
                logger "Keeping existing screen saver image after wifi error"
            else
                eips -f -g "${LIMGERRWIFI}"
            fi
            WLANNOTCONNECTED=1
            ERROR_SUSPEND=1 #short sleeptime will be activated
            break 1
        fi
        let WLANCOUNTER=WLANCOUNTER+1
        logger "Waiting for wifi ${WLANCOUNTER}"
        sleep 2
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

        echo "Downloading and drawing image"
        DOWNLOADRESULT=$(download_image 2>&1)
        DOWNLOADSTATUS=$?
        logger "Download result ${DOWNLOADRESULT}"
        echo "$DOWNLOADRESULT"
        if [ ${DOWNLOADSTATUS} -eq 0 ]; then
            mv $TMPFILE $SCREENSAVERFILE
            logger "Screen saver image file updated"
            if [ ${CLEAR_SCREEN_BEFORE_RENDER} -eq 1 ]; then
                eips -c
                sleep 1
            fi
            eips -f -g ${SCREENSAVERFILE}
        else
            logger "Error updating screensaver"
            DOWNLOAD_ERROR_IMAGE="${LIMGERR}"
            CMSTATE=$(lipc-get-prop com.lab126.wifid cmState 2>/dev/null)
            IFCONFIG_OUTPUT=$(ifconfig ${NET} 2>/dev/null)
            GATEWAY=$(ip route | grep default | grep ${NET} | awk '{print $3}')
            logger "DEBUG ifconfig ${IFCONFIG_OUTPUT}"
            logger "DEBUG cmState ${CMSTATE}"
            logger "DEBUG signalStrength $(lipc-get-prop com.lab126.wifid signalStrength 2>/dev/null)"
            logger "DEBUG default gateway ${GATEWAY}"

            if ! echo "${CMSTATE}" | grep CONNECTED >/dev/null 2>&1; then
                logger "Download failed and wifi is not connected"
                DOWNLOAD_ERROR_IMAGE="${LIMGERRWIFI}"
            elif ! echo "${IFCONFIG_OUTPUT}" | grep "inet addr:" >/dev/null 2>&1; then
                logger "Download failed and wifi has no IP address"
                DOWNLOAD_ERROR_IMAGE="${LIMGERRWIFI}"
            elif [ -z "${GATEWAY}" ]; then
                logger "Download failed and no default gateway is configured"
                DOWNLOAD_ERROR_IMAGE="${LIMGERRWIFI}"
            else
                logger "Download failed while wifi appears connected; treating as server/download error"
            fi

            if [ -s "${SCREENSAVERFILE}" ]; then
                logger "Keeping existing screen saver image after download error"
            else
                if [ ${CLEAR_SCREEN_BEFORE_RENDER} -eq 1 ]; then
                    eips -c
                    sleep 1
                fi
                eips -f -g ${DOWNLOAD_ERROR_IMAGE} #show error picture
            fi
            ERROR_SUSPEND=1       #short sleep time will be activated
        fi

        rm -f "${TMPFILE}"
        logger "Removed temporary files"

        if [ ${CHECKBATTERY} -le ${BATTERYALERT} ]; then
            eips 2 2 -h " Battery at ${CHECKBATTERY}%, please charge "
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
            /sbin/reboot
        fi

        if [ ${USE_RTC} -eq 1 ]; then
            logger "Staying awake for error retry for ${INTERVAL_ON_ERROR} seconds"
            sleep $INTERVAL_ON_ERROR
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
