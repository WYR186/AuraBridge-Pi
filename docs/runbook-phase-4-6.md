# Runbook — Phase 4 through Phase 6

Continues [runbook-phase-0-3.md](runbook-phase-0-3.md). **Do not start Phase 4
until Phase 0–3 is validated on the actual Pi** (KA11 detected, AirPlay 2 and
Spotify Connect working). Run everything as the **normal user** that owns the
PipeWire session.

Phase order is deliberate and safety-gated:

```
Phase 4 Bluetooth  →  Phase 5 Safe Sink (real-time safety)  →  Phase 6 DLNA
                                         │
                          DLNA is BLOCKED until Phase 5 is VERIFIED
```

> **Authoring note:** the Phase 4–6 scripts were written and statically checked
> on a dev machine with no PipeWire. None of the steps below have been run on the
> real Pi + KA11 + Aura Studio 3. Treat every "Acceptance" box as **unverified**
> until you tick it on the hardware.

---

## Phase 4 — Bluetooth A2DP (MVP Plus)

Bluetooth is convenience, not core. Keep AirPlay/Spotify as the primary paths.

```bash
./scripts/safe-volume.sh
./scripts/setup-bluetooth.sh          # BlueZ + PipeWire BT; alias "Aura Studio 3 BT"
```

`setup-bluetooth.sh` leaves the adapter **non-discoverable and non-pairable**.
To pair, open a short window and pair your phone *during* it:

```bash
./scripts/bt-pairing-window.sh        # 120s window; or pass seconds: ... 60
```

Then test whether a Bluetooth connection hijacks AirPlay/Spotify routing:

```bash
./scripts/bluetooth-routing-spike.sh  # observe-only; logs to logs/bluetooth-routing-spike-*.txt
```

Manual checks:

- [ ] `setup-bluetooth.sh` printed the controller status with the alias set and
      **Discoverable: no / Pairable: no**.
- [ ] During `bt-pairing-window.sh`, the phone could pair; after the window the
      adapter is **no longer discoverable** (the script's trap guarantees this
      even on Ctrl-C).
- [ ] The routing spike recorded before/after `wpctl status` and
      `pactl list sink-inputs`, and you answered the hijack questions.
- [ ] If a hijack was observed: **no WirePlumber policy was written.** Decide
      between (a) a version-matched policy (separate, explicit approval — see
      [wireplumber-versioning.md](wireplumber-versioning.md)) or (b) keeping
      Bluetooth disabled by default.

Fallback (if disruptive): `sudo systemctl disable --now bluetooth.service`.

---

## Phase 5 — Real-time audio safety / AuraBridge Safe Sink

This is the gate for DLNA. Goal: a graph-level hard cap so even 100% client
volume cannot blast the speaker.

```bash
./scripts/setup-safe-sink.sh          # investigate (read-only) + write a DISABLED candidate
```

Review the probe output (versions, KA11 sink, filter-chain/LADSPA/LV2). Then
install it **reversibly** (backs up, restarts PipeWire, auto-rolls-back on
failure) and verify it with a human in the loop:

```bash
./scripts/setup-safe-sink.sh --apply  # creates "AuraBridge Safe Sink", sets it default
./scripts/test-safe-sink.sh           # KEEP THE AURA STUDIO 3 PHYSICAL VOLUME LOW
```

Manual checks:

- [ ] `--apply` reported the Safe Sink present and set it as the default sink
      (AirPlay/Spotify still play — through the Safe Sink now).
- [ ] `test-safe-sink.sh` confirmed audio reaches the KA11 via the controlled
      path, you ran the **100% test with the physical knob low**, and answered
      the danger question.
- [ ] Verdict is **VERIFIED** → `logs/safe-sink-verified.txt` contains
      `SAFE_SINK_VERIFIED=yes`. If **NOT VERIFIED**, stop — DLNA stays blocked.

Rollback any time:

```bash
./scripts/setup-safe-sink.sh --rollback
```

If a real-time safe path **cannot** be verified, that is an acceptable outcome:
keep the Safe Sink off, keep DLNA disabled, and rely on AirPlay/Spotify only.

---

## Phase 6 — Optional DLNA (only if Phase 5 is VERIFIED)

```bash
./scripts/install-dlna.sh             # REFUSES unless SAFE_SINK_VERIFIED=yes
./scripts/install-dlna.sh --start     # optional: install/update + start now
```

If the Safe Sink is not verified, the script prints *"DLNA is blocked until
real-time audio safety is verified."* and exits — installing nothing.

If verified, it installs `gmediarender` and a **disabled** user unit. Start it
only manually, and stop it when done:

```bash
systemctl --user start  gmrender.service   # appears as "Aura Studio 3 DLNA"
systemctl --user status gmrender.service
./scripts/start-discovery-stack.sh --check-only
systemctl --user stop   gmrender.service   # quick disable
```

Manual checks:

- [ ] Physical volume LOW; default sink is the **verified** Safe Sink.
- [ ] On a DLNA control point, **Aura Studio 3 DLNA** appears and plays.
- [ ] Push the control point to **100%** — confirm the Safe Sink cap keeps the
      analog output safe.
- [ ] Record the client's behaviour in the table in [dlna.md](dlna.md).
- [ ] AirPlay and DLNA are both locally discoverable:
      `./scripts/start-discovery-stack.sh --check-only`.
- [ ] `gmrender.service` is **not enabled** unless you explicitly chose DLNA
      boot autostart with `./scripts/install-dlna.sh --enable`.

---

## Anytime — status & logs

```bash
./scripts/status.sh    # now shows BT alias/discoverable, Safe Sink + verification, DLNA gate
./scripts/logs.sh      # adds gmrender, bluetoothctl show/devices, Safe Sink config + marker
```

## Rollback summary

| Undo | Command |
| --- | --- |
| Disable Bluetooth | `sudo systemctl disable --now bluetooth.service` |
| Remove Safe Sink | `./scripts/setup-safe-sink.sh --rollback` |
| Stop DLNA now | `systemctl --user stop gmrender.service` |
| Remove DLNA unit | `rm -f ~/.config/systemd/user/gmrender.service && systemctl --user daemon-reload` |
| Re-lock DLNA | delete/edit `logs/safe-sink-verified.txt` (gate re-checks it) |
