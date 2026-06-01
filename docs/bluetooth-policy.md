# Bluetooth A2DP Policy (Phase 4)

> **Status: implemented as scripts, NOT yet validated on real hardware.** The
> Phase 4 scripts (`setup-bluetooth.sh`, `bt-pairing-window.sh`,
> `bluetooth-routing-spike.sh`) exist and pass static checks, but they have
> **not** been run on the Raspberry Pi with a phone and the Aura Studio 3. Treat
> routing behaviour as **unverified** until the routing spike is run on the Pi.

## Where Bluetooth sits

Bluetooth A2DP is **MVP Plus, not core MVP.** AirPlay 2 and Spotify Connect are
the primary, reliable paths. Bluetooth is added for Android / Xiaomi / Samsung /
PC convenience and may be kept **disabled by default** if it proves disruptive
(see the fallback section).

## Components

BlueZ, PipeWire Bluetooth support (`libspa-0.2-bluetooth`), the WirePlumber
BlueZ monitor, and the normal PipeWire output path (the Safe Sink once it
exists, otherwise the KA11 sink). **No direct ALSA `hw:`/`plughw:` routing.**

Target Bluetooth alias: **Aura Studio 3 BT** (set via `bluetoothctl system-alias`).

## Hard rule: never permanently discoverable

The adapter is configured **non-discoverable and non-pairable by default**.
`setup-bluetooth.sh` forces `discoverable off` / `pairable off` after install.

Pairing is only possible inside a **timed window** opened by
`bt-pairing-window.sh`:

```bash
./scripts/bt-pairing-window.sh        # default 120s window
./scripts/bt-pairing-window.sh 60     # 60s window (CLI arg)
BT_PAIRING_SECONDS=60 ./scripts/bt-pairing-window.sh   # or via env
```

`bt-pairing-window.sh` installs a `trap` so the window is closed
(`discoverable off`, `pairable off`) **even if it is interrupted (Ctrl-C) or
errors**. The adapter must never be left permanently discoverable.

## Auto-connect / routing hijack MUST be tested

The default WirePlumber policy may auto-create a Bluetooth node and **switch
routing on connect**, interrupting AirPlay or Spotify. This must be measured
before Bluetooth is trusted. Run the spike on the Pi:

```bash
./scripts/bluetooth-routing-spike.sh
```

It records (to `logs/bluetooth-routing-spike-<timestamp>.txt`):

1. `pipewire --version`
2. `wireplumber --version`
3. `wpctl status`
4. `pactl list sinks short`
5. `pactl list sink-inputs`
6. `bluetoothctl show`
7. `bluetoothctl devices`

…before and after a Bluetooth connection, while AirPlay and then Spotify are
playing, and asks the operator whether each was hijacked.

The spike is **observe-only**. It writes **no** WirePlumber policy.

## Any WirePlumber policy must be version-specific

If the spike shows a hijack, mitigation requires a WirePlumber policy change —
and that change is **version-specific**:

- **WirePlumber 0.4.x** → Lua-style rule (disable switch-on-connect for the
  `bluez_output` node).
- **WirePlumber 0.5.x+** → SPA-JSON (`.conf`) fragment in
  `wireplumber.conf.d/`.

Check the version first with `./scripts/wireplumber-version-check.sh`. Do **not**
copy "latest docs" examples onto a mismatched install. See
[wireplumber-versioning.md](wireplumber-versioning.md).

**Gate:** the routing spike proposes a version-matched mitigation but does
**not** apply it. Writing Bluetooth WirePlumber policy requires an explicit,
separate approval and must follow the documentation contract (version, config
dir, syntax, files changed, reason, rollback).

## Fallback strategy

If hijacking cannot be handled cleanly, the MVP keeps Bluetooth **disabled by
default**:

```bash
sudo systemctl disable --now bluetooth.service   # disable Bluetooth entirely
```

Pair/play manually only when needed, and keep AirPlay + Spotify as the primary
paths. Bluetooth never gates the core MVP.

## Relationship to volume safety

Bluetooth is a **trusted, user-initiated** source (the user pairs their own
phone), so it is lower-risk than DLNA. It still routes through the normal
PipeWire path and benefits from the Safe Sink once that exists. Bluetooth does
**not** unblock DLNA, and the volume guard is still not speaker protection — see
[volume-safety.md](volume-safety.md).
