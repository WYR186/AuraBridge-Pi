# Raspberry Pi Bring-Up Checklist

Use this checklist the first time AuraBridge Pi runs on real Raspberry Pi
hardware. The goal is a safe, repeatable Phase 0-3 validation only.

Do **not** run Phase 4-6 experiments during first bring-up. Do not enable DLNA,
do not apply the Safe Sink, and do not write WirePlumber policy.

## 0. Bench Setup

- [ ] Raspberry Pi 4 is powered by a known-good 5V 3A USB-C supply.
- [ ] Ethernet is connected if possible. Prefer Ethernet over Wi-Fi for first
      setup so SSH, package installs, mDNS, AirPlay, and Spotify debugging are
      simpler.
- [ ] FiiO KA11 is connected to a Raspberry Pi USB-A port through the USB-A
      male to Type-C female adapter.
- [ ] The adapter is a real data adapter, not charge-only.
- [ ] 3.5 mm AUX cable is connected from KA11 to Aura Studio 3 AUX-IN.
- [ ] Aura Studio 3 is powered on, set to AUX/input mode if needed, and its
      physical volume is LOW.
- [ ] Phone/source device volume is LOW.
- [ ] Do not use the Raspberry Pi onboard 3.5 mm output.

## 1. SSH Login

- [ ] Boot Raspberry Pi OS Lite 64-bit.
- [ ] SSH into the Pi as the normal user, not root.
- [ ] Confirm the repo is at `~/AuraBridge-Pi`:

```bash
cd ~/AuraBridge-Pi
```

- [ ] Run the Pi preflight:

```bash
./scripts/preflight-pi.sh
```

If this warns that it is not a Raspberry Pi, stop and confirm you are on the
right host.

## 2. Base System

- [ ] Install base tools:

```bash
./scripts/setup-base.sh
```

- [ ] Install PipeWire, WirePlumber, and pipewire-pulse:

```bash
./scripts/setup-pipewire.sh
```

- [ ] Record WirePlumber version. This is informational only during bring-up;
      do not write policy:

```bash
./scripts/wireplumber-version-check.sh
```

## 3. KA11 Validation

- [ ] Confirm KA11 appears at USB, ALSA, and PipeWire layers:

```bash
./scripts/check-ka11.sh
```

Required outcome: **PASS**. If it fails, stop and fix hardware before installing
AirPlay or Spotify.

- [ ] Apply safe initial volume:

```bash
./scripts/safe-volume.sh
```

Remember: this is only initialization. It is not real-time speaker protection.

## 4. First Low-Volume Audio Test

- [ ] Confirm Aura Studio 3 physical volume is still LOW.
- [ ] Play a short, quiet test only after KA11 validation and `safe-volume.sh`.
- [ ] Do not exceed 45% during bring-up.

## 5. AirPlay Install And Test

- [ ] Install AirPlay 2 receiver:

```bash
./scripts/install-airplay2.sh
```

- [ ] Confirm services:

```bash
systemctl status nqptp --no-pager
systemctl status shairport-sync --no-pager
```

- [ ] On iPhone/Mac, confirm **Aura Studio 3 AirPlay** appears.
- [ ] Play a quiet track and confirm sound through the KA11/AUX path.

## 6. Spotify Install And Test

- [ ] Re-assert safe volume:

```bash
./scripts/safe-volume.sh
```

- [ ] Install Spotify Connect:

```bash
./scripts/install-spotify.sh
```

- [ ] Confirm user service:

```bash
systemctl --user status librespot.service --no-pager
```

- [ ] In Spotify app, confirm **Aura Studio 3 Spotify** appears.
- [ ] Play a quiet track and confirm sound through the KA11/AUX path.

## 7. Status, Logs, And Report

- [ ] Capture the normal status/log view:

```bash
./scripts/status.sh
./scripts/logs.sh
```

- [ ] Capture a diagnostic bundle:

```bash
./scripts/collect-report.sh
```

Attach the resulting `reports/aurabridge-report-<timestamp>.tar.gz` if asking
for help.

## What Not To Run Yet

- [ ] Do not run `./scripts/setup-safe-sink.sh --apply`.
- [ ] Do not run `./scripts/test-safe-sink.sh` until basic AirPlay/Spotify
      bring-up is stable and you intentionally enter Phase 5.
- [ ] Do not run `./scripts/install-dlna.sh`.
- [ ] Do not enable or start `gmrender.service`.
- [ ] Do not modify WirePlumber policy.
- [ ] Do not route services directly to ALSA `hw:` or `plughw:` devices.
- [ ] Do not treat `volume-guard-loop.sh` as real-time speaker protection.
