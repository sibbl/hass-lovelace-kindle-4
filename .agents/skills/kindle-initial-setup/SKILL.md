---
name: kindle-initial-setup
description: Guide the first-time setup of this hass-lovelace-kindle-4 project on a Kindle 4 Non Touch. Use when installing the dashboard from scratch, preparing the Kindle jailbreak/USBNetwork/MKK/KUAL/kite prerequisites, configuring `extensions/homeassistant/config.sh`, copying the repo folders to `/mnt/us`, or validating the initial boot/startup workflow.
---

# Kindle Initial Setup

## Overview

Use this skill to guide a first installation of the Kindle-side Home Assistant dashboard scripts from this repository. Keep the workflow anchored to the files in this repo and the Kindle paths they expect.

## Repo Facts

- Copy local `extensions/homeassistant` to Kindle path `/mnt/us/extensions/homeassistant`.
- Copy local `kite` to Kindle path `/mnt/us/kite`.
- `kite/onboot/homeassistant.sh` backgrounds `/mnt/us/extensions/homeassistant/startup.sh`.
- `startup.sh` waits 120 seconds, then starts `/mnt/us/extensions/homeassistant/daemon.sh start`.
- `daemon.sh` runs `script.sh` and writes `/mnt/us/extensions/homeassistant/homeassistant.pid`.
- `script.sh` fetches `IMAGE_URI`, renders it with `eips`, then suspends with `rtcwake` unless `USE_RTC=0`.

## Initial Setup Workflow

1. Confirm prerequisites with the user:
   - Kindle 4 Non Touch is jailbroken.
   - USBNetwork is installed and SSH works.
   - Mobileread Kindle Kit is installed so KUAL can run.
   - KUAL v1 AZW is copied to `/mnt/us/documents`.
   - kite is installed so boot scripts in `/mnt/us/kite/onboot` run.

2. Configure the repository before copying:
   - Edit `extensions/homeassistant/config.sh`.
   - Set `IMAGE_URI` to the plain HTTP rendered-image endpoint.
   - Adjust `INTERVAL`, `INTERVAL_ON_ERROR`, `DELAY_BEFORE_SUSPEND`, battery thresholds, `PINGHOST`, and `ROUTERIP` for the local network.
   - Keep LF line endings on all `*.sh` files.

3. Validate local shell files before transfer:

```sh
sh -n extensions/homeassistant/config.sh
sh -n extensions/homeassistant/utils.sh
sh -n extensions/homeassistant/script.sh
sh -n extensions/homeassistant/startup.sh
sh -n kite/onboot/homeassistant.sh
bash -n extensions/homeassistant/daemon.sh
```

4. Copy files to the Kindle. Prefer `scp` or `rsync` using the actual SSH target configured for the device. USBNetwork commonly exposes the Kindle at `root@192.168.15.244`, but do not assume that if the user has a Wi-Fi IP or custom SSH config.

```sh
scp -r extensions/homeassistant root@KINDLE_HOST:/mnt/us/extensions/
scp -r kite root@KINDLE_HOST:/mnt/us/
```

5. Reboot the Kindle and watch the startup window:
   - `startup.sh` intentionally waits 120 seconds before starting the daemon.
   - Use this window to SSH in if immediate troubleshooting is needed.
   - After the delay, `daemon.sh start` begins the render/sleep loop.

6. Confirm first run:
   - Check `/mnt/us/extensions/homeassistant/homeassistant.log` when `LOGGING=1`.
   - Confirm `daemon.sh status` reports the service running after the startup delay.
   - Confirm the screen eventually renders the fetched image or one of the error images.

## Troubleshooting Checks

- If SSH disconnects after the dashboard starts, the script likely suspended the Kindle. Reboot and use the 120 second startup window, or connect during `DELAY_BEFORE_SUSPEND` after a render.
- If Wi-Fi works but routing is lost after sleep, verify `ROUTERIP` in `config.sh`; `script.sh` adds it as the default gateway when none is found.
- If the image never downloads, verify that `IMAGE_URI` is HTTP, not HTTPS, and that the Kindle can ping `PINGHOST`.
- If updates or debugging are needed on an already installed Kindle, switch to the `kindle-update-session` skill.
