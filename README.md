# Kindle 4 Non Touch Home Assistant Lovelace Dashboard

This repository describes the hardware part behind a Kindle 4 based eink dashboard.

A lovelace UI panel of your Home Assistant instance is rendered to an image and polled from a jailbroken Kindle 4 on a regular basis.

![Outside photo](https://raw.githubusercontent.com/sibbl/hass-lovelace-kindle-4/main/assets/front.jpg)

## Software

I keep this short as I think this should be pretty straight forward.

1. Set up [Home Assistant](http://home-assistant.io/) on the platform of your choice.
1. Set up the rendering software i.e. using docker, [see my hass-lovelace-kindle-screensaver](https://github.com/sibbl/hass-lovelace-kindle-screensaver/) repository.

Hint 1: there's an `eink` HA theme inside this repository which you can configure for your newly created panel.

Hint 2: I recommend installing this kiosk extension (i.e. via HACS) to remove the UI app header bar.

You should end up with a URL pointing to the exposed port from the docker container to configure on your kindle in the following section.

Important: this URL needs to be plain HTTP as no TLS or SSL is supported by the Kindle 4. If your server is HTTPS only (which is a good thing!), I recommend using a free CDN like [hostry](https://www.hostry.com).

## Hardware

While the software part should be the same for other Kindle models like Paperwhites, the following section specifically addresses the Kindle 4 non touch.

If you're using a Paperwhite, it's probably better to use the [online screensaver extension](https://www.mobileread.com/forums/showthread.php?t=236104). It uses features like `rtcwake` and `upscript` which are not available on the Kindle 4 NT out of the box.

Thus, a bit more work was necessary to get a reliable solution which I describe below. This solution is approved by my parents as they have this system and code running in their kitchen.

1. Jailbreak your Kindle 4 Non Touch [as described here](https://www.mobileread.com/forums/showthread.php?t=191158).
1. Install USBNetwork so that you can SSH into your device. [See download including instructions here](https://www.mobileread.com/forums/showthread.php?t=88004).
1. Install mkk certificates so that KUAL can be used. [See download including instructions here](https://www.mobileread.com/forums/showthread.php?t=233932).
1. Install kite so that we can start our script on each boot. [See download including instructions here](https://www.mobileread.com/forums/showthread.php?t=168270) - I've used the `kite.sh` from the `kite.gz` download.
1. Copy KUAL v1 azw file into `/mnt/us/documents` [as described here](https://www.mobileread.com/forums/showthread.php?t=203326).
1. Clone this repository. **Important for Windows users**: ensure that the `*.sh` files have LF line endings and NOT CRLF.
1. Set the variables at the top of this repository's `extensions/homeassistant/script.sh`.
    - If you want to run the device on battery, I recommend increasing the `INTERVAL` (so that it suspends longer) and decrease `DELAY_BEFORE_SUSPEND` so that the (artificial) delay between drawing the image and suspending is as low as possible. But please keep in mind that this wasn't what I've built the script for. E.g. the online screensaver extension supports configuring a scheduler to run less frequent at night and save battery.
1. Copy `homeassistant` and `kite` folders from this repository into `/mnt/us/` on the device.
1. Reboot your device and the script should run 2 minutes after sucessful boot.

### Changing config or debugging

There are two possibilities to SSH into your Kindle to change your config or debug if something didn't work as expected.

1. The `extensions/homeassistant/startup.sh` sleeps 2 minutes until it starts the daemon on boot. On boot, you have time to SSH into your kindle.
1. After drawing the image, the `extensions/homeassistant/script.sh` sleeps a short time until it suspends - see the `DELAY_BEFORE_SUSPEND` config option. This gives you time to SSH into your device and stop the daemon using `sh /mnt/us/extensions/homeassistant/daemon.sh stop`.

For debugging purposes, `LOGGING` can be configured to `1` so that an extended log is written to `extensions/homeassistant/homeassistant.log`.

## Photo frame

Similarly to [this project](https://marios-blog.com/2020/01/22/digitaler-bilderrahmen-mit-kindle-paperwhite/), I've bought a 13x18 cm photo frame from an online store over here in Germany.

We removed the front cover of the Kindle 4 and also decided to remove the backside and remove the mainboard from the frame as there wasn't enough space to plug a Micro USB cable into the device's bottom while keeping it centered. A 90 degree adapter might be a better choice, also depending on the exact size of the frame.

![Inside photo](https://raw.githubusercontent.com/sibbl/hass-lovelace-kindle-4/main/assets/inside.jpg)

## My sources and similar projects

- The rtcwake binary inside `extensions/homeassistant` was taken from [this post from Stefan Strobel](https://www.mobileread.com/forums/showpost.php?p=3009582&postcount=36).
- [nicoh88's kindle-kt3_weatherdisplay_battery-optimized](https://github.com/nicoh88/kindle-kt3_weatherdisplay_battery-optimized) is the origin of most code and the images.
- [Mario's adaptations](https://marios-blog.com/2020/01/22/digitaler-bilderrahmen-mit-kindle-paperwhite/), which is based on nicoh88's repository.
  - Even for non-Germans I recommend scrolling through the article as it also shows a different approach to the photo frame.

The following two projects were my inspiration and I've also used them for quite some time. However, manually rebooting or charging the device was necessary too often and would've never gotten an approval by my parents.

- [Online screensaver extension](https://www.mobileread.com/forums/showthread.php?t=236104)
- [FHEM Kindle Display](https://wiki.fhem.de/wiki/Kindle_Display)