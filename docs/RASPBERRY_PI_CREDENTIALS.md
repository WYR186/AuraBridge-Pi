# Raspberry Pi 4 - Account & Connection Credentials

## Connection Information

**Recording Date**: 2026-06-04

### Network
- **Hostname**: `raspberrypanda`
- **IPv4 Address**: `192.168.50.151`
- **MAC Address**: `d8:3a:dd:15:b:a3`
- **Connection Type**: Ethernet/Wi-Fi (wlan0)
- **Network Subnet**: 192.168.50.0/24
- **Gateway**: 192.168.50.1

### SSH Access
```bash
# Using IP address
ssh Panda@192.168.50.151

# Using hostname (mDNS)
ssh Panda@raspberrypanda.local
```

---

## User Account

| Property | Value |
|----------|-------|
| **Username** | `Panda` |
| **Password** | `040720` |
| **User Group** | sudo (has sudo access) |
| **Home Directory** | `/home/Panda` |

---

## System Information

| Property | Value |
|----------|-------|
| **OS** | Debian GNU/Linux 12 (bookworm) |
| **Raspberry Pi OS** | Lite 64-bit |
| **Kernel** | 6.6.51+rpt-rpi-v8 |
| **Architecture** | aarch64 (ARM64) |
| **Boot Firmware** | `/boot/firmware` |
| **Root Filesystem** | `/dev/mmcblk0p2` (469GB total) |

---

## Project Setup Status

| Component | Version | Status |
|-----------|---------|--------|
| **PipeWire** | 1.2.7 | ✅ Installed |
| **WirePlumber** | 0.4.13 | ✅ Installed |
| **AuraBridge-Pi** | Phase 1 | ✅ Deployed at `~/AuraBridge-Pi` |
| **Base Tools** | - | ✅ Installed (git, curl, build-essential, etc.) |

---

## Audio System Status

**Default Sink**: `alsa_output.platform-bcm2835_audio.stereo-fallback`
**Default Volume**: 0.01 (post-calibration initial level)
**Onboard Audio**: bcm2835 Headphones (3.5mm AUX output)

---

## Quick Commands

### SSH Shortcut
```bash
sshpass -p "040720" ssh -o StrictHostKeyChecking=accept-new Panda@192.168.50.151
```

### Remote Execution Example
```bash
sshpass -p "040720" ssh Panda@192.168.50.151 'cd ~/AuraBridge-Pi && ./scripts/status.sh'
```

### File Transfer (SCP)
```bash
# Upload file to Pi
scp /local/path Panda@192.168.50.151:~/

# Download file from Pi
scp Panda@192.168.50.151:~/file.txt /local/path
```

---

## Important Notes

- ⚠️ **Credentials stored**: This file contains login credentials. Keep it secure.
- ✅ **Network reachable**: Confirmed 2026-06-04
- 🔋 **Powered**: Tree raspberry Pi is powered and running
- 📦 **Disk space**: 433GB available (3% used)
- 🎵 **Audio**: Onboard 3.5mm AUX output is ready for use
- 🔌 **FiiO KA11**: Not yet connected; using onboard audio for now

---

## Next Phase

User is implementing an **AuraBridge variant that uses the Raspberry Pi's onboard 3.5mm AUX output** instead of the FiiO KA11 USB DAC.

This accounts file supports both configurations.
