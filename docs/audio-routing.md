# Audio Routing (Phase 0–3)

## The rule that shapes everything

**No service routes directly to ALSA `hw:`/`plughw:` devices.** Every client
goes through PipeWire (natively or via `pipewire-pulse`). Direct ALSA output
lets one service grab the KA11 exclusively and produces `Device or resource
busy` the moment a second protocol tries to play. PipeWire is the single sound
server that multiplexes all sources onto the one USB DAC.

## Current (Phase 0–3) graph

```
Shairport Sync (PulseAudio backend)     librespot (pulseaudio backend)
              \                                 /
               \                               /
                v                             v
                        pipewire-pulse
                            |
                            v
                  PipeWire media graph
                            |
                            v
                 WirePlumber (default policy, UNMODIFIED)
                            |
                            v
              default sink = FiiO KA11 USB DAC sink
                            |
                            v
                       3.5 mm AUX  ->  Aura Studio 3
```

In this build there is **no AuraBridge Safe Sink and no limiter** yet. The KA11
sink is allowed to be the default sink because that is the only safe,
PipeWire-mediated path available before the Safe Sink phase. Clients still never
touch ALSA directly.

## Target graph (later phases — for context only)

```
clients -> pipewire-pulse -> PipeWire -> AuraBridge Safe Sink
        -> limiter / fixed-gain stage -> KA11 physical sink -> AUX -> speaker
```

Once the Safe Sink exists (Phase 5), normal clients target the Safe Sink and the
**KA11 physical sink stops being the default**. That is also the precondition
for ever enabling DLNA (Phase 6). None of that is done here.

## Selecting the physical output (onboard AUX vs USB dongle)

The final `default sink` above can be **either** the FiiO KA11 USB DAC **or** the
Pi's onboard 3.5 mm AUX (`bcm2835 Headphones`). Which one is used is decided by
the shared selector ([`scripts/lib/output-target.sh`](../scripts/lib/output-target.sh)),
not by anything hardcoded in the routing graph:

```bash
./scripts/select-output.sh onboard   # Pi built-in 3.5 mm jack
./scripts/select-output.sh usb       # USB DAC dongle (小尾巴 / KA11)
./scripts/select-output.sh auto      # prefer the dongle when present, else onboard (default)
```

Either way the device is referenced by its **dynamically detected PipeWire sink
name**, never an ALSA card number, and clients never touch `hw:`/`plughw:`. The
Safe Sink (below) targets whichever output is selected. Full details:
[onboard-audio.md](onboard-audio.md).

## Why PulseAudio backend (not native PipeWire)

For the MVP, Shairport Sync and librespot use their **PulseAudio** output, which
connects to `pipewire-pulse`. The PulseAudio API path is mature and behaves
consistently across distro/PipeWire versions, which matters more in a
multi-protocol box than in an AirPlay-only one. The native PipeWire backends are
intentionally **not** the MVP default. See [airplay2.md](airplay2.md) and
[spotify.md](spotify.md).

## Default sink and where to look

- `wpctl status` — shows nodes and which sink is default (`*`).
- `pactl list sinks short` — PulseAudio-API view of the same sinks.
- `pactl list sink-inputs` — which client streams are currently routed.

To make the KA11 the default (if it is not): find its node ID in `wpctl status`,
then `wpctl set-default <ID>`. Do **not** hardcode an ALSA card number anywhere.

## What we deliberately do NOT do in Phase 0–3

- No `hw:`/`plughw:` client routing.
- No WirePlumber policy/config files (see
  [wireplumber-versioning.md](wireplumber-versioning.md)).
- No Safe Sink, no filter-chain limiter, no fixed-gain node.
- No Bluetooth nodes, no DLNA renderer nodes.
