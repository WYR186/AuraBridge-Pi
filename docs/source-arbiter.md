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

## Safety rule: single source is never touched

> **The arbiter mutes nothing unless two or more sources are playing at the same
> time.** With 0 or 1 managed source playing it is a no-op and guarantees that
> lone source is audible. So AirPlay (or any protocol) used on its own is *never*
> muted, paused, or stopped by the arbiter — it behaves exactly as if the arbiter
> were not installed. Muting only ever happens to the *older* of two simultaneous
> streams. This rule is what makes the arbiter safe for everyday single-source use.

The decision logic is an **idempotent reconcile**: every event (and a periodic
watchdog tick) recomputes the desired state from a fresh `pactl` snapshot and
converges to it. There is no event-delta state machine to get out of sync, the
arbiter only ever unmutes streams *it* muted, and on startup it clears any stale
mute. A missed or duplicated event cannot strand a source silent.

## Why a muted phone doesn't pause — and how we make it pause

A plain mute is a **speaker-side** action: it silences that stream on the Pi but
sends nothing back to the phone, so the phone keeps playing (its progress bar
keeps moving) — it just isn't heard. To make the phone actually pause you have to
send a command **back to the sender over its own protocol**, and that ability
differs per protocol. Real speakers (Sonos/HomePod) implement that feedback for
every protocol; a DIY box has to do it per-protocol, and one source simply can't.

## Mechanism: two layers

Preemption is done in two layers:

1. **PipeWire mute (always, guaranteed floor).** Mute the displaced sink-input so
   the speaker instantly plays only the winner. Reversible, never disconnects.
2. **Protocol-level PAUSE (best effort, on top of muting).** Ask the displaced
   phone to *pause* over its own protocol so its UI reflects the hand-off and the
   user can resume. We send **Pause, not Stop** — Pause keeps the session and is
   resumable; Stop disconnects (that is what broke AirPlay before).

### Per-protocol capability matrix

| Source | Pause the phone? | How | Default | Requirement |
| --- | --- | --- | --- | --- |
| **DLNA** | ✅ yes | UPnP `AVTransport#Pause` (SOAP to `:49494`) | **ON** (`AURABRIDGE_ARBITER_DLNA_PAUSE=1`) | `curl`; renderer description reachable on localhost / the Pi's LAN IP |
| **AirPlay 2** | ✅ yes (gentle) | D-Bus `org.gnome.ShairportSync.RemoteControl.Pause` | **OFF** (`AURABRIDGE_ARBITER_AIRPLAY_PAUSE=1`) | shairport-sync rebuilt with `AURABRIDGE_AIRPLAY_DBUS=1 ./scripts/install-airplay2.sh`; validate first — this is the old breakage path |
| **Spotify** | ❌ **no** | — (stock librespot has no remote-control API) | mute only | swap to a librespot fork with a control API to change this |
| **Bluetooth** | ➖ n/a | not arbitrated here (manual MVP-Plus path) | — | — |

> **Auto-resume difference.** A source we *paused* (DLNA, or AirPlay when enabled)
> stays paused after the winner stops — you resume it on the phone, like a real
> speaker. A source we could only *mute* (Spotify) never actually stopped, so it
> becomes audible again automatically once the winner goes away.

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
  per-protocol Pause calls (`arb_protocol_preempt`).
- `scripts/source-arbiter.sh --run` — waits for pipewire-pulse, clears any stale
  mute, then runs the idempotent `reconcile()` on every `pactl subscribe`
  sink-input event **and** on a periodic watchdog tick (`read -t`, default 2s).
  `reconcile()` snapshots all managed sink-inputs, and: with ≤1 playing it mutes
  nothing; with ≥2 it keeps the newest (highest first-seen ordinal) audible and
  mutes the rest, recording each in its own `_muted` set so it only ever unmutes
  what it muted. On top of muting it asks each displaced phone to *pause* over its
  protocol (`AURABRIDGE_ARBITER_DLNA_PAUSE=1` on by default,
  `AURABRIDGE_ARBITER_AIRPLAY_PAUSE` off). On exit it unmutes everything (SIGTERM
  trap + `ExecStopPost --reset`).
- `systemd/aurabridge-arbiter.service` — user unit, `Restart=on-failure` so it
  re-subscribes if pipewire-pulse restarts.

It observes the graph through pipewire-pulse's PulseAudio API (`pactl`). Native
PipeWire streams (AirPlay) are reflected there as sink-inputs too, so one `pactl`
vantage point covers all sources without needing `jq`/`pw-dump`.

## Not hardware-validated yet

This was written on a development Mac (see the README status note) and has **not**
run on the Pi + KA11 + Aura Studio 3. Verify on real hardware:

- [ ] **Regression guard: AirPlay alone is untouched.** With the arbiter running
      and only AirPlay playing, it is never muted and plays normally (start/stop
      AirPlay several times). The logs should show no mute actions.
- [ ] `pactl list sink-inputs` shows the AirPlay (native PipeWire) stream while it
      plays — confirms the arbiter can see it. If not, switch the event source to
      `pw-mon` (noted in the script).
- [ ] AirPlay → Spotify → DLNA → AirPlay each barge in cleanly; only the newest is
      audible; all three stay listed on their respective apps the whole time.
- [ ] Default AirPlay build has **no** `--with-dbus` (`shairport-sync -V` / build
      flags) unless you rebuilt with `AURABRIDGE_AIRPLAY_DBUS=1`.
- [ ] DLNA pause works: displacing DLNA pauses it; a control point (BubbleUPnP /
      Hi-Fi Cast) shows "paused" and can resume (`curl` to `:49494` reachable).
- [ ] Only with AirPlay pause enabled (`AURABRIDGE_ARBITER_AIRPLAY_PAUSE=1` + the
      D-Bus rebuild), `busctl --system list | grep -i shairport` shows the name
      and `RemoteControl.Pause` pauses the iPhone *without disconnecting* it.
- [ ] Stopping the arbiter unmutes every source (nothing is left silent).
- [ ] Record results in the table below.

| Date | Winner→Loser | Loser phone paused? | Loser muted? | All still discoverable? | Notes |
| --- | --- | --- | --- | --- | --- |
| _pending hardware test_ | AirPlay → DLNA | | | | |
| _pending hardware test_ | DLNA → Spotify | | | | |
| _pending hardware test_ | Spotify → AirPlay | | | | |
