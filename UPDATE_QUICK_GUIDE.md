# AuraBridge Pi — Quick Update & Backup Guide

## 🚀 One-Minute Summary

**Your Raspberry Pi is designed to be safely updated without losing data.**

- **Code** (scripts, apps) → Updated via `git pull` or recompilation
- **Config** (settings, tokens) → Stored in `~/.config/` and `~/.cache/` → **Never overwritten**
- **Data** (Spotify login, audio settings) → Preserved automatically

---

## 📋 Quick Workflow

### Before Any Update (Optional but Recommended)

```bash
# Backup configs from your Mac (2 minutes)
~/backup-aurabridge-pi.sh

# Or manually
sshpass -p "040720" ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/diagnose.sh"
```

### For Script Updates Only (Fast Path)

**When:** Documentation, bug fixes in bash scripts, new diagnostics

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi
git pull origin main
./scripts/diagnose.sh
```

**Time:** 2-5 minutes | **Risk:** Very low | **Compilation:** No

---

### For Spotify / Service Updates (Medium Path)

**When:** New Spotify version, updated service configuration

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi
git pull origin main

# Recompile just Spotify
source ~/.cargo/env
cargo install librespot --locked --no-default-features \
  --features pulseaudio-backend,rustls-tls-webpki-roots --force

# Restart
systemctl --user restart librespot.service
systemctl --user status librespot.service
```

**Time:** 5-15 minutes | **Risk:** Low | **Compilation:** Yes, one service

---

### For Full System Updates (Thorough Path)

**When:** Major changes, new dependencies, complete rebuild needed

```bash
# Backup first
~/backup-aurabridge-pi.sh --full

ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi
git pull origin main

# Run all setup scripts (idempotent = safe)
./scripts/setup-base.sh
./scripts/setup-pipewire.sh
./scripts/install-airplay2.sh
./scripts/install-spotify.sh

# Verify
./scripts/diagnose.sh
```

**Time:** 20-60 minutes | **Risk:** Medium | **Compilation:** Everything

---

## 💾 Backup Script Usage

### Backup Configs (Recommended, Weekly)

```bash
~/backup-aurabridge-pi.sh
# or
~/backup-aurabridge-pi.sh --config
```

Creates backup in `~/backups/aurabridge/YYYYMMDD-HHMMSS/`

**Includes:**
- Spotify OAuth tokens
- Output configuration (onboard/usb/auto)
- Service settings
- System diagnostics

**Size:** ~1-10 MB  
**Time:** 2-3 minutes

### Backup Everything (Monthly, or before major updates)

```bash
~/backup-aurabridge-pi.sh --full
```

**Includes:** Everything + compiled binaries  
**Size:** 1-2 GB  
**Time:** 5-10 minutes

### Backup Diagnostics Only

```bash
~/backup-aurabridge-pi.sh --diagnose
```

**For:** Troubleshooting, before-after comparison  
**Size:** ~5-10 KB  
**Time:** < 1 minute

---

## 🔄 If Update Breaks Something

### Quick Rollback (Git)

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi

# Undo last update
git revert HEAD

# Or go back to specific version
git log --oneline -10
git checkout <old-commit>

# Restart affected service
systemctl --user restart librespot.service
```

### Restore from Backup

```bash
# Find your backup
ls ~/backups/aurabridge/

# Restore configs
BACKUP=~/backups/aurabridge/20260605-120000
sshpass -p "040720" scp -r $BACKUP/.config/aurabridge/ Panda@192.168.50.151:~/.config/

# Restart
sshpass -p "040720" ssh Panda@192.168.50.151 "systemctl --user restart librespot.service"
```

---

## ✅ What's Protected (Never Overwritten)

```
✅ ~/.config/aurabridge/output.conf           # Your output mode (onboard/usb/auto)
✅ ~/.cache/librespot/                        # Spotify login tokens
✅ ~/.config/systemd/user/librespot.service   # Custom service file
✅ Any config file in ~/.config/              # All user configs
✅ Any config file in ~/.local/               # User binaries, data
```

These are **yours** — they survive all updates.

---

## ❌ What Gets Updated (Can be Overwritten)

```
❌ ~/AuraBridge-Pi/scripts/                   # Bash scripts (git-managed)
❌ ~/AuraBridge-Pi/docs/                      # Documentation (git-managed)
❌ Compiled binaries (optional recompile)     # Only if you rebuild
```

These are **from the project** — updated when you `git pull`

---

## 🎯 Update Decision Tree

```
Want to update? → YES

├─ Just bug fixes / scripts?
│  └─ git pull (2 min, no risk)
│
├─ Spotify or one service changed?
│  └─ cargo install librespot (10 min, low risk)
│
├─ Major changes / new features?
│  └─ Full rebuild (30 min, medium risk)
│     → Backup first with --full
│
└─ Emergency / corrupted system?
   └─ Fresh SD card + restore backup (60 min)
```

---

## 📅 Recommended Schedule

| Task | Frequency | Time | Command |
|------|-----------|------|---------|
| Check status | Before updates | 2 min | `./scripts/diagnose.sh` |
| Backup configs | Weekly | 2 min | `~/backup-aurabridge-pi.sh` |
| Update scripts | As needed | 5 min | `git pull` |
| Full backup | Monthly | 10 min | `~/backup-aurabridge-pi.sh --full` |
| Full rebuild | Quarterly | 30 min | Full system update |

---

## 🔍 Verification After Update

**Always verify after updates:**

```bash
# Quick check (1 minute)
./scripts/diagnose.sh --brief

# Or full diagnostics (5 minutes)
./scripts/diagnose.sh --full

# Expected output
✅ All systems nominal (8/8) — Ready for playback!

# Test Spotify (5 minutes)
# Open Spotify app → Find "AuraStudio3Spotify" → Play test track
```

---

## 📞 Emergency Recovery

### If Completely Broken

```bash
# 1. Restore full backup (if you have it)
BACKUP=~/backups/aurabridge/20260605-100000
tar -xzf $BACKUP/pi-full-backup.tar.gz -C /tmp/

# 2. Or re-flash SD card
# Download Raspberry Pi Imager
# Flash fresh OS
# Restore configs from backup

# 3. Or contact for help with diagnostics
./scripts/diagnose.sh --full > ~/debug-info.txt
# Share the output for debugging
```

---

## 💡 Pro Tips

1. **Always backup before `--full` mode**
2. **Use incremental updates** (faster, safer)
3. **Test updates on non-critical times** (not during important listening)
4. **Keep backups for 1 month** (auto-cleanup keeps last 10)
5. **Check git diff before pulling** (`git diff origin/main`)
6. **Version-tag releases** for easy rollback

---

## Full Documentation

See `docs/UPDATE_STRATEGY.md` for:
- Detailed update workflows
- Troubleshooting guide
- Version tracking
- Advanced backup strategies

---

## Quick Reference

```bash
# Backup
~/backup-aurabridge-pi.sh

# Update (choose one)
git pull                                          # Scripts only
cargo install librespot --force                   # Spotify only
./scripts/setup-base.sh && ./scripts/setup-pipewire.sh && ./scripts/install-spotify.sh  # Full

# Verify
./scripts/diagnose.sh

# Rollback
git revert HEAD
```

---

**Bottom line: Your data is safe. Updates are incremental and reversible.** ✅

For questions, see `docs/UPDATE_STRATEGY.md` or run `./scripts/diagnose.sh --full`.
