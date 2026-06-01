# AirPlay 2 (Phase 2)

## What it uses

- **NQPTP** — the PTP timing daemon required for AirPlay 2.
- **Shairport Sync** — the AirPlay receiver, built with **AirPlay 2 support**
  and the **PulseAudio backend**.
- **`pipewire-pulse`** — the PulseAudio-compatible API that Shairport Sync's
  PulseAudio backend connects to, bridging it into the PipeWire graph.

## Backend decision: PulseAudio, not native PipeWire

For the MVP, Shairport Sync uses the **PulseAudio backend through
`pipewire-pulse`**, *not* the native PipeWire backend. The PulseAudio path is
mature and behaves consistently across distributions and PipeWire versions,
which is what a multi-protocol bridge needs. The native PipeWire backend may be
revisited later, but it is **not** the MVP default.

```
Shairport Sync (PulseAudio backend)
        -> pipewire-pulse
        -> PipeWire
        -> default sink = FiiO KA11   (Safe Sink later, not yet)
        -> AUX -> Aura Studio 3
```

No direct ALSA `hw:`/`plughw:` routing.

## Build flags — `./configure --help` is the source of truth

The exact PulseAudio flag name can differ between Shairport Sync versions, so
`install-airplay2.sh` first runs:

```bash
./configure --help | grep -i pulse
./configure --help | grep -i airplay
```

The preferred configure line is:

```bash
./configure --sysconfdir=/etc \
  --with-pa \
  --with-soxr \
  --with-avahi \
  --with-ssl=openssl \
  --with-systemd-startup \
  --with-airplay-2
```

If `--with-pa` is not offered, the script uses whichever PulseAudio backend flag
`./configure --help` reports. It will **not** silently fall back to the native
PipeWire backend.

## Device name

```
Aura Studio 3 AirPlay
```

Set via the Shairport Sync config (`general.name`) by the install script.

## Run order

```bash
./scripts/setup-base.sh        # build tools, avahi, etc. (Phase 1)
./scripts/setup-pipewire.sh    # PipeWire + pipewire-pulse (Phase 1)
./scripts/check-ka11.sh        # KA11 must PASS
./scripts/safe-volume.sh       # 0.30, unmuted, BEFORE testing
./scripts/install-airplay2.sh  # NQPTP + Shairport Sync
```

`install-airplay2.sh` runs `safe-volume.sh` again before it finishes, so the
first AirPlay stream starts at a safe level.

## Test steps

1. On the same network, open Control Center (iPhone/iPad) or the AirPlay menu
   (Mac) and pick **"Aura Studio 3 AirPlay"**.
2. Keep the Aura Studio 3 physical volume **low**.
3. Play audio. Confirm sound from the speaker.
4. `wpctl status` / `pactl list sink-inputs` — the Shairport Sync stream should
   appear routed to the KA11 sink.
5. `./scripts/status.sh` — NQPTP and Shairport Sync should report active.

## Acceptance (from the overview)

- [ ] NQPTP active
- [ ] Shairport Sync active
- [ ] `pipewire-pulse` active
- [ ] iPhone / Mac sees "Aura Studio 3 AirPlay"
- [ ] Audio plays through KA11 into the Aura Studio 3
- [ ] PipeWire shows the stream
- [ ] No ALSA device-locking conflict
- [ ] Output level is safe

## Notes on the systemd service

Shairport Sync built `--with-systemd-startup` installs and manages its own
`shairport-sync` unit. NQPTP installs its own `nqptp` unit. The install script
enables and starts both. Because the PulseAudio backend needs access to the
user PipeWire/`pipewire-pulse` session, see
[runbook-phase-0-3.md](runbook-phase-0-3.md) for the session/linger notes if the
stream connects but produces no sound.
