# Raspberry Pi 4 Setup & Connection Info

## Device Information

**Recorded**: 2026-06-04

### Network Connection
- **Device Hostname**: `raspberrypanda`
- **IPv4 Address**: `192.168.50.151`
- **MAC Address**: `d8:3a:dd:15:b:a3`
- **Connection Type**: Ethernet (en0)
- **Status**: ✅ Detected and reachable

## SSH Access

Connect to the Raspberry Pi via SSH:

```bash
ssh pi@192.168.50.151
# or using hostname
ssh pi@raspberrypanda.local
```

## First Boot Checklist

Before running any AuraBridge scripts, ensure:

1. **OS**: Raspberry Pi OS Lite 64-bit (headless)
2. **SSH**: Accessible from your Mac at the IP above
3. **Ethernet**: Connected (preferred over Wi-Fi for stability)
4. **Repos**: Clone or navigate to the AuraBridge-Pi repository:
   ```bash
   cd ~/AuraBridge-Pi
   ```

## Headless Mode Setup (Raspberry Pi OS)

The AuraBridge Pi 2.2 project **requires headless operation** (no monitor, keyboard, or mouse).

### If you installed with the Raspberry Pi Imager:

1. **Insert microSD card** into your Mac
2. **Open Raspberry Pi Imager** (https://www.raspberrypi.com/software/)
3. **Select OS**: Raspberry Pi OS (64-bit) → Raspberry Pi OS Lite
4. **Select Storage**: Your microSD card
5. **Advanced Options** (Ctrl/Cmd + Shift + X):
   - ✅ Set hostname: `raspberrypanda`
   - ✅ Enable SSH: Password authentication
   - ✅ Set username & password (default: `pi` / `raspberry`)
   - ✅ Configure Wi-Fi (optional; Ethernet preferred)
   - ✅ Set locale, keyboard, timezone

6. **Write** the image
7. **Eject** the microSD card and insert into Raspberry Pi 4

### If you installed manually:

Create an empty `ssh` file in the boot partition to enable SSH on first boot:

```bash
# On Mac, after flashing the image:
# 1. Mount the boot partition (usually auto-mounts)
# 2. Touch the file:
touch /Volumes/boot/ssh
# 3. Eject the card and insert into Pi
```

**Enable Wi-Fi** (if Ethernet unavailable):

Create `wpa_supplicant.conf` in the boot partition:

```bash
cat > /Volumes/boot/wpa_supplicant.conf << 'EOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
country=US

network={
    ssid="your-wifi-ssid"
    psk="your-wifi-password"
    key_mgmt=WPA-PSK
}
EOF
```

Replace `your-wifi-ssid` and `your-wifi-password` with your actual Wi-Fi credentials.

## Troubleshooting Headless Boot

**Problem**: Cannot SSH to the Pi
**Solution**:
1. Verify the Pi is powered and the LED blinks
2. Check your network router for the device IP
3. Ensure SSH is enabled (see above)
4. Try `ssh pi@raspberrypanda.local` (mDNS discovery)

**Problem**: No network connection after boot
**Solution**:
1. Check Ethernet cable is properly seated
2. If using Wi-Fi, verify `wpa_supplicant.conf` has correct SSID/password
3. Reboot: `sudo reboot`

## Running AuraBridge Scripts

After first boot and SSH verification, follow the Phase 0-3 runbook:

```bash
cd ~/AuraBridge-Pi
./scripts/setup-base.sh
./scripts/setup-pipewire.sh
./scripts/wireplumber-version-check.sh
./scripts/check-ka11.sh
./scripts/safe-volume.sh
./scripts/install-airplay2.sh
./scripts/install-spotify.sh
```

See [pi-bringup-checklist.md](pi-bringup-checklist.md) and [first-boot-runbook.md](first-boot-runbook.md) for detailed steps.
