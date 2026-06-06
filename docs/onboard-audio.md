# Onboard AUX output (and switching to the USB dongle later)

AuraBridge 2.2 was designed around an external USB DAC "小尾巴" (the FiiO KA11).
Until that hardware arrives you can run the **exact same stack** out of the
Raspberry Pi's built-in 3.5 mm AUX jack, and switch to the dongle later with one
command. Nothing about the onboard path blocks or removes the USB path.

## How output selection works

A single shared library — [`scripts/lib/output-target.sh`](../scripts/lib/output-target.sh)
— is the only place that knows how to recognise each device. Every script
(`status.sh`, `setup-safe-sink.sh`, `check-output.sh`, `select-output.sh`) asks
it which output to use, so they can never disagree.

The selection is resolved in this order (first match wins):

1. the `AURABRIDGE_OUTPUT` environment variable,
2. the config file `~/.config/aurabridge/output.conf`,
3. the built-in default, **`auto`**.

Values:

| Value | Meaning |
| --- | --- |
| `onboard` | Pi built-in 3.5 mm AUX jack (`bcm2835 Headphones`). |
| `usb` | External USB DAC dongle (小尾巴, e.g. FiiO KA11). |
| `auto` | Prefer the USB dongle **when one is actually plugged in**, else onboard. |

`auto` is what makes the same SD card work before and after the dongle shows up:
plug the KA11 in, and `auto` routes to it; unplug it, and it falls back to the
onboard jack. The sink is always found by its **dynamically detected PipeWire
sink name** — never a hardcoded ALSA card number, consistent with the rest of
the project ([audio-routing.md](audio-routing.md)).

## First-time onboard setup (no dongle yet)

```bash
./scripts/setup-base.sh
./scripts/setup-pipewire.sh
./scripts/setup-onboard-audio.sh     # enables the jack, may require a reboot
# (reboot here only if it reports the boot config changed)
./scripts/select-output.sh onboard   # make it the active output
./scripts/check-output.sh            # validate the selected output
./scripts/status.sh
```

`setup-onboard-audio.sh` is idempotent and reversible. It:

1. ensures `dtparam=audio=on` in `/boot/firmware/config.txt` (backing the file
   up first; a **reboot is required** the first time it adds the line, because
   the bcm2835 audio device only enumerates after that),
2. records `onboard` as the selection,
3. best-effort unmutes the onboard ALSA mixer controls,
4. sets the onboard PipeWire sink as the default and applies the safe volume.

## When the USB dongle arrives

Plug it in (via the data-capable USB-A→Type-C adapter — see
[hardware.md](hardware.md)), then:

```bash
./scripts/check-ka11.sh              # full USB DAC validation (USB+ALSA+PipeWire)
./scripts/select-output.sh usb       # or 'auto' to let it auto-prefer the dongle
./scripts/status.sh
```

If a Safe Sink was already applied, it follows the new selection automatically —
re-run `./scripts/setup-safe-sink.sh --apply` after switching so the fixed-gain
stage points at the dongle's sink rather than the onboard one.

## Quality and safety caveats for onboard

- The Pi's onboard 3.5 mm output is **PWM-based**: noticeably noisier and weaker
  than the KA11. It is great for bring-up and testing, but the USB DAC remains
  the intended final output. This is exactly why the project defaults toward the
  dongle.
- The onboard jack is closer to line level than the KA11's headphone-amp output,
  so it is *less* likely to be dangerously loud — but the safety model is
  unchanged: `safe-volume.sh` still sets `1.00` first, and you should still keep
  the Aura Studio 3 physical volume low during the first test. See
  [volume-safety.md](volume-safety.md).
- The Safe Sink / DLNA gate is **independent of which output you pick**. DLNA
  stays blocked until the Safe Sink is verified, on either output.

## Troubleshooting

- **No onboard sink in `wpctl status`:** confirm `dtparam=audio=on` and that you
  rebooted; `aplay -l` should list a `bcm2835 Headphones` card. Re-run
  `setup-onboard-audio.sh`.
- **Audio routed to HDMI instead of the jack:** the onboard sink is matched by
  the `bcm2835` name; pick it explicitly with `./scripts/select-output.sh
  onboard`, which sets it as the PipeWire default.
- **Switched to the dongle but still hear the jack:** run
  `./scripts/select-output.sh usb` (or `auto`) and, if using the Safe Sink,
  re-apply it. Check `./scripts/status.sh` → *Output selection*.
