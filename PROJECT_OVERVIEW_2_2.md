# AuraBridge Pi 2.2 Project Overview

> This file is the English source of truth for the project. It is a faithful
> Markdown rendering of `AuraBridge Pi 2.2 Project Overview.docx`. If this file
> and any script/doc disagree, this file wins.

## 1. Project Summary

AuraBridge Pi 2.2 is a Raspberry Pi 4 based multi-protocol wireless audio
receiver for a Harman Kardon Aura Studio 3 speaker.

The Raspberry Pi receives audio through AirPlay 2, Spotify Connect, Bluetooth
A2DP, and optional DLNA / UPnP. It routes audio through PipeWire and
WirePlumber to a controlled audio path, then to a FiiO KA11 Type-C USB DAC /
headphone amplifier. The KA11 outputs analog audio through a 3.5 mm AUX cable
into the Aura Studio 3.

The project does not modify the speaker internally. The Raspberry Pi works as
an external audio bridge.

**Main signal path:**

```
User devices
  -> AirPlay 2 / Spotify Connect / Bluetooth A2DP / optional DLNA
  -> Raspberry Pi 4
  -> PipeWire + WirePlumber
  -> AuraBridge Safe Sink (preferred controlled sink)
  -> PipeWire limiter or fixed-gain stage (if verified)
  -> FiiO KA11 Type-C USB DAC
  -> 3.5 mm AUX
  -> Harman Kardon Aura Studio 3
```

## 2. Version 2.2 Design Changes

Version 2.2 makes the following corrections:

- `volume-guard-loop.sh` is **not** a real-time safety mechanism.
- Polling-based volume correction is only for recovery, audit, and diagnostics.
- Real-time audio safety must be implemented inside the PipeWire / WirePlumber
  audio graph, or risky clients must remain disabled.
- DLNA is blocked until a PipeWire-level limiter, virtual safe sink,
  fixed-gain stage, or equivalent hard cap is verified.
- The FiiO KA11 physical sink should not be exposed as the default sink for
  normal clients if a Safe Sink is implemented.
- WirePlumber policy must be written according to the actual installed
  WirePlumber version. Do not blindly copy latest WirePlumber examples.
- Shairport Sync should use the PulseAudio backend through `pipewire-pulse`
  for the MVP.
- The MVP controller should be Bash scripts plus systemd services/timers,
  not FastAPI or Node.js.

## 3. Main Goal

Build a stable, headless, practical multi-protocol audio bridge for daily home
use. The system must support:

- AirPlay 2 from iPhone, iPad, and Mac
- Spotify Connect through librespot
- Bluetooth A2DP for Android, Xiaomi, Samsung, and PC devices
- Optional DLNA / UPnP **only after** real-time safety is verified
- FiiO KA11 USB DAC output
- Safe initial volume
- Real-time audio safety layer before risky clients
- Service health checks
- Useful diagnostic logs
- systemd startup and recovery

## 4. Non-Goals

Do not attempt:

- Native Xiaomi MiPlay receiver support
- Samsung SmartThings / Tap Sound / Music Share emulation
- Full Google Cast / Chromecast receiver
- Internal modification of the Aura Studio 3
- Raspberry Pi onboard 3.5 mm output as the final output
- Passive Type-C to 3.5 mm analog passthrough adapters
- Apple Home app stability as a required feature
- Pure ALSA direct output as the multi-protocol default
- FastAPI or Node.js controller in the MVP
- Polling-based Bash volume guard as a real-time safety mechanism
- DLNA before real-time audio safety is verified

## 5. Required Hardware

- Raspberry Pi 4 Model B
- microSD card, 32 GB or larger recommended
- Official or high quality 5V 3A USB-C power supply
- USB-A male to Type-C female adapter
- FiiO KA11 Type-C USB DAC / headphone amplifier
- 3.5 mm AUX cable
- Harman Kardon Aura Studio 3

Optional: Ethernet cable, Raspberry Pi case, heatsink or fan, powered USB hub,
I2C OLED display, physical button for Bluetooth pairing or safe-volume reset.

## 6. FiiO KA11 Requirements

The FiiO KA11 Type-C is the project DAC. The agent must verify that it is
detected by Linux as a USB audio device.

Required checks:

- `lsusb`
- `aplay -l`
- `amixer -c <card_id> scontrols`
- `alsamixer -c <card_id>`
- `pipewire --version`
- `wireplumber --version`
- `wpctl status`
- `pactl list sinks short`

Expected outcome: KA11 appears in `lsusb`, appears as an ALSA sound card,
appears as a PipeWire sink, WirePlumber version is recorded, hardware mixer
behavior is documented, the default output path can route audio to KA11, and
test audio can play through KA11 into the Aura Studio 3.

If the KA11 does not appear as a USB audio device, **stop the setup and report
the error.**

## 7. Important KA11 Safety Warning

The KA11 is a USB DAC / headphone amplifier. **It is not a fixed-level line-out
device.** When connected to an active speaker AUX input, high output volume can
cause very loud sound. The system must apply safe volume before any real
playback test.

Initial safety values:

- PipeWire default sink volume: 20% to 30%
- Maximum normal testing volume: 45%
- Aura Studio 3 physical volume: low
- Phone / source device volume: low
- DLNA: disabled until real-time safety is verified

Required command for initial safe volume:

```
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.30
wpctl set-mute   @DEFAULT_AUDIO_SINK@ 0
```

Important: this command is only initialization. It is not a real-time limiter.
It does not protect against instant volume spikes from untrusted clients.

## 8. Audio Architecture

The system must use PipeWire and WirePlumber as the main audio routing layer.

```
Shairport Sync (AirPlay 2)
librespot (Spotify Connect)
BlueZ + PipeWire Bluetooth (A2DP)
Optional DLNA renderer (blocked until safe)
        |
        v
pipewire-pulse / PipeWire
        |
        v
PipeWire media graph
        |
        v
WirePlumber policy manager
        |
        v
AuraBridge Safe Sink (preferred)
        |
        v
Limiter or fixed-gain stage (if verified)
        |
        v
FiiO KA11 USB DAC sink
        |
        v
3.5 mm AUX output
        |
        v
Aura Studio 3
```

Do not route all services directly to ALSA hardware devices such as `hw:1,0`
or `plughw:1,0`. Direct ALSA output can cause device locking problems in a
multi-protocol system.

## 9. Real-Time Audio Safety Requirement

This is the most important 2.2 correction.

Do not treat `scripts/volume-guard-loop.sh` as a real-time safety mechanism.
It is only recovery, audit, diagnostics, and post-failure correction.
It is **not** a limiter, hard cap, speaker protection, or real-time safety
layer.

Why: if a client sends `SetVolume=100%` and the script checks every 5 seconds,
the speaker can still play at full volume for several seconds. That is
unacceptable.

Required design direction: create an AuraBridge Safe Sink whenever possible;
route normal clients to the Safe Sink, not directly to KA11; route the Safe
Sink through a PipeWire filter-chain limiter or fixed-gain stage; only then
route audio to the KA11 physical sink.

If a real-time safety layer cannot be verified: keep DLNA disabled, keep
untrusted clients disabled, and do not claim the system is protected by
`volume-guard-loop.sh`.

## 10. AuraBridge Safe Sink Design

Preferred path:

```
Normal clients -> AuraBridge Safe Sink -> limiter or fixed-gain stage
  -> FiiO KA11 physical sink -> AUX -> Aura Studio 3
```

The KA11 physical sink should not be the default sink for normal clients if the
Safe Sink is implemented. The agent must not assume that a limiter plugin
exists. Before implementing the Safe Sink, inspect the system with
`pipewire --version`, `wireplumber --version`, `pw-cli ls Node`,
`wpctl status`, `ls /usr/lib/*/ladspa`, `ls /usr/lib/*/lv2`.

Safe Sink acceptance: clients can output to AuraBridge Safe Sink; audio reaches
KA11 through a controlled path; KA11 physical sink is not the normal default
sink; output gain is safe; 100% client volume does not create dangerous analog
output. If this cannot be verified, DLNA remains disabled.

## 11. Shairport Sync AirPlay 2 Design

Use NQPTP, Shairport Sync, PulseAudio backend, `pipewire-pulse`, PipeWire,
FiiO KA11.

MVP output path:

```
Shairport Sync -> PulseAudio backend -> pipewire-pulse -> PipeWire
  -> AuraBridge Safe Sink (if implemented) -> FiiO KA11
```

Do not use the native PipeWire backend as the MVP default.

Before building, inspect available configure options:

```
./configure --help | grep -i pulse
./configure --help | grep -i airplay
```

Preferred configure idea:

```
./configure --sysconfdir=/etc \
  --with-pa \
  --with-soxr \
  --with-avahi \
  --with-ssl=openssl \
  --with-systemd-startup \
  --with-airplay-2
```

If `--with-pa` is not the correct flag, use the PulseAudio backend flag shown
by `./configure --help`. Target AirPlay name: **Aura Studio 3 AirPlay**.

AirPlay acceptance: NQPTP active; Shairport Sync active; `pipewire-pulse`
active; iPhone or Mac sees "Aura Studio 3 AirPlay"; audio plays through KA11
and Aura Studio 3; PipeWire shows the stream; no ALSA device locking conflict;
output level is safe.

## 12. Spotify Connect Design

Use librespot.

```
librespot -> PulseAudio-compatible output -> pipewire-pulse -> PipeWire
  -> AuraBridge Safe Sink (if implemented) -> FiiO KA11
```

Target Spotify name: **Aura Studio 3 Spotify**.

Acceptance: Spotify app sees the device; playback works; no ALSA device
locking conflict with AirPlay; output level is safe.

## 13. Bluetooth A2DP Design

Use BlueZ, PipeWire Bluetooth support, WirePlumber BlueZ monitor, FiiO KA11
sink. Target Bluetooth name: **Aura Studio 3 BT**. Bluetooth must not be
permanently discoverable.

Required script `scripts/bt-pairing-window.sh`, basic behavior:
`bluetoothctl discoverable on`, `sleep 120`, `bluetoothctl discoverable off`.

Bluetooth routing must be tested. Do not assume the default WirePlumber policy
will be ideal. Required Bluetooth routing spike: record PipeWire/WirePlumber
versions; identify 0.4.x vs 0.5.x+; use version-matched docs only; pair an
Android phone; check `wpctl status` before and after connection; check
`pactl list sink-inputs`; play AirPlay then connect Bluetooth; play Spotify then
connect Bluetooth; document whether Bluetooth hijacks routing; if hijack
occurs, add version-specific mitigation.

If Bluetooth is too disruptive, the MVP may keep Bluetooth disabled by default
and enable it manually only when needed.

## 14. WirePlumber Version Policy

This is a hard requirement. Before writing any WirePlumber policy, run
`wireplumber --version`, `wpctl status`, `pw-cli info all`. Then:

- If WirePlumber is 0.4.x: use 0.4 Lua-style configuration and 0.4-era docs.
- If WirePlumber is 0.5.x or newer: use the newer SPA-JSON / JSON-style config.
- Do not blindly copy latest WirePlumber examples.
- Do not assume a 0.5.x config works on 0.4.x.
- Do not assume a 0.4.x Lua rule works on 0.5.x.

Any WirePlumber configuration change must document: installed version, config
directory used, config syntax used, files modified, reason for change, and
rollback instructions.

## 15. DLNA / UPnP Design

DLNA is blocked by default. Do not enable DLNA until real-time audio safety is
verified. Possible tools: gmrender-resurrect, Rygel. DLNA must not rely on
`volume-guard-loop.sh`.

DLNA unlock requirements: AuraBridge Safe Sink (or equivalent protected route)
exists; KA11 physical sink is not directly exposed as default sink;
PipeWire-level limiter, fixed-gain filter, or hard cap is verified; 100%
client-side volume command does not create dangerous analog output; test
performed with Aura Studio 3 physical volume low; quick disable script exists;
exact renderer and client behavior is documented.

If these requirements are not met: keep DLNA disabled; do not install DLNA as
an enabled startup service; do not include DLNA in the MVP acceptance criteria.

## 16. Controller Design

Do not use FastAPI or Node.js in the MVP. Use Bash scripts, systemd services,
systemd timers, SSH, journalctl. Possible future UI: tiny Python
`http.server`, OLED status display, physical pairing button, physical
safe-volume reset button.

## 17. Required Repository Structure

```
AuraBridge-Pi/
  README.md
  WHITEPAPER_2_2.md
  PROJECT_OVERVIEW_2_2.md
  TROUBLESHOOTING.md
  scripts/
    setup-base.sh
    setup-pipewire.sh
    check-ka11.sh
    safe-volume.sh
    volume-guard-loop.sh
    install-airplay2.sh
    install-spotify.sh
    setup-bluetooth.sh
    bt-pairing-window.sh
    bluetooth-routing-spike.sh
    wireplumber-version-check.sh
    setup-safe-sink.sh
    test-safe-sink.sh
    install-dlna.sh
    status.sh
    logs.sh
  systemd/
    aurabridge-volume-guard.service
    aurabridge-volume-guard.timer
    aurabridge-health.service
    librespot.service
    gmrender.service
  docs/
    hardware.md
    ka11-validation.md
    audio-routing.md
    volume-safety.md
    safe-sink.md
    bluetooth-policy.md
    wireplumber-versioning.md
    airplay2.md
    spotify.md
    dlna.md
```

## 18. Required Scripts (behavior summary)

- **check-ka11.sh** — print USB devices, ALSA cards, KA11 mixer controls,
  PipeWire/WirePlumber versions, PipeWire status, available sinks, default
  sink. Fail clearly if KA11 is not detected.
- **safe-volume.sh** — `wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.30` and
  `wpctl set-mute @DEFAULT_AUDIO_SINK@ 0`. Initialization only, not a
  real-time safety mechanism.
- **volume-guard-loop.sh** — periodically check default sink volume; clamp
  back if it exceeds the configured maximum. Suggested: safe 0.30, max 0.45,
  interval 5–10 s. Recovery and diagnostics only; not speaker protection; not
  a DLNA justification.
- **wireplumber-version-check.sh** — print WirePlumber/PipeWire versions,
  config directories, likely config model (0.4 Lua vs 0.5+ SPA-JSON), and a
  warning not to copy mismatched docs.
- **setup-safe-sink.sh** — attempt to create or document a protected output
  path. If it cannot, print "Real-time audio safety layer not verified. DLNA
  must remain disabled." (Future phase.)
- **status.sh** — print AuraBridge Pi status, hostname, IP, KA11 detection,
  PipeWire/WirePlumber versions, default sink + volume, Safe Sink status,
  AirPlay/NQPTP/Spotify/Bluetooth/DLNA service status, recent errors.
- **logs.sh** — collect journals for shairport-sync, nqptp, bluetooth,
  librespot, user pipewire/wireplumber, and USB dmesg lines.

## 19. Development Phases

- **Phase 0 — Preparation:** prepare OS image, SD card, power supply, adapter,
  KA11, AUX cable, Ethernet if possible, and this overview + prompts.
- **Phase 1 — Base OS + PipeWire + WirePlumber + KA11 Validation:** boot Pi,
  install PipeWire/WirePlumber, detect KA11, record versions, document mixer
  behavior, set safe volume, play test audio. Acceptance: SSH reachable; KA11
  in `lsusb`/`aplay -l`/`wpctl status`; versions recorded; mixer documented;
  safe volume works; test audio plays at low volume.
- **Phase 2 — AirPlay 2:** install NQPTP; build/install Shairport Sync with
  AirPlay 2 + PulseAudio backend; route through `pipewire-pulse` to KA11 or
  Safe Sink. Acceptance: target appears; playback works; PipeWire shows
  stream; no ALSA locking; output level safe.
- **Phase 3 — Spotify Connect:** install librespot as a systemd service; route
  through `pipewire-pulse` to KA11 or Safe Sink. Acceptance: device visible;
  playback works; no AirPlay conflict; output level safe.
- **Phase 4 — Bluetooth A2DP** (not in this build).
- **Phase 5 — Real-Time Audio Safety / Safe Sink** (not in this build).
- **Phase 6 — Optional DLNA** (not in this build).
- **Phase 7 — Optional Convenience Layer** (not in this build).

## 20. Core MVP Acceptance Criteria

- [ ] Raspberry Pi 4 boots headless
- [ ] SSH works
- [ ] FiiO KA11 is detected
- [ ] PipeWire sees KA11
- [ ] PipeWire version is recorded
- [ ] WirePlumber version is recorded
- [ ] KA11 hardware mixer behavior is documented
- [ ] Safe initial volume is applied
- [ ] AirPlay 2 works
- [ ] Spotify Connect works
- [ ] Services survive reboot
- [ ] `status.sh` reports meaningful state
- [ ] `logs.sh` collects useful diagnostics

## 21–23. Later-phase acceptance criteria

MVP Plus (Bluetooth), Real-Time Safety (Safe Sink / limiter), and Optional
DLNA acceptance criteria apply to Phases 4–6 and are out of scope for this
build. See sections 9–15 for the safety constraints that gate them.

## 24. Major Risks and Mitigations

| Risk | Severity | Mitigation |
| --- | --- | --- |
| ALSA device locking | High | Use PipeWire / pipewire-pulse, avoid direct `hw:` output |
| DLNA volume spike | High | Keep DLNA blocked until Safe Sink / limiter is verified |
| Bash volume guard race condition | High | Treat polling as recovery only |
| Bluetooth auto-connect interruption | Medium | Controlled pairing, routing spike, version-specific WirePlumber policy |
| WirePlumber version mismatch | High | Detect version first, use matching docs |
| KA11 output too loud | High | Low physical volume, safe initial volume, hardware mixer check |
| USB DAC not detected | High | Validate KA11 with `check-ka11.sh` |
| Wi-Fi instability | Medium | Prefer Ethernet or stable 5 GHz Wi-Fi |
| Apple Home app instability | Low | Best-effort only |
| Controller over-engineering | Low | Use Bash + systemd in MVP |

## 25. Recommended MVP Scope

First build: Raspberry Pi OS Lite 64-bit, PipeWire, WirePlumber, FiiO KA11
validation, safe initial volume, NQPTP, Shairport Sync AirPlay 2 through
PulseAudio backend, librespot Spotify Connect, status and logs scripts.

Then add: Bluetooth A2DP with controlled pairing, Bluetooth routing spike,
WirePlumber version-specific policy only if needed.

Only after that add: AuraBridge Safe Sink, PipeWire limiter or fixed-gain
route, optional DLNA after safety verification.

## 26. Final Definition

AuraBridge Pi 2.2 is a Raspberry Pi 4 based multi-protocol audio bridge that
turns a traditional AUX speaker into a practical network audio endpoint. The
core 2.2 rule is:

- Audio safety must be real-time and inside the audio graph.
- Polling scripts are not speaker protection.
- DLNA stays disabled until a Safe Sink, limiter, or equivalent hard cap is
  verified.
- WirePlumber policy must match the installed WirePlumber version.
