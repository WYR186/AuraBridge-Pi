# AuraBridge Pi

AuraBridge Pi 2.2 is a Raspberry Pi 4 based, headless, multi-protocol wireless
audio receiver for a **Harman Kardon Aura Studio 3** speaker.

The Pi receives audio over the network (AirPlay 2, Spotify Connect, later
Bluetooth A2DP and optionally DLNA), routes it through **PipeWire + WirePlumber**,
and sends it out through a **FiiO KA11 Type-C USB DAC** over a 3.5 mm AUX cable
into the Aura Studio 3. The speaker is never opened or modified — the Pi is an
external bridge.

> **Output is selectable.** Before the USB dongle arrives you can run the same
> stack out of the Pi's built-in 3.5 mm AUX jack, then switch to the KA11 with a
> single command — see [docs/onboard-audio.md](docs/onboard-audio.md). Pick the
> output with `./scripts/select-output.sh onboard|usb|auto`.

> **Current validation status:** Phase 0–3 are implemented, and Phase 4–6 now
> have conservative scripts and documentation. This checkout was updated on a
> development Mac, **not** on the actual Raspberry Pi, so Phase 4–6 are
> implemented but **not hardware-validated**. Do not claim Bluetooth routing,
> the Safe Sink, or DLNA are safe until the runbook checks pass on the Pi.

## Signal path (current build)

```
iPhone / iPad / Mac (AirPlay 2)   Spotify app (Spotify Connect)
                       \             /
                        v           v
                 Shairport Sync   librespot
                        \           /
                         v         v
                       pipewire-pulse
                            |
                            v
                    PipeWire + WirePlumber
                            |
                            v
                 default sink = FiiO KA11 USB DAC   (dynamically detected)
                            |
                            v
                       3.5 mm AUX
                            |
                            v
                   Harman Kardon Aura Studio 3
```

The **AuraBridge Safe Sink** and a real-time limiter sit between PipeWire and
the KA11 in the *target* architecture, but they are a later phase. In this
build, clients reach the KA11 through PipeWire/`pipewire-pulse` only — never by
direct ALSA `hw:`/`plughw:` routing.

## Hardware

Required:

- Raspberry Pi 4 Model B
- microSD card (32 GB or larger recommended)
- Official / high quality 5V 3A USB-C power supply
- USB-A male to Type-C female adapter
- FiiO KA11 Type-C USB DAC / headphone amplifier
- 3.5 mm AUX cable
- Harman Kardon Aura Studio 3

Optional: Ethernet cable, case, heatsink/fan, powered USB hub, I2C OLED, a
physical button. See [docs/hardware.md](docs/hardware.md).

## Implemented scope

- **Phase 0** — Repository, documentation, script skeletons, and safety rules.
- **Phase 1** — Base OS prep; install PipeWire + WirePlumber; **dynamically**
  detect and validate the FiiO KA11; record PipeWire/WirePlumber versions;
  apply a safe initial volume; status & logs tooling. *No WirePlumber policy is
  written.*
- **Phase 2** — Build & install NQPTP and Shairport Sync with **AirPlay 2 +
  the native PipeWire backend**. Device name:
  `Aura Studio 3 AirPlay`.
- **Phase 3** — Install **librespot** for Spotify Connect through
  `pipewire-pulse` / PipeWire. Device name: `Aura Studio 3 Spotify`.
- **Phase 4** — Bluetooth A2DP setup with a controlled pairing window and an
  observe-only routing spike. Bluetooth is MVP Plus, not core MVP.
- **Phase 5** — Reversible AuraBridge Safe Sink spike using a PipeWire
  filter-chain fixed-gain stage. It can be installed and tested, but is **not
  verified** until the real Pi + KA11 + Aura Studio 3 test writes
  `SAFE_SINK_VERIFIED=yes`.
- **Phase 6** — DLNA installer and gmrender user service are present but
  hard-gated. DLNA refuses to proceed until Phase 5 real-time safety is
  verified, and it is never enabled by default.

## What is NOT implemented yet

- **Web UI / OLED / physical buttons** (Phase 7): not present.
- **WirePlumber policy files**: still not written. Any Bluetooth routing
  mitigation must be version-specific and explicitly approved later.
- **Verified real-time speaker protection**: not claimed until Phase 5 is run
  on the actual Pi and passes.

## Safety warnings (read before any playback)

- The **FiiO KA11 is a DAC / headphone amplifier, not a fixed-level line-out.**
  Its output can be loud. Keep the Aura Studio 3 physical volume **low** and the
  source device volume **low** for the first tests.
- `scripts/safe-volume.sh` sets the PipeWire default sink to **1.00** and
  unmutes it. This is **initialization only**, *not* real-time protection.
- `scripts/volume-guard-loop.sh` is **recovery, audit, and diagnostics only**.
  Polling **does not** prevent sudden volume spikes and **does not** make DLNA
  safe. It must never be cited as speaker protection.
- **DLNA stays blocked** until a Safe Sink / real-time limiter / hard cap is
  implemented and verified in a later phase.
- Always check the installed **WirePlumber version first** before touching any
  policy. None is touched in this build. See
  [docs/wireplumber-versioning.md](docs/wireplumber-versioning.md).

## Basic run order (on the Raspberry Pi)

```bash
# Phase 1
./scripts/setup-base.sh
./scripts/setup-pipewire.sh
./scripts/wireplumber-version-check.sh

# --- Choose the audio output --------------------------------------------------
# No USB dongle yet? Use the Pi's built-in 3.5 mm AUX jack:
./scripts/setup-onboard-audio.sh        # enables the jack (may need one reboot)
./scripts/select-output.sh onboard
# Have the FiiO KA11 USB dongle (小尾巴)? Use it instead (or 'auto'):
# ./scripts/select-output.sh usb
# -----------------------------------------------------------------------------

./scripts/check-output.sh               # validates whichever output is selected
./scripts/safe-volume.sh

# Phase 2 (AirPlay 2)
./scripts/install-airplay2.sh

# Phase 3 (Spotify Connect)
./scripts/install-spotify.sh

# Optional: barge-in arbiter (install only by default; validate before enabling)
./scripts/install-arbiter.sh
# ./scripts/install-arbiter.sh --enable

# Phase 4-6 are gated; start only after Phase 0-3 are validated on the Pi.
./scripts/setup-bluetooth.sh
./scripts/bt-pairing-window.sh
./scripts/bluetooth-routing-spike.sh
./scripts/setup-safe-sink.sh
# Optional, only after reviewing the probe:
# ./scripts/setup-safe-sink.sh --apply
# ./scripts/test-safe-sink.sh
# ./scripts/install-dlna.sh   # refuses unless Safe Sink is verified
# ./scripts/install-dlna.sh --start
# ./scripts/start-discovery-stack.sh --check-only  # AirPlay + DLNA visible together

# Anytime
./scripts/status.sh
./scripts/logs.sh
```

A fresh-install walkthrough with manual checks after each phase is in
[docs/runbook-phase-0-3.md](docs/runbook-phase-0-3.md).
Phase 4–6 are covered in [docs/runbook-phase-4-6.md](docs/runbook-phase-4-6.md).

## Documentation

- [docs/RASPBERRY_PI_SETUP.md](docs/RASPBERRY_PI_SETUP.md) — Pi connection info & headless mode setup ⭐ **Start here**
- [docs/RASPBERRY_PI_CREDENTIALS.md](docs/RASPBERRY_PI_CREDENTIALS.md) — SSH credentials & system info (secured)
- [docs/hardware.md](docs/hardware.md) — hardware and wiring
- [docs/onboard-audio.md](docs/onboard-audio.md) — onboard 3.5 mm AUX output & switching to the USB dongle
- [docs/ka11-validation.md](docs/ka11-validation.md) — KA11 detection & mixer
- [docs/audio-routing.md](docs/audio-routing.md) — PipeWire routing model
- [docs/volume-safety.md](docs/volume-safety.md) — the volume safety rules
- [docs/wireplumber-versioning.md](docs/wireplumber-versioning.md) — version policy
- [docs/airplay2.md](docs/airplay2.md) — AirPlay 2 setup & test
- [docs/spotify.md](docs/spotify.md) — Spotify Connect setup & test
- [docs/field-note-2026-06-06-airplay-dlna-recovery.md](docs/field-note-2026-06-06-airplay-dlna-recovery.md) — confirmed Pi4 AirPlay success; Android/DLNA not yet usable
- [docs/pi-bringup-checklist.md](docs/pi-bringup-checklist.md) — first hardware checklist
- [docs/first-boot-runbook.md](docs/first-boot-runbook.md) — exact first-boot command order
- [docs/pass-fail-matrix.md](docs/pass-fail-matrix.md) — bring-up PASS/WARN/FAIL criteria
- [docs/rollback.md](docs/rollback.md) — safe service rollback commands
- [docs/known-risks-before-hardware.md](docs/known-risks-before-hardware.md) — risks before Pi validation
- [docs/runbook-phase-0-3.md](docs/runbook-phase-0-3.md) — full runbook
- [docs/runbook-phase-4-6.md](docs/runbook-phase-4-6.md) — Bluetooth, Safe Sink, gated DLNA
- [docs/bluetooth-policy.md](docs/bluetooth-policy.md) — controlled Bluetooth policy
- [docs/safe-sink.md](docs/safe-sink.md) — Safe Sink design, verification, rollback
- [docs/dlna.md](docs/dlna.md) — DLNA gate and safe manual procedure
- [docs/source-arbiter.md](docs/source-arbiter.md) — barge-in arbiter: newest source wins, all protocols stay discoverable
- [docs/airplay-takeover-and-discovery.md](docs/airplay-takeover-and-discovery.md) — why a 2nd phone can't see/take over a busy AirPlay device (Wi-Fi power save + session interruption)
- [docs/field-note-2026-06-06-reboot-no-sound.md](docs/field-note-2026-06-06-reboot-no-sound.md) — reboot "connects but no sound" (Safe Sink → KA11 rebind), offline Pi, and the permanent fixes
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — common problems
- [PROJECT_OVERVIEW_2_2.md](PROJECT_OVERVIEW_2_2.md) — English source of truth
- [WHITEPAPER_2_2.md](WHITEPAPER_2_2.md) — design whitepaper

## Controller philosophy

Bash scripts + systemd units only. No FastAPI, no Node.js. This keeps the
bridge debuggable and dependency-light on a headless Pi.
