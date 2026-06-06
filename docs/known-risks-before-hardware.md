# Known Risks Before Hardware Validation

This repository has been statically validated on macOS, but the Raspberry Pi
hardware has not been available yet. Treat every runtime claim as unverified
until it passes on the actual Pi + KA11 + Aura Studio 3.

## macOS Static Validation Is Not Hardware Validation

`bash -n`, `shellcheck`, and grep checks catch syntax and obvious policy
mistakes. They do not prove:

- KA11 USB enumeration.
- PipeWire user-session behavior.
- Shairport Sync reaching `pipewire-pulse`.
- Spotify Connect discovery.
- Analog volume safety into the Aura Studio 3.

## Mac Simulation Is Not Raspberry Pi Validation

The `tests/` harness uses mocked command output on a Mac/dev machine. It is
useful for checking script branches, parsing, and safety gates, but it still is
not Raspberry Pi validation.

Mock tests only validate script logic. They do **not** validate:

- Real PipeWire or WirePlumber behavior.
- Real `pipewire-pulse` user-session routing.
- Real FiiO KA11 USB/ALSA/PipeWire enumeration.
- Real AirPlay visibility or playback.
- Real Spotify Connect visibility or playback.
- Real Bluetooth pairing, A2DP routing, or hijack behavior.
- Real analog output level or audio safety.

Passing `tests/run-static-checks.sh` and `tests/run-mock-tests.sh` means the
repository is better prepared for first hardware bring-up. It does not mean the
system has passed hardware validation.

## pipewire-pulse User Session Risk

PipeWire, WirePlumber, and `pipewire-pulse` usually run as user services.
Headless boot can fail if the user session is not available or linger is not
enabled. Symptom: `pactl info` fails, clients connect but produce no sound, or
user services do not survive reboot.

Mitigation: confirm `systemctl --user status pipewire pipewire-pulse wireplumber`
and `loginctl enable-linger "$USER"` where needed.

## Shairport Sync System Service To User Socket Risk

Shairport Sync is commonly installed as a system service, while `pipewire-pulse`
is a user socket. The system service may not inherit the right user environment
or PulseAudio socket path.

Symptom: AirPlay target appears but no sound, or logs show PulseAudio connection
errors.

Mitigation: collect `shairport-sync` logs, `pactl info`, and user PipeWire
service status. Do not switch to ALSA `hw:`/`plughw:` as a shortcut.

## KA11 Output Too Loud Risk

The KA11 is a headphone amplifier, not a fixed-level line-out. High digital
volume into the Aura Studio 3 AUX input can be dangerous or unpleasant.

Mitigation:

- Keep Aura Studio 3 physical volume low.
- Run `./scripts/safe-volume.sh` before playback.
- Keep source volume low.
- Raise volume slowly during bring-up.

`safe-volume.sh` is initialization only. `volume-guard-loop.sh` is recovery and
diagnostics only. Neither is real-time speaker protection.

## Bluetooth Routing Hijack Risk

Bluetooth A2DP can change PipeWire routing when a phone connects. It may
interrupt AirPlay or Spotify. Bluetooth is MVP Plus and should not be part of
first Phase 0-3 hardware bring-up.

Mitigation: leave Bluetooth alone until AirPlay/Spotify are validated, then use
`./scripts/bluetooth-routing-spike.sh` before trusting it.

## Safe Sink Unverified

The Safe Sink is implemented as a reversible Phase 5 spike, but it has not been
verified on hardware. Do not apply it during first bring-up.

Mitigation: first validate direct PipeWire -> KA11 behavior for AirPlay and
Spotify. Only later run the Safe Sink investigation and verification flow.

## DLNA Blocked

DLNA is blocked until real-time audio safety is verified. DLNA clients may send
unsafe volume commands, and Bash polling cannot stop instantaneous spikes.

Mitigation: do not run `./scripts/install-dlna.sh`, do not start
`gmrender.service`, and do not add a DLNA renderer manually.
