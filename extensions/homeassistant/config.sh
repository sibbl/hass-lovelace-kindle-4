#!/bin/sh

INTERVAL=60                             # (sec) - how often to update the script
IMAGE_URI="http://example.org/test.png" # URL of image to fetch. Keep in mind that the Kindle 4 does not support SSL/TLS requests
CLEAR_SCREEN_BEFORE_RENDER=0            # If "1", then the screen is completely cleared before rendering the newly fetched image to avoid "shadows".
INTERVAL_ON_ERROR=30                    # In case of errors, the device waits this long until the next loop.
BATTERYALERT=15                         # if the battery level is equal to or below this threshold, a info will be displayed
BATTERYLOW=5                            # if the battery level is equal to or below this threshold, the "please charge" image will be shown and the device will sleep for a long time until it checks again (or boots up and starts the script again)
BATTERYSLEEP=3600                       # 1 day sleep time when Battery Level is equal or below the "BATTERYLOW" threshold, see above.
PINGHOST="www.google.com"               # which domain (or IP) to ping to check internet connectivity.
ROUTERIP="192.168.0.1"                  # router gateway IP. The Kindle appears to sometimes forget the gateway's IP and we need to set this manually.
LOGGING=1                               # if enabled, the script logs into a file
DELAY_BEFORE_SUSPEND=10                 # seconds to wait between drawing image and suspending. This gives you time to SSH into your device if it's inside the photo frame and stop the daemon

NAME=homeassistant
NAMEOLD=homeassistant_old
SCRIPTDIR="/mnt/us/extensions/homeassistant"
LOGFILE="${SCRIPTDIR}/${NAME}.log"

NET="wlan0"

LIMG="${SCRIPTDIR}"
LIMGBATT="${SCRIPTDIR}/low_battery.png"
LIMGERR="${SCRIPTDIR}/error.png"
LIMGERRWIFI="${SCRIPTDIR}/wifi.png"

TMPFILE="${SCRIPTDIR}/cover.temp.png"
SCREENSAVERFILE="${SCRIPTDIR}/cover.png"

USE_RTC=1 # if 0, only sleep will be used (which is useful for debugging)
RTC=1     # use rtc1 by default
