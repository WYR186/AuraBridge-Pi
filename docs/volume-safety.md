# Volume Safety

This is the most important document in the project. The 2.2 redesign exists
mostly because of what is written here.

## Why the KA11 demands caution

The FiiO KA11 is a **DAC / headphone amplifier**, **not** a fixed-level
line-out. Its analog output is strong. Fed into the Aura Studio 3's powered AUX
input at a high digital volume, it can produce a very loud, potentially
unpleasant or damaging sound. Treat output level as a safety property, not a
convenience setting.

## The four hard facts

1. **`safe-volume.sh` is initialization only.** It sets the PipeWire default
   sink to `1.00` and unmutes it. It runs once. It is *not* a limiter and does
   *not* watch for spikes.
2. **`volume-guard-loop.sh` is recovery / audit / diagnostics only.** It polls
   the default sink volume and clamps it back toward `1.00` if it exceeds
   `1.30`. Because it polls (default every 5 s), a malicious or careless client
   that sets 100% can still be loud for the seconds between checks.
3. **Bash polling is not real-time speaker protection.** Do not describe it as
   protection. Do not rely on it. Do not use it to justify enabling risky
   clients. This is a non-negotiable project rule.
4. **DLNA remains blocked** until a real-time safety layer (Safe Sink + limiter
   / fixed-gain / hard cap inside the PipeWire graph) is implemented **and
   verified**. The Safe Sink is now implemented as a reversible spike
   (`setup-safe-sink.sh`), but it is **not verified** until `test-safe-sink.sh`
   writes `SAFE_SINK_VERIFIED=yes` to `logs/safe-sink-verified.txt` with a human
   confirming the 100%-volume test. `install-dlna.sh` checks that marker.

## Three layers of volume protection (target design)

- **Layer 1 — hardware mixer check.** If the KA11 exposes an ALSA mixer
  control, set it to a safe value. (`amixer -c <card_id> scontrols`,
  `alsamixer -c <card_id>`.) See [ka11-validation.md](ka11-validation.md).
- **Layer 2 — real-time PipeWire safety (the real protection).** An AuraBridge
  Safe Sink feeding a filter-chain fixed-gain stage (a hard cap), with the KA11
  physical sink no longer the default for normal clients. **Implemented as a
  reversible spike in Phase 5 (`setup-safe-sink.sh`), but NOT yet verified on
  hardware.** Until it is verified (`test-safe-sink.sh`), risky clients and DLNA
  stay disabled. See [safe-sink.md](safe-sink.md).
- **Layer 3 — Bash recovery.** `safe-volume.sh`, `volume-guard-loop.sh`, the
  systemd timer, and logging. Recovery and diagnostics only.

For AirPlay 2 and Spotify Connect, Layers 1 and 3 are acceptable **only**
because those clients are trusted, user-driven sources and we keep physical
volumes low — not because polling makes them safe. Untrusted/automatic clients
(DLNA) require a **verified** Layer 2 first.

## Initial test settings

| Setting | Value |
| --- | --- |
| Initial PipeWire default sink volume | 100% (`safe-volume.sh` uses 1.00) |
| Maximum normal testing volume | 130% after the AirPlay loudness calibration |
| Aura Studio 3 physical volume | low |
| Phone / source device volume | low |
| DLNA | disabled |
| Untrusted clients | disabled |

## The required safe-volume commands

```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 1.00
wpctl set-mute   @DEFAULT_AUDIO_SINK@ 0
```

These run inside `safe-volume.sh`. They are initialization, **not** a real-time
limiter, and do **not** protect against instant spikes from untrusted clients.

## The volume guard, stated precisely

`volume-guard-loop.sh` and `aurabridge-volume-guard.{service,timer}`:

- **Are:** a recovery tool, an audit tool, a diagnostics tool, post-failure
  correction.
- **Are NOT:** a real-time safety mechanism, a limiter, a hard cap, a speaker
  protection layer, or a reason to enable DLNA.

If anyone (including future-you) is tempted to write "the system is protected by
the volume guard" — it is not. Implement Layer 2 first.

## First-playback checklist

1. `./scripts/check-ka11.sh` → PASS.
2. Turn the **Aura Studio 3 physical knob low**.
3. `./scripts/safe-volume.sh`.
4. Play something short and quiet; raise volume slowly.
