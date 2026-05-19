# Repository Guidance

## Project Shape

- This repository contains the Kindle-side scripts for a Kindle 4 Non Touch Home Assistant Lovelace dashboard.
- The deployed Kindle paths are fixed: `extensions/homeassistant` is copied to `/mnt/us/extensions/homeassistant`, and `kite/onboot/homeassistant.sh` is copied to `/mnt/us/kite/onboot/homeassistant.sh`.
- The runtime is an old Kindle/Linux environment with BusyBox-era userland. Keep shell changes conservative and avoid assuming GNU-only options.

## Working On Scripts

- Treat `extensions/homeassistant/config.sh` as user-editable configuration.
- Keep `extensions/homeassistant/script.sh`, `utils.sh`, and `startup.sh` compatible with the Kindle shell environment; prefer simple POSIX-style shell unless an existing script already uses Bash.
- `extensions/homeassistant/daemon.sh` is Bash and controls the long-running `script.sh` process through `/mnt/us/extensions/homeassistant/homeassistant.pid`.
- Do not modify binary/image assets such as `extensions/homeassistant/rtcwake`, `*.png`, or `assets/*.jpg` unless the task explicitly requires it.
- Preserve LF line endings for all shell scripts.

## Validation

- Run shell syntax checks after script edits:

```sh
sh -n extensions/homeassistant/config.sh
sh -n extensions/homeassistant/utils.sh
sh -n extensions/homeassistant/script.sh
sh -n extensions/homeassistant/startup.sh
sh -n kite/onboot/homeassistant.sh
bash -n extensions/homeassistant/daemon.sh
```

- When changing download behavior, account for the Kindle 4 limitation documented in `README.md`: the image URL must be plain HTTP because SSL/TLS is not supported by the device workflow.
- When changing sleep, startup, or update behavior, validate against these repository facts:
  - `kite/onboot/homeassistant.sh` starts `startup.sh` in the background.
  - `startup.sh` waits 120 seconds, then runs `daemon.sh start`.
  - `script.sh` waits `DELAY_BEFORE_SUSPEND` seconds after rendering before suspending.

## Local Skills

- Use `.agents/skills/kindle-initial-setup` when guiding a first-time installation of this project on a Kindle.
- Use `.agents/skills/kindle-update-session` when connecting to an already installed Kindle for debugging or file updates.
