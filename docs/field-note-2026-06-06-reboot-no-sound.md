# Field Note — 2026-06-06 (evening): reboot no-sound, offline Pi, recurring fixes

Records three failures hit on the real Pi (raspberrypanda, 192.168.50.151, on
**wlan0**) and the **permanent** fixes so they don't recur. Read with
[field-note-2026-06-06-airplay-dlna-recovery.md](field-note-2026-06-06-airplay-dlna-recovery.md)
and [airplay-takeover-and-discovery.md](airplay-takeover-and-discovery.md).

## Issue 1 — "AirPlay connects but no sound" after a reboot (root cause found)

**Symptom:** after a reboot/power-cycle, AirPlay connects but the speaker is silent.

**Root cause:** the FiiO KA11 USB DAC enumerates a few seconds *after* the user
PipeWire graph starts. The Safe Sink filter-chain
(`~/.config/pipewire/pipewire.conf.d/99-aurabridge-safe-sink.conf`,
`target.object = alsa_output.usb-FIIO_FIIO_KA11-01.analog-stereo`) loads first and
binds its **output** to whatever sink exists — the Pi **onboard 3.5mm jack**
(`alsa_output.platform-bcm2835_audio.stereo-fallback`). It never moves to the KA11
when it appears. So the chain is `AirPlay → aurabridge_safe_sink → onboard jack`,
not the KA11 the speaker is plugged into → silence.

Confirm with `pactl list sink-inputs`: the `aurabridge_safe_sink.output` stream's
`Sink:` is the onboard sink id, and the KA11 sink shows `SUSPENDED`.

**Important:** the old `aurabridge-safe-sink-refresh.service` (which ran
`refresh-safe-sink.sh`, a full *reapply + PipeWire restart*) was already enabled
and DID run at boot — but the routing **still** landed on the onboard jack. The
heavy reapply does not reliably honor `target.object` across the restart (the same
late-enumeration race recurs). **A forced move is required.**

**Permanent fix:** [`scripts/bind-safe-sink-output.sh`](../scripts/bind-safe-sink-output.sh)
— waits for the selected sink (KA11) to appear, then **moves** the
`aurabridge_safe_sink.output` sink-input onto it (`pactl move-sink-input`),
idempotently, with no PipeWire restart. `aurabridge-safe-sink-refresh.service`
(user) now runs this at boot instead of the heavy reapply.

**Manual recovery (any time it's silent):**
```bash
./scripts/bind-safe-sink-output.sh        # or, heavier: ./scripts/refresh-safe-sink.sh
# one-off by hand:
#   pactl move-sink-input <aurabridge_safe_sink.output id> <KA11 sink id>
```

## Issue 2 — the whole Pi went offline (not an AirPlay problem)

**Symptom:** AirPlay AND DLNA AND SSH all unreachable; from another machine on the
same LAN, `ping 192.168.50.151` = 100% loss, `raspberrypanda.local` doesn't
resolve, ARP entry `(incomplete)`, and **other** AirPlay devices on the LAN are
still visible. → the Pi itself is off the network (powered off / crashed / Wi-Fi
dropped without reconnect), not a software/mDNS issue.

**How to tell quickly (from a Mac/PC on the same LAN):**
```bash
ping -c3 192.168.50.151 ; ping -c3 raspberrypanda.local ; arp -a | grep -i d8:3a:dd
```
**Recovery:** physical power-cycle. **Mitigation:** Issue 3 below + prefer wired
Ethernet for the Pi.

## Issue 3 — AirPlay/DLNA "disappear on their own" while idle/streaming

Both vanish together (independent mDNS vs SSDP buses) ⇒ Wi-Fi dropping multicast,
usually **Wi-Fi power save**. Permanent fix:
[`scripts/setup-wifi-powersave.sh`](../scripts/setup-wifi-powersave.sh) (disables
power save persistently — NetworkManager `wifi.powersave=2` drop-in here, since
this Pi is Bookworm/NM). Details:
[airplay-takeover-and-discovery.md](airplay-takeover-and-discovery.md).

## After-reboot verification checklist

Run after every reboot (or let the services do it; then spot-check):
```bash
systemctl is-active avahi-daemon nqptp shairport-sync
systemctl --user is-active pipewire pipewire-pulse wireplumber \
  aurabridge-safe-sink-refresh.service
iw dev wlan0 get power_save                      # want: off
# routing must be KA11, not onboard:
pactl list sink-inputs | grep -A6 aurabridge_safe_sink.output | grep Sink:
pactl list sinks short | grep -E 'FIIO|aurabridge'   # KA11 RUNNING when playing
```
Expected: services `active`; power save `off`; the `aurabridge_safe_sink.output`
stream's `Sink:` is the **KA11** sink id; AirPlay plays out of the speaker.

## Do not regress

- Keep `aurabridge-safe-sink-refresh.service` **enabled** (user service) and
  pointed at `bind-safe-sink-output.sh`. It is what makes audio survive a reboot.
- Do not assume "the refresh service ran" means routing is correct — verify the
  `aurabridge_safe_sink.output` `Sink:` is the KA11.
- Keep Wi-Fi power save **off**; prefer Ethernet for the Pi if possible.
