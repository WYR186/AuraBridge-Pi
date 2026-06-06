# DLNA / UPnP (Phase 6 — gated, currently BLOCKED)

> **Status: BLOCKED.** The Safe Sink is not verified (see
> [safe-sink.md](safe-sink.md)), so DLNA must stay off. `install-dlna.sh` is now
> a **gated installer** (not just a stub): it refuses to do anything until
> `logs/safe-sink-verified.txt` contains `SAFE_SINK_VERIFIED=yes`.
> `systemd/gmrender.service` exists but has a start-time gate and **no
> `[Install]` section**, so it cannot be enabled or autostarted.

## Client expectations (Xiaomi / Samsung) — read this first

The renderer is a **generic DLNA/UPnP MediaRenderer**. How you reach it depends on
the phone, and the **guaranteed** path is a third-party DLNA control point, not the
phone's built-in cast button:

- **Reliable on both Xiaomi and Samsung:** a DLNA control-point app —
  **BubbleUPnP**, **Hi-Fi Cast**, or **VLC for Android**. Pick the renderer
  *Aura Studio 3 DLNA*, queue a track, play. This is the supported workflow.
- **Xiaomi (MIUI / HyperOS):** some bundled apps expose a DLNA/“投射” target, but
  whether a *generic* renderer is listed varies by version — treat native casting
  as best-effort.
- **Samsung (One UI):** “Smart View” is mainly Miracast / Samsung-only and the
  stock music app dropped DLNA, so the native menu generally will **not** push
  audio to a generic renderer. Use a control-point app.

We deliberately do **not** emulate Google Cast / Miracast to satisfy the native
buttons — that is a large, uncertain effort outside this project's scope.

For codec coverage, `install-dlna.sh` installs the broader GStreamer plugin set
(`-good`, `-bad`, `-ugly`, `libav`) so MP3 / AAC / M4A / FLAC / WAV / OGG pushed
from phones actually decode — otherwise the device is *discovered but silent*.

## DLNA is high-risk

DLNA / UPnP control points are the least trustworthy clients in this project:

- A control point may force volume to **100%** on connect or on play.
- **Unsafe volume commands** arrive over the network with no user gesture on the
  Pi, and renderer/control-point volume can desync.
- Multiple control points can fight over a single renderer.
- Output can bypass some client-side volume logic.
- A sudden spike **cannot be stopped in time by Bash polling.**

Because the KA11 is a headphone amplifier feeding a powered speaker, an
unexpected 100% command is a real speaker-safety risk.

## The rule

- DLNA is **blocked until real-time audio safety is verified.**
- DLNA stays **disabled by default** even after verification (manual start only).
- DLNA **cannot rely on `volume-guard-loop.sh`.** Polling is recovery only and
  is explicitly **not** an acceptable safety mechanism. See
  [volume-safety.md](volume-safety.md).

## Unlock requirements (ALL must be true)

- [ ] AuraBridge Safe Sink exists (or an equivalent protected route) —
      [safe-sink.md](safe-sink.md)
- [ ] KA11 physical sink is not the default sink for normal clients
- [ ] A PipeWire-level limiter / fixed-gain / hard cap is **verified**
- [ ] A 100% client-side volume command does **not** create dangerous analog output
- [ ] The test was performed with the Aura Studio 3 physical volume **low**
- [ ] A quick-disable command exists (it does — see below)
- [ ] The exact renderer and client behavior is documented (log section below)

These map directly to `logs/safe-sink-verified.txt` (`SAFE_SINK_VERIFIED=yes`,
`dangerous_at_100pct=no`), which `install-dlna.sh` and `gmrender.service` both
check.

## How the gate is enforced (defense in depth)

1. **`install-dlna.sh`** greps the marker; if it is missing or not `yes`, it
   prints *"DLNA is blocked until real-time audio safety is verified."* and exits
   non-zero — installing nothing.
2. **`gmrender.service`** has an `ExecStartPre` that re-checks the marker at
   start time, so even a manual `systemctl --user start` refuses to run if the
   Safe Sink is no longer verified.
3. The unit has **no `[Install]` section**, so it can never be `enable`d or
   autostarted at boot.
4. The renderer routes via `PULSE_SINK=aurabridge_safe_sink` through
   pipewire-pulse — **never** to ALSA `hw:`/`plughw:`.

## Manual enable procedure (only after verification)

```bash
# Pre-req: ./scripts/setup-safe-sink.sh --apply && ./scripts/test-safe-sink.sh  (=> VERIFIED)
./scripts/install-dlna.sh                      # gmediarender + GStreamer codecs + stable UUID + user unit (DISABLED)
systemctl --user start gmrender.service        # start manually (foreground service)
systemctl --user status gmrender.service       # confirm it is running
./scripts/check-dlna-discovery.sh              # confirm phones can actually find it
```

The renderer appears to control points as **Aura Studio 3 DLNA**. `install-dlna.sh`
generates a stable UUID once (`~/.config/aurabridge/dlna-uuid`); `gmrender.service`
loads it via `EnvironmentFile` and passes `--uuid` (plus `--port 49494`) so control
points keep recognising the **same** device across reboots.

## Discovery / 发现排查

DLNA/UPnP discovery uses **SSDP over multicast UDP 1900** (`239.255.255.250`) plus
an HTTP/SOAP control port (`--port 49494`). This is **not** mDNS/Avahi, so the
AirPlay discovery stack does nothing for it. When a phone can't see the speaker,
the cause is almost always the network, not the Pi:

- **Same subnet.** The phone must share the Pi's subnet (here `192.168.50.x`) — not
  a guest network, not a VLAN-split or isolated SSID.
- **AP / client isolation OFF.** Many routers block client↔client traffic; that
  stops the phone reaching the Pi. Disable it.
- **IGMP snooping / multicast filtering** on the AP must allow `239.255.255.250`.
- **Ethernet Pi + Wi-Fi phone** must bridge on the same L2 segment.
- **No host firewall** blocking UDP 1900 / TCP 49494 (default AuraBridge has none).

Run the read-only checker on the Pi: `./scripts/check-dlna-discovery.sh`. It reports
the Pi's subnet, whether the renderer is running and listening on UDP 1900 / TCP
49494, SSDP multicast group membership, and the culprits above.

## Quick disable procedure

```bash
systemctl --user stop gmrender.service         # stop now
# It is not enabled, so it will NOT come back on reboot. To remove entirely:
rm -f ~/.config/systemd/user/gmrender.service && systemctl --user daemon-reload
```

## Safe testing procedure

1. Turn the **Aura Studio 3 physical volume LOW**.
2. `./scripts/safe-volume.sh` (install-dlna.sh also does this).
3. Confirm the default sink is the **verified Safe Sink** (`./scripts/status.sh`).
4. `systemctl --user start gmrender.service`.
5. From a DLNA control point (e.g. BubbleUPnP, Hi-Fi Cast), select
   **Aura Studio 3 DLNA**, play a quiet track, and **deliberately push the
   control point to 100%** — confirm the Safe Sink cap keeps analog output safe.
6. Record what the client did in the log below.
7. `systemctl --user stop gmrender.service` when finished.

## Candidate tools

`gmediarender` (gmrender-resurrect) — used here, decoding via GStreamer. `Rygel`
is an alternative (adapt `gmrender.service` accordingly). If generic-renderer
compatibility ever proves insufficient, **`upmpdcli`** (OpenHome + UPnP AV on top
of MPD) is a heavier fallback with broader control-point support — out of scope
unless needed.

## Client behavior log

Record each control point you test (this is required documentation). Test on each
phone both the native cast menu (best-effort) and a control-point app (supported):

| Date | Phone / OS | Control point app | Discovered? | Sets volume on connect? | Respects Safe Sink cap? | Codecs OK (MP3/AAC/FLAC) | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- |
| _pending hardware test_ | Xiaomi / HyperOS | Native 投屏 | | | | | best-effort; may not list generic renderer |
| _pending hardware test_ | Xiaomi / HyperOS | BubbleUPnP / Hi-Fi Cast | | | | | supported path |
| _pending hardware test_ | Samsung / One UI | Smart View | | | | | expected: no generic DLNA audio target |
| _pending hardware test_ | Samsung / One UI | BubbleUPnP / VLC | | | | | supported path |
