# Runbook — Phase 0 through Phase 3

A fresh-install sequence for the AuraBridge Pi, covering only Phase 0–3. Run the
scripts as the **normal user** that owns the PipeWire session (they call `sudo`
where root is needed). Do **not** run the whole thing as root.

## Phase 0 — Preparation (off the Pi)

- [ ] Flash **Raspberry Pi OS Lite 64-bit** to the microSD card.
- [ ] Enable SSH (e.g. via Raspberry Pi Imager advanced options) and set the
      hostname/user.
- [ ] Prepare the 5V 3A supply, USB-A→Type-C adapter, FiiO KA11, AUX cable, and
      (preferably) an Ethernet cable.
- [ ] Boot the Pi, confirm you can `ssh` in.
- [ ] Clone this repository to the user's home, so paths match the systemd
      units: `git clone <repo> ~/AuraBridge-Pi && cd ~/AuraBridge-Pi`.

> The user systemd units in `systemd/` reference `%h/AuraBridge-Pi/scripts/...`.
> If you clone elsewhere, adjust the unit `ExecStart`/`WorkingDirectory` paths.

## Phase 1 — Base OS, PipeWire/WirePlumber, KA11, safe volume

Run in order:

```bash
./scripts/setup-base.sh            # base tools (idempotent); no reboot
./scripts/setup-pipewire.sh        # PipeWire, WirePlumber, pipewire-pulse
./scripts/wireplumber-version-check.sh
./scripts/check-ka11.sh
./scripts/safe-volume.sh
```

Manual checks after Phase 1:

- [ ] `setup-base.sh` finished and printed next steps.
- [ ] `setup-pipewire.sh` printed `pipewire --version`, `wireplumber --version`,
      `wpctl status`, `pactl info`, `pactl list sinks short`.
- [ ] `wireplumber-version-check.sh` told you 0.4 (Lua) vs 0.5+ (SPA-JSON). **Record it.**
- [ ] `check-ka11.sh` prints **PASS** (KA11 in `lsusb`, `aplay -l`, and as a
      PipeWire sink). If FAIL → fix hardware, see [hardware.md](hardware.md).
- [ ] `safe-volume.sh` set the default sink to 0.30 and unmuted it.
- [ ] **Plug in the AUX, turn the Aura Studio 3 volume LOW**, and play a short
      quiet test (e.g. `pw-play /usr/share/sounds/alsa/Front_Center.wav`).
      Confirm sound through the KA11. Do not exceed 45% during bring-up.

Do **not** modify any WirePlumber policy. See
[wireplumber-versioning.md](wireplumber-versioning.md).

## Phase 2 — AirPlay 2

```bash
./scripts/safe-volume.sh           # re-assert safe level before testing
./scripts/install-airplay2.sh      # NQPTP + Shairport Sync (PulseAudio backend)
```

Manual checks:

- [ ] The script ran `./configure --help | grep -i pulse` / `... airplay` and
      built with the PulseAudio backend + AirPlay 2 (not native PipeWire).
- [ ] `systemctl status nqptp` → active.
- [ ] `systemctl status shairport-sync` → active (it may be a system unit from
      `--with-systemd-startup`).
- [ ] On an iPhone/Mac on the same network, **"Aura Studio 3 AirPlay"** appears.
- [ ] Play audio at low volume; confirm sound; `pactl list sink-inputs` shows the
      stream on the KA11 sink; no `Device or resource busy`.

See [airplay2.md](airplay2.md). How to test AirPlay is the bullet list above.

## Phase 3 — Spotify Connect

```bash
./scripts/safe-volume.sh
./scripts/install-spotify.sh       # librespot + user service
```

Manual checks:

- [ ] `systemctl --user status librespot` → active. (If headless without login:
      `loginctl enable-linger "$USER"` — the script does this.)
- [ ] In the Spotify app (same account, same network), **"Aura Studio 3
      Spotify"** appears in the device picker.
- [ ] Play a track at low volume; confirm sound.
- [ ] Start AirPlay too; confirm AirPlay and Spotify coexist with no ALSA
      locking conflict.

See [spotify.md](spotify.md). How to test Spotify is the bullet list above.

## Anytime — status & logs

```bash
./scripts/status.sh    # one-screen health summary
./scripts/logs.sh      # recent journals for all relevant services + USB dmesg
```

## After Phase 0-3

Phase 4–6 scripts are now implemented as conservative, safety-gated steps, but
they must only be used **after this Phase 0–3 runbook passes on the actual Pi**.
Continue with [runbook-phase-4-6.md](runbook-phase-4-6.md).

And by project rule:

- Do **not** write or edit any WirePlumber policy.
- Do **not** enable `systemd/gmrender.service`; Phase 6 is manual-start only
  and gated by Safe Sink verification.
- Do **not** treat the volume guard as speaker protection or use it to justify
  enabling DLNA. See [volume-safety.md](volume-safety.md).

## Reboot / persistence

- PipeWire/WirePlumber/`pipewire-pulse` run as user services. For unattended
  boot, `loginctl enable-linger "$USER"`.
- NQPTP and Shairport Sync (system units) start at boot once enabled.
- After a reboot, re-run `./scripts/status.sh` to confirm everything came back.
