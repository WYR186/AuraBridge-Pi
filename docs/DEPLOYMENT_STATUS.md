# AuraBridge Pi 2.2 - Deployment Status

**Last Updated**: 2026-06-06  
**Deployment Version**: onboard-audio variant with dual-output support  
**Raspberry Pi**: raspberrypanda (192.168.50.151)

> **Current source of truth:** this file started as a 2026-06-05 deployment
> snapshot. AirPlay, the FiiO KA11 path, and Safe Sink were later recovered on
> real hardware. DLNA/gmrender has Pi-side service diagnostics, but Android
> phone casting is not yet usable in this version. Before using any older
> checklist below, read
> [field-note-2026-06-06-airplay-dlna-recovery.md](field-note-2026-06-06-airplay-dlna-recovery.md).

---

## 🎉 Deployment Summary

### ✅ Successfully Completed

#### System Foundation (Phase 1)
- **PipeWire**: v1.2.7 ✅
- **WirePlumber**: v0.4.13 ✅
- **Base Tools**: git, curl, build-essential, autoconf, automake, libtool, pkg-config ✅

#### Output Selection Layer (NEW - Core Feature)
- **Library**: `scripts/lib/output-target.sh` ✅
  - Single source of truth for output selection
  - Supports modes: `onboard | usb | auto`
  - Dynamic PipeWire sink matching (not hardcoded card numbers)
- **Scripts Deployed**: ✅
  - `scripts/setup-onboard-audio.sh` — configures Pi's 3.5mm AUX
  - `scripts/select-output.sh` — switch between outputs
  - `scripts/check-output.sh` — validate output configuration
- **User Config**: `~/.config/aurabridge/output.conf` ✅
  - Current verified setting: `AURABRIDGE_OUTPUT=usb`

#### Audio Output (Current: USB KA11 through Safe Sink)
- **Status**: ✅ **PASS** (verified on real Pi4 + Aura Studio 3)
- **Hardware**: FiiO KA11 USB DAC → 3.5mm AUX → Aura Studio 3 AUX-IN
- **Default Sink**: `aurabridge_safe_sink`
- **Safe Sink Downstream**: `alsa_output.usb-FIIO_FIIO_KA11-01.analog-stereo`
- **AirPlay Loudness Gain**: `1.30` with initial volume `1.00`
- **DLNA Safety Note**: old `gain=0.10` verification no longer applies after
  the louder AirPlay calibration.

#### Spotify Connect (Phase 3)
- **librespot**: v0.8.0 ✅ (compiled with pulseaudio-backend, rustls-tls-webpki-roots)
- **Service**: `~/.config/systemd/user/librespot.service` ✅
- **Status**: **active (running)** ✅
- **Device Name**: AuraStudio3Spotify
- **Audio Backend**: PulseAudio → PipeWire-Pulse → PipeWire
- **Features**:
  - OAuth login enabled (`--enable-oauth`)
  - Initial volume: 30
  - Restart on failure

### ⚠️ Known Issues & To-Do

#### AirPlay 2 (Phase 2)
- **Status**: ✅ Working on real Pi4 as of 2026-06-06
- **Backend**: Native PipeWire (`output_backend = "pipewire"`)
- **Discovery**: Avahi / Shairport constrained to `wlan0` IPv4
- **Output**: `aurabridge_safe_sink` → FiiO KA11 → Aura Studio 3 AUX
- **Components Installed**:
  - NQPTP (Precision Time Protocol) ✅
  - Shairport-sync (binary compiled) ✅
  - systemd service file ✅
- **Do Not Regress**: Do not switch Shairport Sync back to PulseAudio just to
  debug one symptom.
- **Device Name**: "Aura Studio 3 AirPlay"

---

## 🔧 System Service Status

| Service | Scope | Status | Notes |
|---------|-------|--------|-------|
| PipeWire | User | **active** | Audio engine |
| WirePlumber | User | **active** | Policy & session manager |
| PipeWire-Pulse | User | **active** | PulseAudio compatibility |
| librespot | User | **active** ✅ | Spotify Connect |
| shairport-sync | System | **active** ✅ | AirPlay 2, native PipeWire |
| nqptp | System | **active** ✅ | AirPlay 2 timing |
| avahi-daemon | System | **active** | mDNS/DNS-SD support |
| gmrender | User | **active** ⚠️ | Pi-side DLNA renderer only; Android casting not yet usable |

---

## 🎯 Current Capabilities

### ✅ Working Now
1. **AirPlay 2** via iPhone/Mac
   - Device appears as "Aura Studio 3 AirPlay"
   - Audio confirmed from Aura Studio 3 on 2026-06-06
   - Native PipeWire backend
   - Published on `wlan0` IPv4, port `7000`

2. **Spotify Connect** via Spotify app (iOS/macOS/Android)
   - Device appears as "AuraStudio3Spotify" in Spotify
   - First connection requires OAuth authorization
   - Audio output through PipeWire/Safe Sink to KA11

3. **Output Selection**
   - Current verified path: `usb` (FiiO KA11)
   - Auto mode: automatically detects and switches between outputs

### ⚠️ Still Separate / Not Core
1. **Android / DLNA phone casting** — not yet usable in this version. gmrender
   may be active for Pi-side diagnostics, but this is not a working Android
   playback path.
2. **Bluetooth A2DP** — currently separate from the AirPlay success path.
3. **Arbiter** — optional; install-only by default. Barge-in always mutes the
   loser and pauses DLNA; AirPlay pause (and its `--with-dbus` build) stay opt-in
   and use Pause, never Stop/disconnect.

### 🎵 Audio Stack (Current Flow)
```
AirPlay: Shairport Sync (native PipeWire)
Spotify/DLNA: PulseAudio API via pipewire-pulse
    ↓
PipeWire graph / WirePlumber
    ↓
aurabridge_safe_sink
    ↓
alsa_output.usb-FIIO_FIIO_KA11-01.analog-stereo
    ↓
FiiO KA11 → 3.5mm AUX → Aura Studio 3 (AUX-IN)
```

---

## 📋 Testing Checklist (Next Steps)

### Immediate Regression Test
- [ ] Open iPhone/Mac AirPlay picker
- [ ] Look for "Aura Studio 3 AirPlay"
- [ ] Play a test track at LOW volume
- [ ] Verify sound comes through Aura Studio 3
- [ ] Run `./scripts/status.sh` and compare with the 2026-06-06 field note

### Spotify Test
- [ ] Open Spotify app on iPhone/Mac
- [ ] Look for "AuraStudio3Spotify" in available devices
- [ ] If first connection: complete OAuth authorization (follow on-screen prompts)
- [ ] Play a test track at LOW volume
- [ ] Verify sound comes through Aura Studio 3
- [ ] Check Aura Studio 3 physical volume is low

### KA11 / Safe Sink Check
- [ ] Run: `./scripts/check-output.sh` (should detect USB)
- [ ] Run: `./scripts/status.sh`
- [ ] Confirm default sink is `aurabridge_safe_sink`
- [ ] Confirm Safe Sink downstream is the KA11 sink

---

## 🔐 Security & Best Practices

### Credentials & Caching
- **OAuth tokens**: Stored in `~/.cache/librespot/` (per librespot behavior)
- **Credential caching**: Currently disabled (can be enabled via config)
- **SSH Access**: Username `Panda`, password `040720` (see RASPBERRY_PI_CREDENTIALS.md)

### Volume Safety
- Initial PipeWire volume: **1.00** (post-calibration start level)
- **NOT** real-time protection — monitor audio carefully during first tests
- Keep Aura Studio 3 physical volume **LOW** until confirmed stable

---

## 📁 Key Files & Directories

**On Raspberry Pi:**
```
~/AuraBridge-Pi/
├── scripts/lib/output-target.sh          # Output selection library
├── scripts/setup-onboard-audio.sh        # Configure onboard audio
├── scripts/select-output.sh              # Switch outputs
├── scripts/check-output.sh               # Validate configuration
├── docs/onboard-audio.md                 # Onboard audio documentation
└── systemd/librespot.service             # Template (copied to user config)

~/.config/systemd/user/
├── librespot.service                     # Spotify service (active)

~/.config/aurabridge/
└── output.conf                           # Output selection config

~/.local/bin/
└── librespot → ~/.cargo/bin/librespot    # Symlink to binary
```

---

## 🚀 Rollback / Recovery

### If Something Goes Wrong

**Restore previous PipeWire sink (before onboard configuration):**
```bash
./scripts/safe-volume.sh
wpctl status | grep -A 5 "Sinks:"
```

**Switch back to USB DAC (when it arrives):**
```bash
./scripts/select-output.sh usb
./scripts/check-output.sh
```

**Restart services:**
```bash
systemctl --user restart librespot.service
systemctl --user restart pipewire.service
systemctl --user restart wireplumber.service
```

---

## 📞 Troubleshooting

### Spotify Device Not Appearing
1. Check librespot is running: `systemctl --user status librespot.service`
2. Verify avahi-daemon is running: `systemctl status avahi-daemon`
3. Restart: `systemctl --user restart librespot.service`
4. Check logs: `journalctl --user -u librespot.service -n 20`

### No Sound from Spotify
1. Verify output: `./scripts/check-output.sh`
2. Check PipeWire sink volume: `pactl list sinks | grep -A 3 "Volume"`
3. Check ALSA mixer: `amixer -c 2 scontrols`
4. Verify 3.5mm cable is connected to Aura Studio 3 AUX-IN
5. Ensure Aura Studio 3 physical volume is not at 0

### OAuth Authorization Loop
- librespot generates a Spotify OAuth URL on first run
- Browse to URL on your laptop (or phone) and authorize
- Device will cache credentials after first successful authorization

---

## ✅ Sign-Off

**Deployment Status**: ✅ **ONBOARD AUDIO PHASE COMPLETE**

- Core output selection layer deployed and tested
- Spotify Connect fully functional on onboard audio
- System ready for testing and subsequent phases
- FiiO KA11 USB DAC support ready (just switch with one command)

**Next Milestone**: Spotify audio test on Aura Studio 3

---

*Generated during 2026-06-04 deployment of AuraBridge Pi 2.2 onboard-audio variant*
*User: Panda | Device: raspberrypanda (192.168.50.151)*
