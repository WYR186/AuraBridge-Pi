# AuraBridge Safe Sink (Phase 5)

> **Status: implemented as a reversible spike; NOT verified on hardware.**
> `setup-safe-sink.sh` can install a fixed-gain Safe Sink, and `test-safe-sink.sh`
> can verify it — but verification has **not** been performed on the real
> Raspberry Pi + KA11 + Aura Studio 3 (this work was authored on a dev machine
> with no PipeWire). Therefore **the Safe Sink is NOT verified and DLNA remains
> blocked.**

## Why `volume-guard-loop.sh` is not safety

`volume-guard-loop.sh` polls the default-sink volume (every ~5 s) and clamps it
*after the fact*. If a client jumps to 100%, the speaker can be at full level for
the seconds until the next poll. Polling is recovery/diagnostics — it is **not**
a limiter, a hard cap, or speaker protection, and it must never justify enabling
DLNA. See [volume-safety.md](volume-safety.md).

## Why real-time, graph-level safety is required

The only way to *guarantee* a maximum analog level is to cap the signal **inside
the audio graph**, after every client-controllable volume, before the DAC. That
is what the Safe Sink does: normal clients target the Safe Sink, the Safe Sink
applies a fixed gain in the PipeWire DSP graph, and only then is audio sent to
the KA11.

## Target design

```
Normal clients
   -> AuraBridge Safe Sink (PipeWire filter-chain virtual sink)
   -> fixed-gain stage (linear mult, applied in the DSP graph)
   -> FiiO KA11 physical sink (present but NOT the default for normal clients)
   -> AUX -> Aura Studio 3
```

## What was attempted

`setup-safe-sink.sh` builds a **PipeWire filter-chain** virtual sink named
`AuraBridge Safe Sink` (`node.name = aurabridge_safe_sink`) using two builtin
`linear` gain nodes (L/R) with a fixed `mult` (default `1.30`). Its
output targets the **dynamically detected** KA11 sink by name (never `hw:`/a card
number). On `--apply` it sets the Safe Sink as the default sink so normal clients
use it instead of the KA11.

Design choices made for safety:

- It is a **PipeWire config** (`~/.config/pipewire/pipewire.conf.d/`), **not a
  WirePlumber policy**, so it does not depend on the WirePlumber 0.4-vs-0.5
  config model and writes no WirePlumber policy.
- Default mode is **investigate-only**: it probes the system and writes a
  **disabled** candidate (`*.conf.disabled`, which PipeWire ignores). Nothing in
  the live audio graph changes until you explicitly run `--apply`.
- `--apply` **backs up** any existing config, restarts PipeWire, and
  **auto-rolls-back** if the Safe Sink does not appear (so a bad config cannot
  leave you without audio).

## What worked

- The scripts pass `bash -n` and `shellcheck`.
- The config generation, KA11-by-name detection, backup, apply, auto-rollback,
  and rollback logic are implemented and reviewed.

## What failed / is unverified

- **No hardware test.** Nothing here has run on a real PipeWire session.
- The builtin `linear` node provides a **fixed attenuation (hard cap on maximum
  level)**, *not* a look-ahead dynamics limiter. That is acceptable per the
  project spec ("fixed-gain stage"), but it must be confirmed audibly safe.
- PipeWire allows node volumes **above 100%** (over-amplification). The fixed
  gain still caps the result, but the exact safe ceiling must be judged on the
  real speaker — which is precisely what `test-safe-sink.sh` asks a human.
- The AirPlay loudness calibration uses `SAFE_SINK_GAIN=1.30` because `0.10`
  was too quiet in normal use. That is an AirPlay usability calibration, **not**
  DLNA safety verification.
- Whether the chosen builtin `linear` graph loads cleanly on the Pi's specific
  PipeWire version is unconfirmed (the auto-rollback exists for exactly this).

## Is the Safe Sink verified?

**No.** Verification requires running `test-safe-sink.sh` on the Pi and a human
confirming, with the Aura Studio 3 physical volume low, that audio flows through
the controlled path **and** a 100% client volume does **not** produce dangerous
output. Only then is `logs/safe-sink-verified.txt` written with
`SAFE_SINK_VERIFIED=yes`. Changing the Safe Sink gain invalidates any previous
marker.

## Does DLNA remain blocked?

**Yes.** `install-dlna.sh` refuses to proceed unless
`logs/safe-sink-verified.txt` says `SAFE_SINK_VERIFIED=yes`. See [dlna.md](dlna.md).

## How to install, verify, and roll back (on the Pi)

```bash
# 1. Investigate (read-only; writes a DISABLED candidate config):
./scripts/setup-safe-sink.sh

# 2. Install reversibly (backs up, restarts PipeWire, auto-rolls-back on failure):
./scripts/setup-safe-sink.sh --apply

# 3. Verify with a human in the loop (physical volume LOW):
./scripts/test-safe-sink.sh

# 4. Roll back at any time:
./scripts/setup-safe-sink.sh --rollback
```

## Rollback steps (manual, if needed)

```bash
rm -f ~/.config/pipewire/pipewire.conf.d/99-aurabridge-safe-sink.conf
systemctl --user restart pipewire pipewire-pulse wireplumber
# Confirm the KA11 is selectable again:
./scripts/status.sh
./scripts/check-ka11.sh
```

## Relationship to other phases

- **DLNA stays blocked** until this is verified (see [dlna.md](dlna.md)).
- Fully *hiding* the KA11 from clients (not just making the Safe Sink the
  default) would need a **version-specific WirePlumber policy** — out of scope
  here and gated by [wireplumber-versioning.md](wireplumber-versioning.md).
