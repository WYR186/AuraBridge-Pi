# Spotify Connect (Phase 3)

## What it uses

- **librespot** — an open-source Spotify Connect receiver.
- **`pipewire-pulse`** — librespot uses its **PulseAudio-compatible output**,
  which connects to `pipewire-pulse` and into the PipeWire graph.

```
librespot (pulseaudio backend)
        -> pipewire-pulse
        -> PipeWire
        -> default sink = FiiO KA11   (Safe Sink later, not yet)
        -> AUX -> Aura Studio 3
```

**No direct ALSA `hw:`/`plughw:` routing.** librespot must not target the ALSA
card directly — that reintroduces device-locking conflicts with AirPlay.

## Device name

```
Aura Studio 3 Spotify
```

## Service model

This build installs librespot as a **user** systemd service
(`systemd/librespot.service`, installed to `~/.config/systemd/user/`). Running
it as a user service means it shares the same PipeWire / `pipewire-pulse`
session as your login, so the PulseAudio output "just works" without
cross-user socket plumbing.

For a headless Pi that should run librespot without an interactive login:

```bash
loginctl enable-linger "$USER"
systemctl --user enable --now librespot.service
```

`install-spotify.sh` sets this up for you and runs `safe-volume.sh` before the
service is started.

## Run order

```bash
./scripts/setup-base.sh
./scripts/setup-pipewire.sh
./scripts/check-ka11.sh        # PASS
./scripts/safe-volume.sh
./scripts/install-spotify.sh   # builds/installs librespot + user service
```

## Test steps

1. Open Spotify on a phone/desktop **logged into the same account**, on the same
   network.
2. Open the device picker (Connect) and choose **"Aura Studio 3 Spotify"**.
3. Keep the Aura Studio 3 physical volume **low**.
4. Play a track. Confirm sound from the speaker.
5. `pactl list sink-inputs` — the librespot stream should be routed to the KA11
   sink. Start AirPlay too and confirm both coexist with no `Device or resource
   busy`.

## Acceptance (from the overview)

- [ ] Spotify app sees "Aura Studio 3 Spotify"
- [ ] Playback works
- [ ] No ALSA device-locking conflict with AirPlay
- [ ] Output level is safe

## Notes

- librespot needs mDNS/zeroconf discovery reachable from the controlling app on
  the same L2 network.
- Authentication is zeroconf/Spotify-Connect based by default (pick the device
  from the app). No credentials are stored by the install script.
