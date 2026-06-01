# DLNA / UPnP (Phase 6 — gated, currently BLOCKED)

> **Status: BLOCKED.** The Safe Sink is not verified (see
> [safe-sink.md](safe-sink.md)), so DLNA must stay off. `install-dlna.sh` is now
> a **gated installer** (not just a stub): it refuses to do anything until
> `logs/safe-sink-verified.txt` contains `SAFE_SINK_VERIFIED=yes`.
> `systemd/gmrender.service` exists but has a start-time gate and **no
> `[Install]` section**, so it cannot be enabled or autostarted.

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
./scripts/install-dlna.sh                      # installs gmediarender + user unit (DISABLED)
systemctl --user start gmrender.service        # start manually (foreground service)
systemctl --user status gmrender.service       # confirm it is running
```

The renderer appears to control points as **Aura Studio 3 DLNA**.

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

`gmediarender` (gmrender-resurrect) — used here. `Rygel` is an alternative
(adapt `gmrender.service` accordingly).

## Client behavior log

Record each control point you test (this is required documentation):

| Date | Control point app | Sets volume on connect? | Respects Safe Sink cap? | Notes |
| --- | --- | --- | --- | --- |
| _pending hardware test_ | | | | DLNA still blocked; no tests yet |
