# Field Note — 2026-06-06 AirPlay Recovery

This note records the first confirmed working AirPlay path on the real Pi4 +
FiiO KA11 + Harman Kardon Aura Studio 3 setup, plus the traps that caused
discovery and "connected but silent" failures.

## Scope

- **Verified working:** AirPlay from Apple devices to Aura Studio 3 through the
  FiiO KA11 USB DAC path.
- **Not yet usable:** Android wireless casting / DLNA from phones. The Pi-side
  gmrender service can run and expose diagnostics, but Android discovery and
  playback are not customer-ready in this version.

## Confirmed good result

On 2026-06-06, AirPlay was visible, connected successfully, and played audio
from the Aura Studio 3 through the USB DAC path.

Known-good runtime state:

```text
Host: raspberrypanda
Pi IP: 192.168.50.151
AirPlay name: Aura Studio 3 AirPlay
DLNA name: Aura Studio 3 DLNA
Default sink: aurabridge_safe_sink
Safe Sink downstream: alsa_output.usb-FIIO_FIIO_KA11-01.analog-stereo
Safe Sink gain: 0.10
Safe Sink verified marker: SAFE_SINK_VERIFIED=yes, gain=0.10
```

Expected services:

```bash
systemctl is-active avahi-daemon
systemctl is-active nqptp
systemctl is-active shairport-sync
systemctl --user is-active pipewire pipewire-pulse wireplumber
systemctl --user is-active gmrender.service
```

All of these should be `active` for the current AirPlay success path and DLNA
service diagnostics. This does **not** mean Android/DLNA phone playback is ready.
`bluetooth.service` may still be failed; that is unrelated to AirPlay.

## Known-good AirPlay config

`/etc/shairport-sync.conf` should use the native PipeWire backend and publish
only on the Wi-Fi interface:

```conf
general = {
  name = "Aura Studio 3 AirPlay";
  output_backend = "pipewire";
  mdns_backend = "avahi";
  interface = "wlan0";
  port = 7000;
};
diagnostics = {
  log_verbosity = 1;
};
```

`/etc/avahi/avahi-daemon.conf` should avoid stale multi-interface records:

```ini
use-ipv4=yes
use-ipv6=no
allow-interfaces=wlan0
```

Why this matters: the Pi may have multiple addresses or transient IPv6 records.
AirPlay clients are sensitive to Bonjour records that point to an unreachable
interface. The stable working path is IPv4 on `wlan0`.

## Known-good discovery checks

On the Pi:

```bash
avahi-browse -rt _airplay._tcp
avahi-browse -rt _raop._tcp
```

Expected AirPlay address:

```text
wlan0 IPv4 D83ADD150BA3@Aura Studio 3 AirPlay
address = [192.168.50.151]
port = [7000]
```

From a Mac on the same Wi-Fi:

```bash
dns-sd -B _raop._tcp local
```

Expected result includes:

```text
D83ADD150BA3@Aura Studio 3 AirPlay
```

For Pi-side DLNA diagnostics, do not use `127.0.0.1` as the only HTTP probe when
gmrender is bound to `wlan0`. Use the Pi's Wi-Fi address:

```bash
curl -fsS http://192.168.50.151:49494/description.xml | grep -E '<friendlyName>|<modelName>'
```

Expected result:

```xml
<friendlyName>Aura Studio 3 DLNA</friendlyName>
<modelName>gmediarender</modelName>
```

## Output routing checks

The working audio path is:

```text
Shairport Sync (native PipeWire)
  -> PipeWire / WirePlumber
  -> aurabridge_safe_sink
  -> FiiO KA11 USB DAC
  -> 3.5 mm AUX
  -> Aura Studio 3
```

Run:

```bash
./scripts/status.sh
pactl info
pactl list sinks short
pactl list sink-inputs
```

Expected status lines:

```text
Default sink: aurabridge_safe_sink
Safe Sink node: present (aurabridge_safe_sink)
Safe Sink downstream: alsa_output.usb-FIIO_FIIO_KA11-01.analog-stereo
Safe Sink gain: 0.10
Safe Sink verified: YES
```

The sound may be quiet. That is expected with `gain=0.10`; it was intentionally
kept conservative during validation.

## Arbiter trap

Before this recovery, the arbiter design was too aggressive:

- It could call protocol-level Stop on displaced AirPlay/DLNA sources.
- That can make sender UIs look disconnected, even though discovery itself is
  separate from playback.
- It also made debugging much harder because "source was muted" and "source was
  told to stop" looked similar from the phone.

Correct current policy:

```text
Arbiter is optional.
install-arbiter.sh installs only by default.
Protocol-level Stop is disabled by default.
Default behaviour is mute-only playback arbitration.
```

Safe checks:

```bash
systemctl --user status aurabridge-arbiter.service
systemctl --user is-active aurabridge-arbiter.service
./scripts/source-arbiter.sh --reset
```

On the successful AirPlay recovery, the Pi reported:

```text
Arbiter (user): not installed
```

So a running arbiter was not the direct cause of the final no-sound/discovery
state, but the old arbiter logic was still fixed to avoid future regressions.

## Power-cycle recovery checklist

After unplugging/replugging the Pi, use this order:

```bash
cd ~/AuraBridge-Pi
./scripts/status.sh

systemctl is-active avahi-daemon nqptp shairport-sync
systemctl --user is-active pipewire pipewire-pulse wireplumber gmrender.service

./scripts/source-arbiter.sh --reset
./scripts/refresh-safe-sink.sh || ./scripts/setup-safe-sink.sh --apply
./scripts/status.sh
```

If AirPlay is visible but connection fails:

```bash
sudo systemctl restart avahi-daemon
sudo systemctl restart nqptp shairport-sync
avahi-browse -rt _raop._tcp
```

If AirPlay connects but has no sound:

```bash
wpctl status
pactl list sinks short
pactl list sink-inputs
journalctl -u shairport-sync -n 80 --no-pager
journalctl --user -u pipewire -u wireplumber -n 80 --no-pager
```

If KA11 disappears after power loss or cable movement:

```bash
lsusb
dmesg | grep -iE 'usb|fiio|ka11|snd_usb|No such device' | tail -n 80
./scripts/check-output.sh
```

The previous recovery logs showed USB audio errors around a disconnect:

```text
Unable to submit urb #11: -19
spa.alsa: snd_pcm_status error: No such device
```

Those point to a physical USB/DAC disconnect or power/cable issue, not an
AirPlay protocol problem.

## Version status for this commit

This version should be described as:

```text
AirPlay works end-to-end on Aura Studio 3.
Android / DLNA phone casting is not yet usable.
```

## Do not regress these choices

- Do not route Shairport Sync directly to ALSA `hw:` / `plughw:`.
- Do not change AirPlay back to PulseAudio just to debug one symptom; the
  working path is native PipeWire.
- Do not publish AirPlay on every interface while debugging discovery; keep
  Avahi/Shairport constrained to `wlan0` IPv4.
- Do not enable arbiter protocol Stop unless AirPlay and DLNA have both been
  validated again.
- Do not treat `curl http://127.0.0.1:49494/...` failure as DLNA failure when
  gmrender is intentionally bound to `wlan0`.
- Do not raise Safe Sink gain casually. `0.10` is quiet but verified-safe.
