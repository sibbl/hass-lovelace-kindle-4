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

1. Prefer the bundled shell script for update sessions:

```sh
.agents/skills/kindle-update-session/scripts/kindle-update-session.sh deploy
```

The script defaults to `KINDLE_HOST=192.168.0.172` and `KINDLE_USER=root`. It waits for SSH, cancels a pending `startup.sh`, stops the daemon and any leftover `script.sh` processes if present, copies `extensions/homeassistant` and `kite`, restarts the daemon, and prints process/service status.

By default it does not overwrite `/mnt/us/extensions/homeassistant/config.sh`, because that file contains device-specific settings.

Never overwrite the Kindle's `config.sh` blindly. Before any config deploy, read the current remote file and preserve a backup. The bundled script enforces this: `DEPLOY_CONFIG=yes` first reads the Kindle config, writes a local backup under `.git/kindle-update-session-backups/`, writes a remote backup next to the original config, and prints the current remote config. It then refuses to overwrite unless `CONFIRM_DEPLOY_CONFIG=yes` is also set.

Use `DEPLOY_CONFIG=yes` without confirmation only to inspect and back up the current Kindle config:

```sh
DEPLOY_CONFIG=yes .agents/skills/kindle-update-session/scripts/kindle-update-session.sh deploy
```

Use both flags only after reviewing the printed remote config and intentionally deciding to replace it:

```sh
DEPLOY_CONFIG=yes CONFIRM_DEPLOY_CONFIG=yes .agents/skills/kindle-update-session/scripts/kindle-update-session.sh deploy
```

The script expects non-interactive SSH by default. If it reports `Permission denied (publickey,password)`, configure an SSH key for `root@KINDLE_HOST` first, or run with `KINDLE_SSH_BATCH_MODE=no` for an interactive password prompt:

```sh
KINDLE_SSH_BATCH_MODE=no .agents/skills/kindle-update-session/scripts/kindle-update-session.sh deploy
```

Use these variants when needed:

```sh
KINDLE_HOST=192.168.0.172 .agents/skills/kindle-update-session/scripts/kindle-update-session.sh wait
KINDLE_HOST=192.168.0.172 .agents/skills/kindle-update-session/scripts/kindle-update-session.sh stop
KINDLE_HOST=192.168.0.172 .agents/skills/kindle-update-session/scripts/kindle-update-session.sh status
```

2. Prepare local changes before touching the Kindle:
   - Run the repo validation from `AGENTS.md`.
   - Keep the list of changed files small and know which paths must be copied.
   - Use the actual Kindle SSH target. USBNetwork commonly uses `root@192.168.15.244`; Wi-Fi installs may use a router-assigned IP or SSH alias.

3. Reboot or wake the Kindle, then connect during a known window:

```sh
ssh root@KINDLE_HOST
```

4. Immediately cancel any pending boot startup before it can launch the render loop:

```sh
ps | grep '[s]tartup.sh'
PID=$(ps | grep '[s]tartup.sh' | awk '{print $1}')
[ -n "$PID" ] && kill -HUP $PID
```

5. Stop the daemon if it is already running:

```sh
ps | grep '[s]cript.sh'
sh /mnt/us/extensions/homeassistant/daemon.sh stop
PIDS=$(ps | grep '[s]cript.sh' | awk '{print $1}')
[ -n "$PIDS" ] && kill -HUP $PIDS
```

6. Confirm the device should stay reachable:

```sh
ps | grep '[s]tartup.sh'
ps | grep '[s]cript.sh'
sh /mnt/us/extensions/homeassistant/daemon.sh status
```

Expected result: no `startup.sh` process, no `script.sh` render loop, and the daemon status is stopped or reports a stale pidfile rather than a running process.

7. Inspect logs and state as needed:

```sh
[ -f /mnt/us/extensions/homeassistant/homeassistant.log ] && tail -100 /mnt/us/extensions/homeassistant/homeassistant.log
cat /mnt/us/extensions/homeassistant/config.sh
ls -la /mnt/us/extensions/homeassistant
```

8. Copy updates from the local machine. Prefer `rsync` when available locally; fall back to `scp` if needed:

```sh
rsync -rltv --no-owner --no-group --no-perms extensions/homeassistant/ root@KINDLE_HOST:/mnt/us/extensions/homeassistant/
rsync -rltv --no-owner --no-group --no-perms kite/ root@KINDLE_HOST:/mnt/us/kite/
```

9. Restart and validate on the Kindle:

```sh
sh /mnt/us/extensions/homeassistant/daemon.sh start
sh /mnt/us/extensions/homeassistant/daemon.sh status
[ -f /mnt/us/extensions/homeassistant/homeassistant.log ] && tail -100 /mnt/us/extensions/homeassistant/homeassistant.log
```

## Choosing The Connection Window

- Prefer the boot window when doing planned updates. Reboot, connect within 120 seconds, stop `startup.sh` first, then stop the daemon.
- Use the post-render window only for quick emergency stops. It lasts `DELAY_BEFORE_SUSPEND` seconds after drawing, which defaults to 10 seconds in `config.sh`.
- If the Kindle suspends before commands complete, reboot and use the boot window; do not rely on repeated post-render attempts for multi-file updates.

## Validation Boundary

These steps are validated against the repository scripts, but a live Kindle session still depends on the device's USBNetwork or Wi-Fi SSH configuration. When using this skill, explicitly confirm the actual `KINDLE_HOST`, whether the connection is USBNetwork or Wi-Fi, and whether `startup.sh` or `script.sh` is currently running before copying updates.

The bundled script is intentionally polling SSH rather than ping. The Kindle may answer only briefly between render/suspend cycles, and SSH availability is the condition that matters for stopping the service.
