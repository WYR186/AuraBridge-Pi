# Mac / Dev-Machine Simulation Tests

These tests exercise AuraBridge shell-script logic without Raspberry Pi
hardware. They are intentionally conservative and do **not** validate real audio
behavior.

## What This Tests

- Bash syntax for repository scripts.
- ShellCheck, when installed.
- Safety grep checks for forbidden patterns.
- `check-ka11.sh` PASS/FAIL behavior under mocked USB/ALSA/PipeWire outputs.
- `wireplumber-version-check.sh` 0.4 vs 0.5 guidance.
- `status.sh` degraded and service-present summaries.
- `safe-volume.sh` behavior when mocked `wpctl` exists.
- `install-dlna.sh` refusal when Safe Sink verification is missing.

## What This Does Not Test

- Real Raspberry Pi hardware.
- Real FiiO KA11 enumeration.
- Real PipeWire, WirePlumber, or `pipewire-pulse` graph behavior.
- Real AirPlay, Spotify, Bluetooth, or DLNA.
- Real analog output level or speaker safety.

Mock tests must never be described as hardware validation.

## Run Static Checks

```bash
tests/run-static-checks.sh
```

## Run Mock Tests

```bash
tests/run-mock-tests.sh
```

Outputs are written to:

```text
tests/reports/mock-tests-<timestamp>/
```

`tests/reports/` is intentionally ignored by git.

## Mock Cases

- `case-ka11-present`: KA11 appears in `lsusb`, `aplay`, `wpctl`, and `pactl`.
- `case-ka11-missing`: no KA11 appears.
- `case-pipewire-missing`: KA11 appears at USB/ALSA, but PipeWire tools are
  intentionally missing.
- `case-wireplumber-04`: WirePlumber reports `0.4.x` for Lua-style guidance.
- `case-wireplumber-05`: WirePlumber reports `0.5.x` for SPA-JSON guidance.
- `case-services-present`: AirPlay, Spotify, Bluetooth, and PipeWire services
  report active via mocked `systemctl`.
