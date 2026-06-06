# Audio Routing (Phase 0–3)

## The rule that shapes everything

**No service routes directly to ALSA `hw:`/`plughw:` devices.** Every client
goes through PipeWire (natively or via `pipewire-pulse`). Direct ALSA output
lets one service grab the KA11 exclusively and produces `Device or resource
busy` the moment a second protocol tries to play. PipeWire is the single sound
server that multiplexes all sources onto the one USB DAC.

## Current (Phase 0–3) graph

```
Shairport Sync (native PipeWire)     librespot / DLNA (PulseAudio API)
              \                                  /
               \                                /
                v                              v
                       PipeWire media graph
                            |
                            v
                         WirePlumber
                            |
                            v
                default sink = aurabridge_safe_sink
                            |
                            v
                    FiiO KA11 USB DAC sink
                            |
                            v
                       3.5 mm AUX  ->  Aura Studio 3
```

The 2026-06-06 hardware recovery verified the Safe Sink path on the real Pi4:
`aurabridge_safe_sink` is the default sink and its downstream sink is the FiiO
KA11. The AirPlay loudness calibration uses fixed gain `1.30` with initial
volume `0.01`; Android/DLNA must stay treated as unverified after this gain
change. Clients still never touch ALSA directly.

> **Mixing vs. barge-in.** PipeWire **mixes** sources by default — two protocols
> playing at once are summed and you hear both. The optional **source arbiter**
> ([source-arbiter.md](source-arbiter.md)) turns that into *barge-in*: the newest
> wireless source wins the speaker and the previous one is muted by default. It
> acts only on the playback plane; discovery (AirPlay/mDNS, Spotify/Avahi,
> DLNA/SSDP) is independent, so **all protocols stay visible at the same time**
> regardless of who is playing.

## Safety graph (current verified state)

```
clients -> pipewire-pulse -> PipeWire -> AuraBridge Safe Sink
        -> limiter / fixed-gain stage -> KA11 physical sink -> AUX -> speaker
```

Normal clients target the Safe Sink and the **KA11 physical sink is not the
default**. This was the precondition for enabling DLNA on the real Pi4.

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

## Backend split

AirPlay uses Shairport Sync's **native PipeWire** backend. Spotify Connect and
DLNA still use the PulseAudio API through `pipewire-pulse`, which PipeWire
provides. This is intentional: AirPlay gets the native timing path, while other
clients keep the mature PulseAudio compatibility path. See
[airplay2.md](airplay2.md), [spotify.md](spotify.md), and [dlna.md](dlna.md).

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
- No ALSA `hw:`/`plughw:` client routing.
- No Bluetooth nodes, no DLNA renderer nodes.
