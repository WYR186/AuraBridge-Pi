# USB DAC Detection & Support

## Overview

The diagnostic script (`scripts/diagnose.sh`) now automatically **detects and identifies USB audio DACs** (小尾巴) connected to your Raspberry Pi.

---

## Supported USB DACs

### ✅ Officially Supported

| Device | Device ID | Status | Notes |
|--------|-----------|--------|-------|
| **FiiO KA11** | `2204:0003` | ✅ Designed for | Original target device |
| **FiiO KA13** | `2204:0004` | ✅ Compatible | Similar specs to KA11 |
| **FiiO BTR7** | `2204:0005` | ✅ Compatible | Bluetooth + USB |
| **Meizu HiFi DAC Pro** | `2a45:0126` | ✅ Tested | Currently used in test setup |
| **Meizu HiFi DAC** | `2a45:0120` | ✅ Compatible | Earlier version |

### ℹ️ Generic Support

These devices will be detected but may need manual configuration:
- **C-Media USB Audio** (`0d8c:*`)
- **XMOS USB Audio** (`1852:7022`)
- **Logitech USB Audio** (`046d:*`)
- Any USB device with "audio" in the description

---

## How Detection Works

### 1. Automatic Detection
When you run the diagnostic:

```bash
./scripts/diagnose.sh
```

The script checks for connected USB devices using `lsusb` and matches known DAC IDs.

### 2. Output Example

**If FiiO KA11 is connected:**
```
═══ USB Audio Devices (小尾巴 / USB DAC Detection) ═══
► Connected USB Devices
✅ FiiO DAC detected! (小尾巴 present)
  Bus 001 Device 003: ID 2204:0003 FiiO Electronics Co., Ltd. KA11
    → Type: FiiO KA11
```

**If Meizu HiFi DAC is connected:**
```
═══ USB Audio Devices (小尾巴 / USB DAC Detection) ═══
► Connected USB Devices
ℹ️ Meizu HiFi DAC detected:
  Bus 001 Device 003: ID 2a45:0126 Meizu Corp. Meizu HiFi DAC Headphone Amplifier PRO
    → Type: Meizu HiFi DAC Headphone Amplifier PRO
```

**If no USB DAC is connected:**
```
═══ USB Audio Devices (小尾巴 / USB DAC Detection) ═══
► Connected USB Devices
⚠️ No USB audio DAC detected (only onboard audio available)
  Use ./scripts/select-output.sh usb to switch when you connect one
```

---

## Using Detected USB DACs

### Check if Your DAC is Detected

```bash
./scripts/diagnose.sh | grep -A5 "USB Audio"
```

### Switch to USB DAC Output

Once detected:

```bash
./scripts/select-output.sh usb
./scripts/check-output.sh         # Verify it's the default sink
```

### Verify in PipeWire

```bash
pactl list short sinks | grep -i "usb\|fiio\|meizu"
```

### Test Audio

1. Open Spotify app
2. Select "AuraStudio3Spotify" device
3. Play test track
4. Check Aura Studio 3 for sound

---

## When FiiO KA11 Arrives

### Setup Steps

1. **Connect the KA11**
   - Use USB-A → Type-C adapter (must be data, not charge-only)
   - Connect to Raspberry Pi USB port

2. **Verify it's detected**
   ```bash
   ./scripts/diagnose.sh | grep -A3 "USB Audio"
   # Should show: ✅ FiiO DAC detected! (小尾巴 present)
   ```

3. **Switch to USB output**
   ```bash
   ./scripts/select-output.sh usb
   ```

4. **Verify it's the default sink**
   ```bash
   ./scripts/check-output.sh
   # Should show: FiiO KA11 is default sink
   ```

5. **Test Spotify again**
   - Audio now flows through FiiO KA11 → 3.5mm → Aura Studio 3

---

## Troubleshooting USB DAC Issues

### DAC Not Detected

**Check 1: Is it plugged in?**
```bash
lsusb | grep -i "fiio\|meizu\|audio"
```

**Check 2: Try reconnecting**
```bash
# Unplug and wait 5 seconds
# Plug back in
sleep 5
./scripts/diagnose.sh
```

**Check 3: Is it a data cable?**
Charging-only cables won't work. Try a different USB cable.

**Check 4: Try a different USB port**
Some Pi USB ports are more stable than others. Try USB 2.0 ports if 3.0 fails.

### DAC Detected but No Sound

1. **Verify it's the default sink:**
   ```bash
   ./scripts/check-output.sh
   ```

2. **Try auto mode:**
   ```bash
   ./scripts/select-output.sh auto
   ```

3. **Restart audio services:**
   ```bash
   systemctl --user restart pipewire.service
   systemctl --user restart librespot.service
   ```

4. **Check ALSA:**
   ```bash
   aplay -l  # Should show FiiO device
   ```

---

## Device IDs (Technical Reference)

If your USB DAC isn't recognized, you can find its device ID:

```bash
lsusb -v  # Detailed output with device IDs
# Look for: "ID XXXX:XXXX" format
```

Then contact us with the output.

---

## Adding Support for New DACs

To add support for a new USB DAC:

1. Find its device ID: `lsusb | grep <device-name>`
2. Edit `scripts/diagnose.sh`, find the `get_dac_name()` function
3. Add a case entry:
   ```bash
   "2a45:0126") echo "Your Device Name" ;;
   ```

---

## Current Test Status

**As of 2026-06-05:**
- ✅ Meizu HiFi DAC Pro (2a45:0126) — Detected and working
- ⏳ FiiO KA11 (2204:0003) — Ready to test when device arrives
- ⏳ Other FiiO models — Expected to be compatible

---

## Related Commands

```bash
# Comprehensive diagnostic
./scripts/diagnose.sh --full

# Check only USB devices
lsusb

# Check only audio configuration
./scripts/check-output.sh

# Switch output mode
./scripts/select-output.sh [onboard|usb|auto]

# View PipeWire sinks
pactl list short sinks
```

---

## Next Steps

1. **Run diagnostic** to see what's currently connected
2. **When FiiO KA11 arrives**, plug it in and test
3. **Use auto mode** for seamless switching
4. **Report issues** with your specific DAC model

---

*USB DAC detection added to AuraBridge Pi 2.2 on 2026-06-05*
*Current test device: Meizu HiFi DAC Pro*
*Target device: FiiO KA11*
