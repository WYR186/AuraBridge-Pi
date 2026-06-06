# Source Arbiter — barge-in across protocols (Phase 7)

> **Goal:** every wireless protocol is **discoverable at the same time**, and the
> **newest source to start playing wins the speaker** (barge-in / "互相顶下去").
> By default, the previous source is muted at the PipeWire layer, not mixed under
> the new one. Protocol-level Stop is opt-in after hardware validation.

## Two planes — read this first

The single most important idea in this project's multi-protocol behaviour is that
**discovery and playback are two completely separate planes.** Almost every
"why did protocol X disappear?" question comes from conflating them.

### Discovery plane (who can be *seen*)

| Protocol | Discovery bus | Multicast group | Daemon |
| --- | --- | --- | --- |
| AirPlay 2 | mDNS / Bonjour (Avahi) | `224.0.0.251` | shairport-sync |
| Spotify Connect | Avahi zeroconf | `224.0.0.251` | librespot |
| DLNA / UPnP | SSDP | `239.255.255.250` | gmediarender |
| Bluetooth A2DP | BT inquiry (pairing window) | — | bluetoothd |

These buses are **independent**. A DLNA renderer announcing itself over SSDP
**cannot** remove AirPlay's mDNS records — they are different protocols on
different multicast groups. As long as each daemon is running, **all of them are
visible simultaneously.** The arbiter never touches this plane.

### Playback plane (who *owns the speaker*)

Every source — AirPlay (native PipeWire backend), Spotify (PulseAudio →
pipewire-pulse), DLNA (GStreamer → pipewire-pulse) — ends up as a **sink-input**
in the one PipeWire graph. **PipeWire mixes by default**: two sources playing at
once are summed and you hear both. That is the *opposite* of what we want. The
arbiter lives entirely on this plane and turns mixing into barge-in.

## Why "AirPlay disappears when DLNA is playing"

Because discovery is independent (above), DLNA traffic cannot hide AirPlay's
mDNS advert. So if AirPlay seems to vanish while DLNA plays, it is one of:

1. **shairport-sync restarted.** The unit has `Restart=on-failure`; if it crashes
   under audio-graph contention, its Avahi record drops for the few seconds it is
   down and the iPhone shows it blinking out. Fix: the arbiter removes the
   contention (no more two-sources-fighting), and you should also check
   `journalctl -u shairport-sync` for restarts.
2. **Router multicast filtering.** Many home routers run *IGMP snooping* or
   *AP/client isolation*. Heavy SSDP from DLNA casting can disturb mDNS delivery
   (`224.0.0.251`) on the same Wi-Fi, so Bonjour/AirPlay goes flaky. Fix: disable
   AP isolation, and either disable IGMP snooping or add a multicast querier.
3. **It was never a discovery problem — it was mixing.** Before this arbiter,
   DLNA and AirPlay would both play (summed), so the experience was "AirPlay is
   broken" when in fact both were audible at once. Barge-in fixes the experience.

To pin down which one you are hitting on real hardware, run
`./scripts/check-dlna-discovery.sh` (network/SSDP side) and watch
`journalctl -u shairport-sync -f` (restart side) while you reproduce.

## Policy: barge-in (newest source wins)

When a managed source starts playing (its sink-input becomes `Corked: no`), it
becomes the **winner** and every other *currently playing* managed source is
preempted. When the winner stops, the arbiter promotes whatever is still playing.
There is no fixed priority ranking — last to press play wins.

## Mechanism: two layers

Preemption is done in two layers:

1. **PipeWire mute (default, guaranteed floor).** Mute the displaced sink-input
   so the speaker only ever plays the winner. This is conservative because it
   leaves AirPlay / DLNA / Spotify sessions and discovery alone.
2. **Protocol-level Stop (optional, best effort).** If explicitly enabled with
   `AURABRIDGE_ARBITER_PROTOCOL_STOP=1`, tell the displaced source itself to
   stop, so the phone's UI may also reflect the barge-in.

### Per-protocol capability matrix

| Source | Protocol-level Stop | How | Requirement |
| --- | --- | --- | --- |
| **DLNA** | optional | UPnP `AVTransport#Stop` (SOAP to `:49494`) | `AURABRIDGE_ARBITER_PROTOCOL_STOP=1`; `curl`; renderer description reachable on localhost or the Pi's wlan0 address |
| **AirPlay 2** | optional | D-Bus `org.gnome.ShairportSync.RemoteControl.Stop` | `AURABRIDGE_ARBITER_PROTOCOL_STOP=1`; shairport-sync built **`--with-dbus`**; D-Bus policy lets the user call it |
| **Spotify** | ❌ no | — (stock librespot has no remote-control API) | **mute only** — the Spotify app keeps "playing" silently |
| **Bluetooth** | ➖ n/a | not arbitrated here (manual MVP-Plus path) | — |

The mute floor means barge-in is *always* enforced on the speaker; the
protocol-Stop column is purely about whether the displaced **phone** also stops.
Keep it disabled until AirPlay and DLNA have both been proven stable on the real
Pi/router combination.

## Install / enable / disable

```bash
./scripts/install-arbiter.sh                       # install files only
./scripts/install-arbiter.sh --enable              # install + enable + start after validation
systemctl --user status aurabridge-arbiter.service # check
journalctl --user -u aurabridge-arbiter.service -f # watch decisions live
systemctl --user stop aurabridge-arbiter.service   # stop now (sources get unmuted)
systemctl --user disable --now aurabridge-arbiter.service
./scripts/source-arbiter.sh --reset                # unmute every managed source by hand
```

It never raises volume — it only mutes the loser by default — so it is
**independent of the DLNA / Safe-Sink gate**. Still, validate it before leaving
it enabled because it changes live playback ownership across protocols.

## How it works (implementation)

- `scripts/lib/arbiter-lib.sh` — classifies each sink-input
  (airplay/spotify/dlna by PulseAudio properties), provides mute helpers and the
  per-protocol Stop calls.
- `scripts/source-arbiter.sh --run` — waits for pipewire-pulse, reconciles once,
  then reacts to `pactl subscribe` sink-input events. On each new playing source
  it becomes the winner and `preempt_others` mutes the rest. Optional
  protocol-level Stop is disabled unless `AURABRIDGE_ARBITER_PROTOCOL_STOP=1`.
  On exit it unmutes everything (SIGTERM trap + `ExecStopPost --reset`).
- `systemd/aurabridge-arbiter.service` — user unit, `Restart=on-failure` so it
  re-subscribes if pipewire-pulse restarts.

It observes the graph through pipewire-pulse's PulseAudio API (`pactl`). Native
PipeWire streams (AirPlay) are reflected there as sink-inputs too, so one `pactl`
vantage point covers all sources without needing `jq`/`pw-dump`.

## Not hardware-validated yet

This was written on a development Mac (see the README status note) and has **not**
run on the Pi + KA11 + Aura Studio 3. Verify on real hardware:

- [ ] `pactl list sink-inputs` shows the AirPlay (native PipeWire) stream while it
      plays — confirms the arbiter can see it. If not, switch the event source to
      `pw-mon` (noted in the script).
- [ ] AirPlay → Spotify → DLNA → AirPlay each barge in cleanly; only the newest is
      audible; all three stay listed on their respective apps the whole time.
- [ ] With protocol Stop intentionally enabled, shairport-sync built `--with-dbus`;
      `busctl --system list | grep -i shairport` shows the name and
      `RemoteControl.Stop` actually stops the iPhone.
- [ ] DLNA control URL is discovered (`curl` to `:49494` works) and `Stop` halts
      the cast.
- [ ] Stopping the arbiter unmutes every source (nothing is left silent).
- [ ] Record results in the table below.

| Date | Winner→Loser | Loser stopped (protocol)? | Loser muted? | All still discoverable? | Notes |
| --- | --- | --- | --- | --- | --- |
| _pending hardware test_ | AirPlay → DLNA | | | | |
| _pending hardware test_ | DLNA → Spotify | | | | |
| _pending hardware test_ | Spotify → AirPlay | | | | |
