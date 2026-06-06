# Troubleshooting (Phase 0–6)

Run `./scripts/status.sh` and `./scripts/logs.sh` first — they answer most of
the questions below. All commands assume you are SSH'd into the Pi as the normal
user that runs the PipeWire session (not root, unless noted).

## KA11 / USB DAC not detected

Symptoms: `check-ka11.sh` reports FAIL; KA11 missing from `lsusb` / `aplay -l` /
`wpctl status`.

- Re-seat the **USB-A male → Type-C female adapter**; try a different USB-A port
  (prefer the USB 2.0 ports if the USB 3.0 ports are flaky).
- Confirm the adapter is a real data adapter, not charge-only.
- `dmesg | grep -i usb` — look for `USB reset`, under-voltage, or enumeration
  errors. Under-voltage usually means the 5V 3A supply or cable is inadequate;
  try a powered USB hub.
- Do **not** assume the KA11 is card 1. The scripts detect it dynamically by
  name (`FiiO`, `KA11`, `USB Audio`, `DAC`). If your unit reports an unusual
  name, note it and extend the detection hints in `scripts/check-ka11.sh`.

## No sound, but KA11 is detected

- `./scripts/safe-volume.sh` — ensures the default sink is unmuted and at 0.30.
- `wpctl status` — confirm the KA11 is the **default** sink (marked with `*`).
  If not: `wpctl set-default <ID>` using the KA11 node ID from `wpctl status`.
- Confirm the AUX cable is fully seated in the Aura Studio 3 **AUX-IN** and the
  speaker is switched to its AUX/line input.
- Keep the speaker's physical volume low while testing — see
  [docs/volume-safety.md](docs/volume-safety.md).

## PipeWire / WirePlumber not running

- PipeWire normally runs as **user** services:
  `systemctl --user status pipewire pipewire-pulse wireplumber`.
- If they are inactive: `systemctl --user enable --now pipewire pipewire-pulse
  wireplumber`. For a headless box that should run them without an active login,
  enable lingering: `loginctl enable-linger "$USER"`.
- `pactl info` failing with "Connection refused" usually means `pipewire-pulse`
  is not running for your user.

## `pactl` / `wpctl` not found

- `wpctl` ships with WirePlumber; `pactl` ships with `pulseaudio-utils`.
  `setup-pipewire.sh` installs both. The scripts degrade gracefully and print a
  WARN if a tool is missing, rather than crashing.

## AirPlay target "Aura Studio 3 AirPlay" does not appear

- AirPlay 2 needs **NQPTP** running: `systemctl status nqptp`.
- Check Shairport Sync: `systemctl status shairport-sync` (or the user service,
  depending on how `--with-systemd-startup` installed it) and
  `./scripts/logs.sh`.
- Avahi/mDNS must work: `systemctl status avahi-daemon`. AirPlay discovery is
  mDNS-based — the Pi and the phone must be on the same L2 network/VLAN.
- The confirmed Pi4 recovery constrains AirPlay/mDNS to `wlan0` IPv4 to avoid
  stale multi-interface Bonjour records. Check `avahi-browse -rt _raop._tcp`
  and confirm it shows `wlan0 IPv4`, `address = [192.168.50.151]`, and
  `port = [7000]`.
- Confirm Shairport Sync is using the **native PipeWire backend**:
  `/etc/shairport-sync.conf` should contain `output_backend = "pipewire";`.
  See [docs/airplay2.md](docs/airplay2.md) and
  [docs/field-note-2026-06-06-airplay-dlna-recovery.md](docs/field-note-2026-06-06-airplay-dlna-recovery.md).

## AirPlay appears, connects, but no sound

- Run `./scripts/status.sh`. The known-good state is `Default sink:
  aurabridge_safe_sink`, `Safe Sink downstream:
  alsa_output.usb-FIIO_FIIO_KA11-01.analog-stereo`, and `Safe Sink verified:
  YES`.
- Reset any stale arbiter mute state: `./scripts/source-arbiter.sh --reset`.
  The arbiter is optional and should be disabled unless being tested.
- Check the AirPlay stream and routing: `wpctl status`, `pactl list sinks short`,
  and `pactl list sink-inputs`.
- Check recent logs: `journalctl -u shairport-sync -n 80 --no-pager` and
  `journalctl --user -u pipewire -u wireplumber -n 80 --no-pager`.
- If the KA11 was unplugged, moved, or power-cycled, check USB audio errors:
  `dmesg | grep -iE 'usb|fiio|ka11|snd_usb|No such device' | tail -n 80`.
  `No such device` / `Unable to submit urb` means physical USB/DAC disconnect,
  not an AirPlay protocol failure.

## AirPlay works but is quiet

The 2026-06-06 verified Safe Sink gain is `0.10`, so quiet output is expected.
Raise volume cautiously from the source and Aura Studio 3 first. Do not casually
increase the Safe Sink gain; it is part of the verified safety state.

## "Device or resource busy" / ALSA locking

- This is exactly why we route through PipeWire / `pipewire-pulse` and **never**
  to `hw:`/`plughw:` directly. If you see this, something is bypassing PipeWire.
  Check that neither Shairport Sync nor librespot is configured for an ALSA
  backend pointing at the card directly. See [docs/audio-routing.md](docs/audio-routing.md).

## Spotify device "Aura Studio 3 Spotify" not visible

- `systemctl --user status librespot` (this build installs librespot as a user
  service so it shares the PipeWire/`pipewire-pulse` session).
- librespot needs network discovery (mDNS/zeroconf) reachable from the phone on
  the same network. See [docs/spotify.md](docs/spotify.md).
- `./scripts/logs.sh` includes recent librespot journal lines.

## Volume jumped loud

- Turn the **Aura Studio 3 physical knob down** first, then the source device.
- `./scripts/safe-volume.sh` resets the PipeWire default sink to 0.30.
- Remember: the volume guard only *recovers* after the fact. It is **not**
  real-time protection. This is the central 2.2 safety rule — see
  [docs/volume-safety.md](docs/volume-safety.md).

## Bluetooth pairing does not work

- Run `./scripts/setup-bluetooth.sh` on the Pi and confirm
  `bluetooth.service` is active.
- Pair only during a timed window:
  `./scripts/bt-pairing-window.sh` (default 120 seconds).
- After the window, `bluetoothctl show` should report `Discoverable: no` and
  `Pairable: no`. Permanent discoverability is intentionally forbidden.
- If Bluetooth interrupts AirPlay or Spotify, run
  `./scripts/bluetooth-routing-spike.sh` and keep Bluetooth disabled by default
  until a version-specific WirePlumber mitigation is explicitly approved.

## Safe Sink did not appear

- Run `./scripts/setup-safe-sink.sh` first. Its default mode is investigative
  and writes only a disabled candidate config.
- Run `./scripts/check-ka11.sh`; the KA11 must appear as a PipeWire/Pulse sink.
- If `./scripts/setup-safe-sink.sh --apply` fails, it should auto-roll back.
  Check `journalctl --user -u pipewire -u wireplumber --no-pager`.
- Safe Sink installed does **not** mean verified. Verification requires
  `./scripts/test-safe-sink.sh` on the real Pi with the Aura Studio 3 physical
  volume low.

## DLNA installer refuses to run

That is the safe default. `./scripts/install-dlna.sh` refuses unless
`logs/safe-sink-verified.txt` contains `SAFE_SINK_VERIFIED=yes`, written by
`./scripts/test-safe-sink.sh` after the real-time path and 100% volume behavior
are confirmed safe. The volume guard does **not** satisfy this gate.

## DLNA service is active but the phone does not see it

- Run `./scripts/check-dlna-discovery.sh`.
- gmrender is intentionally bound to `wlan0`; `127.0.0.1:49494` may fail.
  Probe the Wi-Fi address instead:
  `curl -fsS http://192.168.50.151:49494/description.xml`.
- Confirm UDP 1900 and TCP 49494:
  `ss -ltnup | grep -E ':(1900|49494)'`.
- If the Pi checks pass but the phone still cannot see it, suspect router/AP
  multicast handling: same subnet, no guest Wi-Fi isolation, AP/client isolation
  off, and IGMP/multicast filtering allowing SSDP `239.255.255.250`.

## A gated future-risk script exited non-zero

That may be correct and intended. In Phase 4–6, scripts fail closed when a
safety gate is missing:

- `install-dlna.sh` exits until the Safe Sink is verified.
- `test-safe-sink.sh` exits non-zero unless the operator confirms safe output.
- `setup-safe-sink.sh --apply` exits and rolls back if the Safe Sink does not
  appear after PipeWire restart.

## Collecting a full diagnostic bundle

```bash
./scripts/status.sh   > /tmp/aurabridge-status.txt 2>&1
./scripts/logs.sh     > /tmp/aurabridge-logs.txt   2>&1
```

Attach both files when asking for help.
