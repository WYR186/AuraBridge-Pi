# Pass / Warn / Fail Matrix

Use this matrix to decide whether the first Raspberry Pi bring-up can continue.
When in doubt, stop, keep speaker volume low, and run `./scripts/collect-report.sh`.

| Check | PASS | WARN | FAIL | Next action |
| --- | --- | --- | --- | --- |
| KA11 `lsusb` detection | `lsusb` shows FiiO/KA11/USB Audio/DAC-like device | `lsusb` exists but device name is generic or unclear | No USB audio-like device, or `lsusb` missing after `setup-base.sh` | Fix adapter, USB port, power, or cable before continuing |
| KA11 `aplay -l` detection | `aplay -l` shows a USB audio playback card matching KA11/USB DAC hints | ALSA sees a generic USB card but name is ambiguous | No USB playback card, or `aplay` unavailable after `setup-base.sh` | Stop; confirm KA11 enumerates as Linux USB Audio |
| KA11 PipeWire sink detection | `wpctl status` or `pactl list sinks short` shows KA11/USB DAC sink | PipeWire is running but sink appears late or with ambiguous name | PipeWire cannot see KA11 sink | Restart user PipeWire stack, replug KA11, then rerun `check-ka11.sh` |
| `safe-volume.sh` | Sets default sink to 0.01 and unmutes | Runs but default sink is unclear | `wpctl` missing or cannot reach PipeWire | Stop playback tests; fix PipeWire user session |
| AirPlay visible | iPhone/Mac sees `Aura Studio 3 AirPlay` | Appears slowly or only on same Ethernet/Wi-Fi segment | Device never appears | Check `nqptp`, `shairport-sync`, Avahi/mDNS, same VLAN |
| AirPlay sound | Quiet audio plays through KA11 -> AUX -> Aura Studio 3 | Stream connects but output path is uncertain | No sound, device busy, or dangerous loudness | Run `status.sh`, `logs.sh`, collect report; do not raise volume blindly |
| Spotify visible | Spotify app sees `Aura Studio 3 Spotify` | Appears after app restart or network delay | Device never appears | Check `librespot.service`, same account/network, user linger |
| Spotify sound | Quiet audio plays through KA11 -> AUX -> Aura Studio 3 | Playback starts but output path is uncertain | No sound, device busy, or dangerous loudness | Run `status.sh`, `logs.sh`, collect report |
| Service reboot survival | After reboot, PipeWire user stack, AirPlay, and Spotify recover | One user service needs manual start | Core services do not recover | Check `loginctl enable-linger "$USER"` and enabled units |
| Logs clean enough | No repeated crashes, USB resets, ALSA busy errors, or PipeWire connection failures | Occasional warnings with stable playback | Repeated service restarts, USB resets, no PipeWire socket, or ALSA lock errors | Stop bring-up and attach report archive |

## Required Gate

`./scripts/check-ka11.sh` must report PASS before AirPlay or Spotify playback
tests. Do not continue from a FAIL by manually forcing ALSA card numbers.

## Safety Interpretation

- `safe-volume.sh` PASS means safe initialization only.
- `volume-guard-loop.sh` is recovery and diagnostics only.
- No PASS in this matrix makes DLNA safe.
- Safe Sink remains unverified until a later Phase 5 hardware test.
