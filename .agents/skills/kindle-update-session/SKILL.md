---
name: kindle-update-session
description: Guide a maintenance session for a Kindle that already has this hass-lovelace-kindle-4 project installed. Use when rebooting the Kindle, connecting by SSH during the configured startup or post-render window, stopping the queued startup/daemon so SSH remains connected, inspecting logs, updating files under `/mnt/us/extensions/homeassistant` or `/mnt/us/kite`, and restarting or validating the service after changes.
---

# Kindle Update Session

## Overview

Use this skill to keep an SSH session alive long enough to inspect, debug, or update an already installed Kindle dashboard. The key is to stop both the running daemon and any pending startup script before the render loop can suspend the device.

## Repo-Derived Timing

- Boot path: `kite/onboot/homeassistant.sh` runs `startup.sh` in the background.
- Startup window: `startup.sh` sleeps 120 seconds before `daemon.sh start`.
- Running loop: `script.sh` renders the image, waits `DELAY_BEFORE_SUSPEND`, then suspends with `rtcwake` when `USE_RTC=1`.
- Stop command: `sh /mnt/us/extensions/homeassistant/daemon.sh stop` sends HUP to the PID recorded in `/mnt/us/extensions/homeassistant/homeassistant.pid`.

## Maintenance Workflow

1. Prepare local changes before touching the Kindle:
   - Run the repo validation from `AGENTS.md`.
   - Keep the list of changed files small and know which paths must be copied.
   - Use the actual Kindle SSH target. USBNetwork commonly uses `root@192.168.15.244`; Wi-Fi installs may use a router-assigned IP or SSH alias.

2. Reboot or wake the Kindle, then connect during a known window:

```sh
ssh root@KINDLE_HOST
```

3. Immediately cancel any pending boot startup before it can launch the render loop:

```sh
ps | grep '[s]tartup.sh'
PID=$(ps | grep '[s]tartup.sh' | awk '{print $1}')
[ -n "$PID" ] && kill -HUP $PID
```

4. Stop the daemon if it is already running:

```sh
ps | grep '[s]cript.sh'
sh /mnt/us/extensions/homeassistant/daemon.sh stop
```

5. Confirm the device should stay reachable:

```sh
ps | grep '[s]tartup.sh'
ps | grep '[s]cript.sh'
sh /mnt/us/extensions/homeassistant/daemon.sh status
```

Expected result: no `startup.sh` process, no `script.sh` render loop, and the daemon status is stopped or reports a stale pidfile rather than a running process.

6. Inspect logs and state as needed:

```sh
tail -n 100 /mnt/us/extensions/homeassistant/homeassistant.log
cat /mnt/us/extensions/homeassistant/config.sh
ls -la /mnt/us/extensions/homeassistant
```

7. Copy updates from the local machine. Prefer `rsync` when available locally; fall back to `scp` if needed:

```sh
rsync -av extensions/homeassistant/ root@KINDLE_HOST:/mnt/us/extensions/homeassistant/
rsync -av kite/ root@KINDLE_HOST:/mnt/us/kite/
```

8. Restart and validate on the Kindle:

```sh
sh /mnt/us/extensions/homeassistant/daemon.sh start
sh /mnt/us/extensions/homeassistant/daemon.sh status
tail -n 100 /mnt/us/extensions/homeassistant/homeassistant.log
```

## Choosing The Connection Window

- Prefer the boot window when doing planned updates. Reboot, connect within 120 seconds, stop `startup.sh` first, then stop the daemon.
- Use the post-render window only for quick emergency stops. It lasts `DELAY_BEFORE_SUSPEND` seconds after drawing, which defaults to 10 seconds in `config.sh`.
- If the Kindle suspends before commands complete, reboot and use the boot window; do not rely on repeated post-render attempts for multi-file updates.

## Validation Boundary

These steps are validated against the repository scripts, but a live Kindle session still depends on the device's USBNetwork or Wi-Fi SSH configuration. When using this skill, explicitly confirm the actual `KINDLE_HOST`, whether the connection is USBNetwork or Wi-Fi, and whether `startup.sh` or `script.sh` is currently running before copying updates.
