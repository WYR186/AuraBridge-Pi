# First Boot Runbook

This is the exact command order for the first Raspberry Pi hardware validation.
Run as the normal Pi user over SSH. Do not run as root.

Keep the Aura Studio 3 physical volume LOW for every audio step.

## Command Sequence

```bash
cd ~/AuraBridge-Pi
./scripts/setup-base.sh
./scripts/setup-pipewire.sh
./scripts/wireplumber-version-check.sh
./scripts/check-ka11.sh
./scripts/safe-volume.sh
./scripts/install-airplay2.sh
./scripts/install-spotify.sh
./scripts/status.sh
./scripts/logs.sh
```

## Before Running

- Confirm the KA11 is plugged into the Pi, not a laptop.
- Confirm the AUX cable runs KA11 -> Aura Studio 3 AUX-IN.
- Confirm the Aura Studio 3 physical volume is low.
- Prefer Ethernet for first boot.
- Run `./scripts/preflight-pi.sh` if anything about the host is uncertain.

## Stop Conditions

Stop and collect a report with `./scripts/collect-report.sh` if:

- `preflight-pi.sh` warns that the host is not a Raspberry Pi.
- `setup-pipewire.sh` cannot start or reach PipeWire.
- `check-ka11.sh` does not report PASS.
- `safe-volume.sh` cannot set the default sink volume.
- AirPlay or Spotify can see the device but no sound reaches the KA11.
- Any playback becomes unexpectedly loud.

## Explicit Non-Steps

Do not run these during first boot:

```bash
./scripts/setup-safe-sink.sh --apply
./scripts/test-safe-sink.sh
./scripts/install-dlna.sh
systemctl --user start gmrender.service
```

Do not edit WirePlumber policy. Do not add ALSA `hw:` or `plughw:` routes.
