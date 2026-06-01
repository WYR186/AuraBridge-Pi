# Safe Rollback

Rollback means stopping AuraBridge audio services and disabling their autostart
without deleting user data, packages, source checkouts, or diagnostic logs.

Use this if first bring-up becomes confusing, too loud, or unstable.

## One-Command Rollback

```bash
./scripts/rollback-audio-services.sh
```

This stops/disables AuraBridge-related AirPlay, Spotify, and volume-guard
services. It does not remove packages and does not delete configs.

## Manual Rollback Commands

System services:

```bash
sudo systemctl stop shairport-sync.service || true
sudo systemctl stop nqptp.service || true
sudo systemctl disable shairport-sync.service || true
sudo systemctl disable nqptp.service || true
```

User services:

```bash
systemctl --user stop librespot.service || true
systemctl --user disable librespot.service || true
systemctl --user stop aurabridge-volume-guard.timer || true
systemctl --user stop aurabridge-volume-guard.service || true
systemctl --user disable aurabridge-volume-guard.timer || true
```

Bluetooth, only if it is causing trouble:

```bash
sudo systemctl stop bluetooth.service || true
sudo systemctl disable bluetooth.service || true
```

DLNA should not be running during first bring-up. If it somehow is:

```bash
systemctl --user stop gmrender.service || true
```

Do not enable it again until Safe Sink verification exists.

## Restore Configs From Backups

Some installer scripts create timestamped backups before writing config files.
If a config change needs to be reverted, inspect backups first:

```bash
ls -l /etc/shairport-sync.conf*
ls -l ~/.config/systemd/user/
```

Restore only the specific file you understand. Do not bulk-delete user data.

Example:

```bash
sudo cp -a /etc/shairport-sync.conf.bak.YYYYMMDDHHMMSS /etc/shairport-sync.conf
sudo systemctl restart shairport-sync.service
```

## What Rollback Must Not Do

- Do not delete `~/AuraBridge-Pi`.
- Do not delete `~/aurabridge-build`.
- Do not remove packages unless explicitly troubleshooting package state.
- Do not delete reports or logs.
- Do not reset the whole Pi while diagnostics are still needed.
- Do not route services directly to ALSA `hw:` or `plughw:` as a shortcut.
