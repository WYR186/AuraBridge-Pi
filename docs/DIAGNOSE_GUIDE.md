# AuraBridge Status Diagnostic Script

## Overview

`scripts/diagnose.sh` provides a **comprehensive, color-coded system status check** for AuraBridge Pi 2.2.

At a glance, you can see:
- System info & uptime
- Network connectivity
- Audio configuration (onboard vs USB)
- PipeWire sinks & volume
- Service status (Spotify, AirPlay, etc.)
- Recent errors
- Overall health score

---

## Usage

### Run from your Mac (Remote)

```bash
sshpass -p "040720" ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/diagnose.sh"
```

### Run from Raspberry Pi (Local SSH)

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi
./scripts/diagnose.sh              # Normal mode (balanced output)
./scripts/diagnose.sh --brief      # Quick summary only
./scripts/diagnose.sh --full       # Complete diagnostic (verbose)
```

---

## Modes

### Normal Mode (Default)
Shows the essentials: system info, network, audio config, sinks, services, and summary.

**Best for:** Quick status checks, everyday use

**Output includes:**
- System Information
- Network & Connectivity  
- Output Configuration
- PipeWire Sinks
- AuraBridge Services
- Quick Summary

### Brief Mode (`--brief`)

Minimal output focusing on critical systems.

**Best for:** Monitoring scripts, quick checks

**Output includes:**
- System Information
- Network & Connectivity
- AuraBridge Services (status only)
- Quick Summary

### Full Mode (`--full`)

**Comprehensive diagnostic** with all details, memory usage, recent errors, etc.

**Best for:** Troubleshooting, debugging, first-time setup verification

**Output includes:**
- All of normal mode, plus:
- PipeWire & Audio Engine details
- ALSA Audio Devices
- Disk & Memory Usage
- Recent Errors & Warnings (last 24h)

---

## Output Explanation

### Status Symbols

| Symbol | Meaning | Example |
|--------|---------|---------|
| ✅ | OK / Running | `✅ Network connected` |
| ❌ | Failed / Problem | `❌ System issues detected` |
| ⚠️ | Warning | `⚠️ AirPlay not running` |
| ℹ️ | Info / Note | `ℹ️ Current output mode: onboard` |
| ⏳ | Pending / In progress | (not commonly shown) |

### Health Score

The **Quick Summary** shows a score like:

```
✅ All systems nominal (8/8) — Ready for playback!
ℹ️ Most systems operational (7/8) — Functional, minor issues
⚠️ Partial functionality (5/8) — Some services missing
❌ Critical issues (2/8) — Check above for details
```

**What counts:**
- PipeWire running
- WirePlumber running
- PipeWire-Pulse running
- Spotify (librespot) running
- Output config file exists
- Avahi (mDNS) running
- PulseAudio tools installed
- Network connected

---

## Example Output (Normal Mode)

```
═══ System Information ═══
  Hostname:                           raspberrypanda
  Model:                              Raspberry Pi 4 Model B Rev 1.5
  OS:                                 Debian GNU/Linux 12 (bookworm)
  Kernel:                             6.6.51+rpt-rpi-v8
  Uptime:                             up 44 minutes

═══ Network & Connectivity ═══
✅ Network connected
  IP Address:                         192.168.50.151
✅ Internet reachable
✅ mDNS (Avahi) running

═══ Output Configuration (Dual-Output Layer) ═══
► Configured Output
✅ Configuration found
  Mode:                               onboard
► Effective Output
✅ Onboard audio (3.5mm) is active

═══ PipeWire Sinks (Audio Outputs) ═══
► Available Sinks
ℹ️ Sink 71: alsa_output.platform-bcm2835_audio.stereo-fallback (48000Hz)
► Default Sink Volume
  Volume: front-left: 19661 / 30% / -31.37 dB

═══ AuraBridge Services ═══
► Spotify (Phase 3)
  librespot:  active
✅ Running (PID 31457)
► AirPlay 2 (Phase 2)
  shairport-sync: failed
⚠️ Not running (audio backend issue)

═══ Quick Summary ═══
✅ All systems nominal (8/8) — Ready for playback!
═════════════════════════════════════════════════════════════
ℹ️ Current output mode: onboard
   To switch: ./scripts/select-output.sh [onboard|usb|auto]
```

---

## Interpreting Results

### Everything Green ✅
System is fully operational and ready for audio playback.

**Next step:** Test Spotify on your device!

### Some Yellow ⚠️
Most things work, but something needs attention.

**Common issues:**
- **AirPlay not running?** This is expected — it needs PulseAudio backend configuration (optional, not critical)
- **Network unavailable?** Check Ethernet/Wi-Fi connection
- **Output unknown?** Try `./scripts/check-output.sh` for detailed audio debugging

### Red Items ❌
Something is broken and needs fixing.

**Common fixes:**
```bash
# Restart all core services
systemctl --user restart pipewire wireplumber pipewire-pulse

# Restart Spotify
systemctl --user restart librespot.service

# Check detailed logs
journalctl --user -u librespot.service -n 50
```

---

## Color Legend

| Color | Meaning |
|-------|---------|
| 🟢 Green | All good, service running |
| 🔴 Red | Failed, not running, error |
| 🟡 Yellow | Warning, partial functionality |
| 🔵 Blue | Headers, section titles |
| 🔷 Cyan | Info, details, sub-sections |

---

## Troubleshooting With Diagnose

### "Sink volume unknown"
PulseAudio tools may not be fully initialized. This usually resolves on its own after restart.

### "Output unknown"
Run the full diagnostic:
```bash
./scripts/diagnose.sh --full | grep -A20 "PipeWire Sinks"
```

### "Spotify not running"
Check why it stopped:
```bash
journalctl --user -u librespot.service -n 30
systemctl --user restart librespot.service
./scripts/diagnose.sh
```

### "Internet unreachable but playback works"
This is OK! Local playback (Spotify Connect, AirPlay) doesn't need Internet. The warning is informational.

---

## Automated Monitoring (Optional)

### Watch status every 5 seconds
```bash
watch -n 5 "cd ~/AuraBridge-Pi && ./scripts/diagnose.sh --brief"
```

### Log status every hour
```bash
(crontab -l; echo "0 * * * * cd ~/AuraBridge-Pi && ./scripts/diagnose.sh >> /tmp/aurabridge-status.log") | crontab -
```

### Remote check from Mac
```bash
watch "sshpass -p '040720' ssh Panda@192.168.50.151 'cd ~/AuraBridge-Pi && ./scripts/diagnose.sh --brief'"
```

---

## Next Steps

Once diagnostics show all green:

1. **Test Spotify** — Open Spotify app, find "AuraStudio3Spotify" device, play a track
2. **Check audio** — Verify sound comes through Aura Studio 3
3. **When FiiO KA11 arrives** — Switch output with `./scripts/select-output.sh usb`
4. **Fix AirPlay** (optional) — Configure shairport-sync if needed

---

## Tips

- **Run regularly** — Check status before troubleshooting issues
- **Bookmark it** — Add to favorites for quick access
- **Share results** — If asking for help, paste the output
- **Check --full** — When debugging, full mode shows error logs
- **Use remote check** — Monitor from your Mac without SSH-ing in

---

## Technical Details

### What the script checks

**System:**
- Hostname, Pi model, OS version, kernel, uptime

**Network:**
- IP address, Internet connectivity (ping 8.8.8.8), mDNS (avahi)

**Audio:**
- PipeWire/WirePlumber status
- Output configuration (onboard vs USB)
- ALSA audio devices and PipeWire sinks
- Default sink volume
- Sink sample rate & format

**Services:**
- librespot (Spotify) — user service
- shairport-sync (AirPlay) — system service
- avahi-daemon (mDNS) — system service
- PipeWire core services — user services

**Errors:**
- Recent 24-hour error logs from each service
- Service failure reasons

**Resources:**
- Memory usage (total, used, available)
- Disk usage (root, home)

---

*Last updated: 2026-06-05*
*AuraBridge Pi 2.2 Diagnostic Guide*
