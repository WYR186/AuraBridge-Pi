# AirPlay 2 (Phase 2)

## What it uses

- **NQPTP** — the PTP timing daemon required for AirPlay 2.
- **Shairport Sync** — the AirPlay receiver, built with **AirPlay 2 support**
  and the **native PipeWire backend** (`--with-pipewire` or `--with-pw`,
  depending on the Shairport Sync version).

## Backend decision: native PipeWire (Directive 3)

Shairport Sync uses the **native PipeWire backend** and connects to PipeWire
**directly**, *not* through `pipewire-pulse`. This removes a layer of IPC
(Shairport → pipewire-pulse → PipeWire collapses to Shairport → PipeWire) and
improves precision-time-protocol (PTP) synchronisation for AirPlay 2.

> Earlier phases used the PulseAudio backend through `pipewire-pulse` for
> portability. Directive 3 supersedes that: the native backend is now the
> default. `pipewire-pulse` is no longer on the AirPlay path (other tools such as
> `pactl` / `safe-volume.sh` may still use it; the install neither requires nor
> removes it).

```
Shairport Sync (native PipeWire backend)
        -> PipeWire (no pipewire-pulse)
        -> WirePlumber routes to the AuraBridge output
           (Safe Sink if present, else the selected sink: onboard AUX / USB DAC)
        -> AUX -> Aura Studio 3
```

No direct ALSA `hw:`/`plughw:` routing.

## Build flags — `./configure --help` is the source of truth

`install-airplay2.sh` first inspects the available options (the native backend
flag and dependency names can differ between Shairport Sync versions):

```bash
./configure --help | grep -iE 'pipewire|with-pw'
./configure --help | grep -i airplay
```

The configure line is:

```bash
./configure --sysconfdir=/etc \
  --with-pipewire \
  --with-soxr \
  --with-avahi \
  --with-ssl=openssl \
  --with-systemd-startup \
  --with-airplay-2
```

`--with-pipewire` / `--with-pw` requires the **`libpipewire-0.3-dev`** headers
(the install adds them, replacing `libpulse-dev`). The script uses whichever
native PipeWire flag `./configure --help` reports and will **not** silently fall
back to the PulseAudio backend.

The runtime config name is **not** the configure flag. In
`/etc/shairport-sync.conf`, the backend must be:

```config
general = {
  name = "Aura Studio 3 AirPlay";
  output_backend = "pipewire";
};
```

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
./scripts/safe-volume.sh       # 0.01, unmuted, BEFORE testing
./scripts/install-airplay2.sh  # NQPTP + Shairport Sync
```

`install-airplay2.sh` runs `safe-volume.sh` again before it finishes, so the
first AirPlay stream starts at a safe level.

## Test steps

1. On the same network, open Control Center (iPhone/iPad) or the AirPlay menu
   (Mac) and pick **"Aura Studio 3 AirPlay"**.
2. Keep the Aura Studio 3 physical volume **low**.
3. Play audio. Confirm sound from the speaker.
4. `wpctl status` / `pw-cli ls Node` — the Shairport Sync stream should appear
   as a native PipeWire client routed to the AuraBridge output (Safe Sink, or
   the selected onboard/USB sink).
5. `./scripts/status.sh` — NQPTP and Shairport Sync should report active.

## Confirmed Pi4 recovery note

The first confirmed real-hardware AirPlay success was recorded on 2026-06-06:
AirPlay connected and the Aura Studio 3 produced audio through the FiiO KA11
USB DAC path. Keep these choices unless there is a deliberate migration:

- Shairport Sync uses `output_backend = "pipewire"`.
- Shairport Sync publishes only on `wlan0`, port `7000`.
- Avahi is constrained to IPv4 on `wlan0`.
- The default sink is `aurabridge_safe_sink`.
- The Safe Sink downstream is the KA11 sink.
- The AirPlay loudness calibration uses Safe Sink gain `1.30` and initial
  volume `0.01`; the old `0.10` gain was too quiet for normal use.
- The optional source arbiter is not required for basic AirPlay playback. It must
  never disconnect AirPlay: AirPlay pause stays opt-in (off by default) and uses
  D-Bus `RemoteControl.Pause`, never `Stop`.

See [field-note-2026-06-06-airplay-dlna-recovery.md](field-note-2026-06-06-airplay-dlna-recovery.md)
before changing any of the above.

## Acceptance (from the overview + Directive 3)

- [ ] NQPTP active
- [ ] Shairport Sync active
- [ ] iPhone / Mac sees "Aura Studio 3 AirPlay"
- [ ] **`pw-cli ls Node` / `wpctl status` shows Shairport Sync as a NATIVE
      PipeWire client (not via `pipewire-pulse`)**
- [ ] Audio plays through the AuraBridge output into the Aura Studio 3
- [ ] PipeWire shows the stream
- [ ] No ALSA device-locking conflict
- [ ] Output level is safe

## Notes on the systemd service

Shairport Sync built `--with-systemd-startup` installs and manages its own
`shairport-sync` unit. NQPTP installs its own `nqptp` unit. The install script
enables and starts both.

The **native PipeWire backend still needs access to a PipeWire session.** The
system `shairport-sync` service must be able to reach the user PipeWire socket
(correct `XDG_RUNTIME_DIR` / running in the user session, with lingering enabled
for the audio user). If the stream connects but produces no sound, this is the
usual cause — see [runbook-phase-0-3.md](runbook-phase-0-3.md) for the
session/linger notes. The verification at the end of `install-airplay2.sh`
(`pw-cli ls Node | grep -i shairport`) confirms the native connection.
