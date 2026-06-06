# Hardware & Wiring

## Bill of materials (required)

| Item | Notes |
| --- | --- |
| Raspberry Pi 4 Model B | The bridge host. Headless, Raspberry Pi OS Lite 64-bit. |
| microSD card | 32 GB or larger recommended. |
| 5V 3A USB-C power supply | Official or high quality. Under-powering causes USB resets. |
| USB-A male → Type-C female adapter | Must be a **data** adapter, not charge-only. |
| FiiO KA11 Type-C | USB DAC / headphone amplifier. The audio output device. |
| 3.5 mm AUX cable | KA11 analog out → Aura Studio 3 AUX-IN. |
| Harman Kardon Aura Studio 3 | The powered speaker. Never opened or modified. |

Optional: Ethernet cable (preferred over Wi-Fi for stability), case,
heatsink/fan, powered USB hub (helps if the KA11 causes USB resets), I2C OLED
display and a physical button (Phase 7 only).

## Wiring

```
Raspberry Pi 4  (USB-A port)
        |
        v
USB-A male  ->  Type-C female adapter
        |
        v
FiiO KA11 Type-C   (USB DAC / headphone amp)
        |
        v
3.5 mm AUX cable
        |
        v
Aura Studio 3  AUX-IN
```

## Rules

- The KA11 is the designated **final** output / DAC for the finished build.
- The Raspberry Pi onboard 3.5 mm jack is supported as an **interim / fallback**
  output for bring-up before the dongle arrives — it is PWM-based and lower
  quality, so it is not the intended final output. Select it with
  `./scripts/select-output.sh onboard`; see [onboard-audio.md](onboard-audio.md).
- **Do not** use a passive Type-C → 3.5 mm analog passthrough adapter. The KA11
  is an active USB Audio Class device and must enumerate over USB.
- The KA11 must appear as a **USB audio device** (`lsusb`, `aplay -l`). If it
  does not, fix the hardware path before any software setup — see
  [ka11-validation.md](ka11-validation.md).

## KA11 positioning and the loudness caveat

The FiiO KA11 is a **DAC / headphone amplifier**, *not* a fixed-level line-out.
Its analog output can drive headphones and is strong enough that, fed into a
powered speaker's AUX input at a high digital volume, it can be very loud.

Consequences for this project:

- Set a **safe initial PipeWire volume (1.00)** before any playback.
- Keep the **Aura Studio 3 physical volume low** during first tests.
- If the KA11 exposes an ALSA hardware mixer control, note it and keep it at a
  conservative level (see [ka11-validation.md](ka11-validation.md)).

See [volume-safety.md](volume-safety.md) for the full safety model.

## If the KA11 misbehaves on USB

Symptoms: dropouts, clicks, `USB reset` in `dmesg`, intermittent disappearance.

- Try a different USB-A port; prefer USB 2.0 ports if USB 3.0 is unstable.
- Use a better 5V 3A supply and cable.
- Use a powered USB hub so the KA11 is not drawing from a marginal Pi rail.
