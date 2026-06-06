# AirPlay takeover & "device disappears while busy" (discovery vs takeover)

> **Symptom:** one iPhone is AirPlaying to *Aura Studio 3 AirPlay*; a second
> iPhone can no longer **see** the device (and Android **DLNA also disappears**),
> so it cannot take over. You want HomePod-style "the newest device wins".

This is **not** what the source arbiter does. The arbiter works on the *playback*
plane (who is audible) and assumes a second device can connect. Here the second
device can't even connect, so the arbiter never gets involved. There are **two
separate layers**, and HomePod-style takeover needs **both** working.

## Layer 1 — Discovery: the device must stay visible while busy

The decisive clue is that **AirPlay and DLNA disappear together**. AirPlay uses
mDNS (`224.0.0.251`); DLNA uses SSDP (`239.255.255.250`) — independent buses.
shairport-sync cannot hide a DLNA SSDP advert. If **both** vanish only while the
Pi is streaming, the common cause is the **network/Wi-Fi dropping multicast**.

The #1 cause on a Raspberry Pi is **Wi-Fi power save**. shairport-sync's own
TROUBLESHOOTING calls this out: the device disappears from the AirPlay list when
the Wi-Fi adapter is in a low-power/power-saving mode. Multicast on Wi-Fi is sent
at the lowest rate with no ACK, so it is the first thing dropped under load or
power save.

**Fix:**

```bash
./scripts/setup-wifi-powersave.sh        # persistently disables Wi-Fi power save
iw dev wlan0 get power_save              # verify -> "Power save: off"
```

It picks the right persistence automatically: a NetworkManager drop-in
(`wifi.powersave = 2`) when NM manages Wi-Fi, otherwise the
`aurabridge-wifi-powersave@wlan0.service` unit. Also strongly recommended:

- **Use wired Ethernet for the Pi** — removes Wi-Fi multicast fragility entirely.
- On the **router**: disable *AP/client isolation* and *IGMP snooping* (or add a
  multicast querier) so `224.0.0.251` / `239.255.255.250` reach all clients.

## Layer 2 — Takeover: a second sender must be allowed to interrupt

Even once it stays visible, shairport-sync **by default returns "busy"** to a
second sender for `sessioncontrol.session_timeout` seconds (default 120), so the
new phone can't take over. shairport-sync has an explicit switch for exactly the
HomePod behaviour:

```conf
sessioncontrol = {
  allow_session_interruption = "yes";   // let a new device interrupt/take over
};
```

(CLI equivalent: `shairport-sync --timeout=0`.) `install-airplay2.sh` now writes
this for fresh installs. To enable it on the **already-running** Pi:

```bash
./scripts/enable-airplay-takeover.sh     # edits /etc/shairport-sync.conf + restarts
```

## Diagnose which layer you're hitting

Run **on the Pi, while one iPhone is actively streaming** (and ideally a second
device is searching):

```bash
./scripts/diagnose-discovery.sh
```

It reports Wi-Fi power-save state, whether an AirPlay session is active, whether
the Pi still advertises AirPlay over mDNS and joins the SSDP/mDNS multicast
groups, and whether `allow_session_interruption` is enabled. Compare a run with
no stream vs. a run while streaming:

| Observation | Layer | Fix |
| --- | --- | --- |
| Visible when idle; AirPlay **and** DLNA vanish for others while streaming | Discovery | `setup-wifi-powersave.sh`; Ethernet; router AP-isolation/IGMP |
| Stays visible while streaming, but a 2nd iPhone gets "busy"/nothing | Takeover | `enable-airplay-takeover.sh` |

HomePod-style "newest device wins" = **both** fixed: power save off (stays
discoverable while busy) **and** `allow_session_interruption = "yes"` (the new
device interrupts the old one).

> Spotify and DLNA have their own takeover stories handled elsewhere (the source
> arbiter's playback-plane barge-in, see [source-arbiter.md](source-arbiter.md)).
> This document is specifically about AirPlay connection-level takeover and the
> shared Wi-Fi discovery problem.

## Sources

- shairport-sync TROUBLESHOOTING.md (device disappears ↔ Wi-Fi power save)
- shairport-sync man page (`--timeout` / "busy" / "barging in")
- shairport-sync issue #725 (disappears from AirPlay list; power management)
