# AuraBridge Pi 2.2 — Deployment Plan for Latest Code

**Status**: You have **11 new features** and **4 modified files** ready to deploy to Raspberry Pi  
**Risk Level**: 🟡 Medium (new features, but with safeguards)  
**Estimated Time**: 30-60 minutes

---

## 📊 Current Code Status

### Local Changes (Not Yet Committed)

#### Modified Files (4)
```
✏️ scripts/install-airplay2.sh      — Fixed AirPlay 2 PulseAudio detection
✏️ scripts/setup-bluetooth.sh        — New version-matched BT policy
✏️ docs/airplay2.md                 — Updated AirPlay docs
✏️ docs/bluetooth-policy.md          — New Bluetooth anti-hijack policy
```

#### New Features (11)
```
🆕 scripts/setup-readonly.sh         — Read-only root filesystem (Phase 7)
🆕 scripts/toggle-rw.sh             — Temporarily disable read-only mode
🆕 scripts/rollback-readonly.sh      — Rollback read-only setup
🆕 docs/readonly-rootfs.md          — Read-only filesystem documentation
🆕 scripts/diagnose.sh              — System status diagnostic tool
🆕 docs/DEPLOYMENT_STATUS.md        — Deployment status documentation
🆕 docs/DIAGNOSE_GUIDE.md           — Diagnostic tool usage guide
🆕 docs/UPDATE_STRATEGY.md          — Update and backup strategy
🆕 docs/RASPBERRY_PI_CREDENTIALS.md — Pi credentials and connection info
🆕 docs/USB_DAC_DETECTION.md        — USB DAC detection documentation
🆕 UPDATE_QUICK_GUIDE.md            — Quick update guide
```

### Branch Status
```
Branch: codex-output-selection
Latest: e96a6c2 "Add selectable audio output"
Remote: up to date with origin/codex-output-selection
```

---

## 🎯 Key Changes to Deploy

### 1. **AirPlay 2 Fix** (High Priority)
**Status**: ✅ Tested, working  
**What it does**: Shairport-sync now correctly detected with PulseAudio backend  
**Risk**: Low (bug fix only)

```bash
# Changed in scripts/install-airplay2.sh
- OLD: PA_FLAG=$(grep "with-PACKAGE" configure | grep pa)  ❌ Bogus match
- NEW: PA_FLAG=$(grep -E "^\s+--with-(pa|pulseaudio)" configure) ✅ Correct
```

### 2. **Bluetooth Anti-Hijack Policy** (Medium Priority)
**Status**: 🆕 New, not yet tested on Pi  
**What it does**: Bluetooth A2DP can't hijack the audio output route  
**Risk**: Medium (new feature, but reversible)

```bash
# New in scripts/setup-bluetooth.sh
- Detects WirePlumber version (0.4.x Lua vs 0.5.x SPA-JSON)
- Writes matching policy to prevent BT from stealing the active sink
- Idempotent (safe to re-run)
- Rollback available (--rollback-policy)
```

### 3. **Read-Only Root Filesystem** (Lower Priority)
**Status**: 🆕 New, NOT tested on Pi  
**What it does**: Survives power loss without SD card corruption  
**Risk**: High (requires reboot, complex reversal)

```bash
# New in scripts/setup-readonly.sh
- Creates ext4 image for persistent state (/var/lib/bluetooth, WirePlumber config)
- Enables OverlayFS read-only root (via raspi-config)
- Requires reboot to take effect
- Fully reversible but complex
```

### 4. **Diagnostic Tool** (Helper)
**Status**: ✅ Tested and working  
**What it does**: One-command system health check with USB DAC detection  
**Risk**: Very Low (no side effects, read-only)

---

## 🚀 Deployment Plan

### Phase 1: Preparation (5 minutes)

```bash
# 1. Commit current changes locally (optional but recommended)
cd ~/Documents/project/AuraBridge-Pi
git add scripts/install-airplay2.sh scripts/setup-bluetooth.sh docs/*.md
git commit -m "Fix AirPlay backend detection; add BT anti-hijack policy"

# 2. Add diagnostic tool and docs to git (optional)
git add scripts/diagnose.sh docs/DEPLOYMENT_STATUS.md docs/DIAGNOSE_GUIDE.md docs/UPDATE_STRATEGY.md UPDATE_QUICK_GUIDE.md
git commit -m "Add diagnostic tool and deployment documentation"

# 3. Tag this version
git tag -a v2.2-airplay-fix-20260605 -m "AirPlay fix + BT policy + diagnostics"

# 4. Backup current Pi state (just in case)
~/backup-aurabridge-pi.sh --full
```

### Phase 2: Deploy to Pi (10 minutes)

**Option A: Push via Git (Recommended if you've committed)**

```bash
# On Pi:
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi
git pull origin codex-output-selection

# Verify what changed
git log -3 --oneline
git diff HEAD~1

# Run preflight check
./scripts/diagnose.sh --brief
```

**Option B: Upload via SCP (If you haven't committed yet)**

```bash
# From Mac:
sshpass -p "040720" scp -r \
  scripts/install-airplay2.sh \
  scripts/setup-bluetooth.sh \
  docs/airplay2.md \
  docs/bluetooth-policy.md \
  docs/readonly-rootfs.md \
  scripts/setup-readonly.sh \
  scripts/toggle-rw.sh \
  scripts/rollback-readonly.sh \
  scripts/diagnose.sh \
  Panda@192.168.50.151:~/AuraBridge-Pi/
```

### Phase 3: Deploy Changes (Choose Your Path)

#### Path A: **Deploy AirPlay Fix Only** (RECOMMENDED FIRST)
⏱️ Time: 10 minutes | 🟢 Risk: Low

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi

# 1. Backup current shairport-sync
cp ~/.cargo/bin/shairport-sync ~/.cargo/bin/shairport-sync.backup.20260605

# 2. Rebuild AirPlay with fixed detection
./scripts/install-airplay2.sh 2>&1 | tail -30

# 3. Verify
systemctl status shairport-sync
journalctl -u shairport-sync -n 10

# 4. Test on iPhone/Mac
# Look for "Aura Studio 3 AirPlay" device → should connect now
```

#### Path B: **Deploy AirPlay Fix + Bluetooth Policy** (MEDIUM)
⏱️ Time: 20 minutes | 🟡 Risk: Medium

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi

# 1. Deploy AirPlay fix (see Path A above)

# 2. Deploy Bluetooth setup
./scripts/setup-bluetooth.sh  # Uses YOUR user (Panda)

# 3. Verify
systemctl status bluetooth
wpctl status | grep -A 5 "Bluetooth"
journalctl --user -u wireplumber -n 10

# 4. Test Bluetooth pairing
# Run bt-pairing-window.sh, then pair a device
```

#### Path C: **Full Deployment** (ALL FEATURES)
⏱️ Time: 60 minutes | 🟠 Risk: Medium-High (reboot required)

```bash
ssh Panda@192.168.50.151

# 1-2. Deploy AirPlay fix (Path A)
# 3. Deploy Bluetooth policy (Path B)

# 4. Enable read-only root filesystem (requires reboot!)
cd ~/AuraBridge-Pi
./scripts/setup-readonly.sh

# 5. REBOOT (critical!)
sudo reboot

# 6. Verify after reboot
./scripts/diagnose.sh --full
mount | grep -i overlay
```

---

## ✅ Verification Steps

### After Deployment (Always Do This)

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi

# Quick check (1 minute)
./scripts/diagnose.sh --brief
# Expected: ✅ All systems nominal (8/8) — Ready for playback!

# Full diagnostic (5 minutes)
./scripts/diagnose.sh --full

# Check specific changes
echo "=== AirPlay 2 Status ==="
systemctl status shairport-sync | head -10

echo "=== Bluetooth Status ==="
systemctl status bluetooth | head -10

echo "=== Spotify Status ==="
systemctl --user status librespot.service | head -10

# Test audio
echo "=== PipeWire Sinks ==="
pactl list short sinks
```

### Audio Test (5 minutes)

**For Spotify:**
```bash
# On iPhone/Mac
# 1. Open Spotify
# 2. Find "AuraStudio3Spotify" → Connect
# 3. Play test track → Should hear sound on Aura Studio 3
```

**For AirPlay (if deployed):**
```bash
# On iPhone/Mac
# 1. Control Center → AirPlay → Find "Aura Studio 3 AirPlay"
# 2. Play any audio → Should hear through Aura Studio 3
```

**For Bluetooth (if deployed):**
```bash
# On iPhone/Mac
# 1. Bluetooth Settings → Find "Aura Studio 3 BT"
# 2. Pair (if pairing window open)
# 3. Play audio → Should hear through Aura Studio 3
```

---

## 🔄 Rollback Plan (If Something Breaks)

### For AirPlay Fix

```bash
ssh Panda@192.168.50.151

# Restore backup
cp ~/.cargo/bin/shairport-sync.backup.20260605 ~/.cargo/bin/shairport-sync

# Restart
systemctl restart shairport-sync

# Or revert code
cd ~/AuraBridge-Pi
git revert HEAD~1  # Go back before AirPlay commit
git log --oneline -3
```

### For Bluetooth Policy

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi

# Rollback policy only (keeps BT enabled)
./scripts/setup-bluetooth.sh --rollback-policy

# Or full rollback
git revert HEAD
```

### For Read-Only Filesystem

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi

# BEFORE REBOOT: disable overlay
sudo raspi-config nonint disable_overlayfs

# Teardown persistence layer
./scripts/rollback-readonly.sh

# Then reboot
sudo reboot
```

### Full Restore from Backup

```bash
# On Mac
BACKUP=~/backups/aurabridge/20260605-120000
sshpass -p "040720" scp -r $BACKUP/.config/aurabridge/ Panda@192.168.50.151:~/.config/
sshpass -p "040720" ssh Panda@192.168.50.151 "systemctl --user restart librespot.service"
```

---

## 📋 Pre-Deployment Checklist

```
Before you start:
  ☐ Pi is powered and online (ping 192.168.50.151)
  ☐ Spotify is playing (optional but good to verify before/after)
  ☐ You have a backup (run ~/backup-aurabridge-pi.sh --full)
  ☐ You understand what you're deploying (read above)

Deployment:
  ☐ Choose your path (A=AirPlay only, B=AirPlay+BT, C=All)
  ☐ Run the deployment commands
  ☐ Watch for errors (don't ignore warnings)
  ☐ Wait for compilation to finish (5-20 min)

Verification:
  ☐ Run ./scripts/diagnose.sh
  ☐ Check "All systems nominal" message
  ☐ Test audio (Spotify, AirPlay, or BT)
  ☐ Check no new errors in logs

Post-Deployment:
  ☐ Take a new diagnostic backup (~backup-aurabridge-pi.sh)
  ☐ Tag the version in git (on your Mac)
  ☐ Update your MEMORY.md with new status
```

---

## 🎯 My Recommendation

### **Start with Path A (AirPlay Fix Only)**

1. **Why**: 
   - Low risk, proven to work
   - Fixes a real bug (AirPlay was broken)
   - No reboot needed
   - Easy to rollback

2. **Then test for 1-2 days**:
   - Try AirPlay on your iPhone
   - Check system stability
   - Verify no new errors

3. **If Path A is stable, do Path B or C**:
   - Path B adds Bluetooth protection (medium risk)
   - Path C adds power-loss resilience (high complexity)

---

## 📝 What Will Happen

### After Deploying AirPlay Fix Only
```
Current: ✅ Spotify ✅ Onboard audio ❌ AirPlay (broken)
After:   ✅ Spotify ✅ Onboard audio ✅ AirPlay (fixed!)
```

### After Deploying Path B (AirPlay + BT Policy)
```
Added: Bluetooth A2DP anti-hijack
       BT can't steal the audio output anymore
       Safer concurrent audio sources
```

### After Deploying Path C (Full)
```
Added: Read-only root filesystem
       Survives sudden power loss
       More resilient to corruption
       Requires careful management (toggle-rw.sh for updates)
```

---

## ⚠️ Important Notes

1. **Read-only filesystem requires reboot** — Full system takes 30 seconds to boot
2. **Bluetooth policy depends on WirePlumber version** — Script auto-detects and uses matching config
3. **All deployments are reversible** — You have rollback scripts and backups
4. **Git commit before deploying** — Easier to track changes and rollback

---

## 🚀 Ready?

Choose your path and let me know! I can:
1. Walk you through each step
2. Monitor the deployment
3. Help troubleshoot if something breaks
4. Create new backups before/after

**Recommended first step**: 
```bash
# See the exact changes
cd ~/Documents/project/AuraBridge-Pi
git diff --stat
git diff
```

Then decide: **Path A, B, or C?**

---

*AuraBridge Pi 2.2 Deployment Plan*  
*Generated: 2026-06-05*
