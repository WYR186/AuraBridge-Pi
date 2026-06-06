# FiiO KA11 Validation

The KA11 must be validated as a USB audio device **before** any playback test.
Use `./scripts/check-ka11.sh`, which performs the checks below and prints a
PASS / WARN / FAIL summary.

## What is checked

| Check | Command | What we want to see |
| --- | --- | --- |
| USB enumeration | `lsusb` | A line hinting at FiiO / KA11 / USB Audio / DAC |
| ALSA playback cards | `aplay -l` | A `USB Audio` card (any index — **not** assumed to be 1) |
| ALSA PCM names | `aplay -L` | A USB/`sysdefault`/`plughw` entry for the DAC |
| Hardware mixer | `amixer -c <card_id> scontrols` | Whether the KA11 exposes a volume control |
| PipeWire version | `pipewire --version` | Recorded for the version log |
| WirePlumber version | `wireplumber --version` | Recorded for the version log |
| PipeWire graph | `wpctl status` | KA11 present as a sink |
| Sinks | `pactl list sinks short` | A USB/FiiO-like sink name |

## Dynamic detection — never assume card 1

The KA11 is **not** assumed to be ALSA card 1 or device 0. Detection is by
**name**, searching for case-insensitive hints across `lsusb`, ALSA cards, and
PipeWire/PulseAudio sinks:

```
FiiO | KA11 | USB Audio | DAC | Headphone | Amp
```

`check-ka11.sh` reports the detected ALSA card index/id dynamically. If your
unit reports an unexpected product string, add the hint to the detection list
in `scripts/check-ka11.sh` rather than hardcoding a card number anywhere.

## Hardware mixer behavior — document it

If `amixer -c <card_id> scontrols` lists a control (e.g. `PCM` or `Headphone`),
record the control name and its range, and keep it at a conservative level.
Some KA11 firmware exposes no usable ALSA mixer (volume is then handled purely
in the PipeWire graph) — that is fine; just record which case you are in.

Suggested record (keep with your build notes):

```
KA11 ALSA card index : <e.g. 2>
KA11 ALSA card id     : <e.g. "Device" / "KA11">
Hardware mixer        : <none | PCM 0-127 | ...>
PipeWire version      : <x.y.z>
WirePlumber version   : <x.y.z  ->  config model: 0.4 Lua / 0.5+ SPA-JSON>
PipeWire sink name    : <alsa_output.usb-FiiO_KA11-...>
```

## PASS / WARN / FAIL meaning

- **PASS** — KA11 is visible in USB *and* ALSA *and* (if PipeWire is running) as
  a sink. Safe to proceed to `safe-volume.sh` and a low-volume test.
- **WARN** — detected at one layer but not all (e.g. ALSA sees it but PipeWire
  is not running yet). Resolve before playback.
- **FAIL** — not detected as a USB audio device. **Stop.** Fix the hardware path
  (adapter, port, power) per [hardware.md](hardware.md) before continuing.

## After a PASS

1. `./scripts/safe-volume.sh` — set default sink to 1.00 and unmute.
2. Keep the Aura Studio 3 physical volume low.
3. Play a short, quiet test (e.g. `pw-play /usr/share/sounds/alsa/Front_Center.wav`
   if available). Confirm sound comes out of the speaker via the KA11.
