# AuraBridge Pi 2.2 — Update & Configuration Management Strategy

## Overview

This guide explains how to safely update your Raspberry Pi with new code while **preserving configuration, data, and audio settings**.

**Key principle**: Configuration and data are **separate from code**. Updates are **incremental**, not full rewrites.

---

## Update Strategies

### 📊 Comparison

| Strategy | Time | Risk | Preserves Config | Preserves Data | When to Use |
|----------|------|------|-----------------|----------------|-------------|
| **Git Pull** | 2-5 min | ⭐ Very Low | ✅ Yes | ✅ Yes | Scripts only, no compilation |
| **Incremental Compile** | 5-15 min | ⭐⭐ Low | ✅ Yes | ✅ Yes | One service changed (Spotify, etc) |
| **Full Rebuild** | 20-60 min | ⭐⭐⭐ Medium | ✅ Yes | ✅ Yes | Major changes, new dependencies |
| **Full Reimage** | 30 min | ⭐⭐⭐⭐ High | ⚠️ Manual | ⚠️ Manual | Recovery, complete reset |

---

## Protected Data & Config

**These files are NEVER overwritten by updates:**

```
~/.config/aurabridge/output.conf              # Output mode (onboard/usb/auto)
~/.local/bin/librespot                        # Spotify binary
~/.cargo/bin/librespot                        # Rust-built Spotify
~/.config/systemd/user/librespot.service      # User-customized service file
~/.cache/librespot/                           # Spotify OAuth tokens, cache
~/.config/systemd/user/                       # All user systemd configs
/etc/shairport-sync.conf                      # AirPlay config (system)
/boot/firmware/config.txt                     # Pi boot config
~/.bashrc, ~/.zshrc                           # Shell configs
```

---

## Strategy 1: Git Pull (Scripts Only) ⭐ Fastest

**Use when:** Bug fixes in bash scripts, doc updates, diagnostic improvements

**Time:** 2-5 minutes | **Risk:** Very Low | **Compilation:** None

### Steps

```bash
ssh Panda@192.168.50.151

cd ~/AuraBridge-Pi

# 1. Check what changed
git status
git diff

# 2. Backup current state (optional but recommended)
git stash

# 3. Pull new version
git pull origin main

# 4. Verify
ls -la scripts/diagnose.sh
./scripts/preflight-pi.sh

# 5. If something breaks, revert
git revert HEAD      # Undo last commit
# OR
git stash pop        # Restore backed-up state
```

### What Gets Updated
- ✅ Bash scripts (`scripts/*.sh`)
- ✅ Documentation (`docs/*.md`)
- ✅ Configuration templates
- ❌ Compiled binaries (NOT updated)
- ❌ User configs (NOT overwritten)

### Rollback
```bash
git revert HEAD
systemctl --user restart librespot.service  # If needed
```

---

## Strategy 2: Incremental Compile

**Use when:** Single component updated (e.g., new Spotify, new Shairport-sync)

**Time:** 5-15 minutes | **Risk:** Low | **Compilation:** Yes, one service

### Example: Update Spotify Only

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi

# 1. Backup old librespot binary
cp ~/.cargo/bin/librespot ~/.cargo/bin/librespot.backup.$(date +%Y%m%d)

# 2. Re-compile just Spotify
source ~/.cargo/env
cargo install librespot --locked --no-default-features \
  --features pulseaudio-backend,rustls-tls-webpki-roots \
  --force  # Force reinstall even if same version

# 3. Restart service
systemctl --user restart librespot.service
systemctl --user status librespot.service

# 4. Test
journalctl --user -u librespot.service -n 20
```

### Rollback if Broken
```bash
# Restore backup
cp ~/.cargo/bin/librespot.backup.20260605 ~/.cargo/bin/librespot

# Restart
systemctl --user restart librespot.service

# Or: recompile old version from git history
git log --oneline
git checkout <old-commit>
cargo install ...
git checkout main
```

---

## Strategy 3: Full Rebuild

**Use when:** Major code changes, new dependencies, system-wide updates

**Time:** 20-60 minutes | **Risk:** Medium | **Compilation:** Yes, everything

### Pre-Update Backup

```bash
ssh Panda@192.168.50.151

# 1. Create full backup of current state
cd ~
tar -czf aurabridge-backup-$(date +%Y%m%d-%H%M%S).tar.gz \
  .config/aurabridge/ \
  .config/systemd/user/librespot.service \
  .cache/librespot/ \
  AuraBridge-Pi/

# 2. Copy backup to Mac for safekeeping
sshpass -p "040720" scp -o StrictHostKeyChecking=accept-new \
  Panda@192.168.50.151:~/aurabridge-backup-*.tar.gz \
  ~/backups/pi/
```

### Full Rebuild Process

```bash
ssh Panda@192.168.50.151
cd ~/AuraBridge-Pi

# 1. Backup (as above)

# 2. Pull new code
git pull origin main

# 3. Verify critical files still exist
ls -la ~/.config/aurabridge/output.conf  # Should exist
ls -la ~/.config/systemd/user/librespot.service  # Should exist

# 4. Re-run all setup scripts (they are idempotent)
./scripts/setup-base.sh
./scripts/setup-pipewire.sh
./scripts/install-airplay2.sh
./scripts/install-spotify.sh  # Will recompile

# 5. Verify all services
./scripts/diagnose.sh

# 6. Test audio
# Open Spotify, find device, play test track
```

### Rollback Full Rebuild

```bash
# Restore from backup
cd ~
tar -xzf aurabridge-backup-20260605-120000.tar.gz

# Restart services
systemctl --user restart librespot.service
systemctl restart shairport-sync

# Re-run diagnose to verify
./scripts/diagnose.sh
```

---

## Strategy 4: Fresh SD Card (Full Reimage)

**Use when:** Corrupted filesystem, complete reset needed, hardware migration

**Time:** 30 minutes setup + compilation | **Risk:** High | **Data Loss:** Possible

⚠️ **WARNING**: Only use if nothing else works. Data may be lost.

### If You Must Reimage

1. **Backup everything from old Pi**
   ```bash
   # From Mac, backup everything
   sshpass -p "040720" scp -r Panda@192.168.50.151:~ ~/pi-complete-backup/
   ```

2. **Flash new OS** (using Raspberry Pi Imager)

3. **Restore configuration**
   ```bash
   # Copy back only config files (not compiled binaries)
   scp ~/.config/aurabridge/ Panda@<new-ip>:~/
   ```

4. **Run full setup**
   ```bash
   git clone <repo> ~/AuraBridge-Pi
   cd ~/AuraBridge-Pi
   ./scripts/setup-base.sh
   # ... etc
   ```

---

## Data & Config Organization

### Configuration Stays Safe

```
HOME (~/)
├── .config/aurabridge/
│   └── output.conf               ✅ Preserved (you own this)
├── .config/systemd/user/
│   ├── librespot.service         ✅ Preserved (you customized)
│   └── pipewire*.service         ✅ Preserved (user services)
├── .cache/librespot/
│   └── credentials.json          ✅ Preserved (Spotify login)
└── .local/bin/
    └── librespot (symlink)       ✅ Preserved (but points to new binary)

AuraBridge-Pi/ (Project Directory)
├── scripts/                      ⚠️ Overwritten on git pull
├── docs/                         ⚠️ Overwritten on git pull
└── systemd/                      ⚠️ Overwritten on git pull
    (copies go to ~/.config/systemd/user/)
```

### Workflow: Never Lose Config

```
Step 1: All custom config → HOME directory
  ~/.config/aurabridge/output.conf
  ~/.config/systemd/user/librespot.service
  ~/.cache/librespot/

Step 2: Project code → AuraBridge-Pi/ (git-managed)
  Code updates won't touch your configs

Step 3: Updates run
  git pull origin main
  ./scripts/install-spotify.sh

Step 4: Your configs are still intact
  Output mode unchanged ✅
  Spotify OAuth tokens preserved ✅
  Service settings preserved ✅
```

---

## Safe Update Process (Recommended)

### Before Every Update

```bash
ssh Panda@192.168.50.151

# 1. Check current status
cd ~/AuraBridge-Pi
./scripts/diagnose.sh > ~/pre-update-status.txt

# 2. Backup config (safety)
cp ~/.config/aurabridge/output.conf ~/.config/aurabridge/output.conf.backup
cp ~/.config/systemd/user/librespot.service ~/.config/systemd/user/librespot.service.backup

# 3. Note current versions
librespot --version
systemctl --user status librespot.service
```

### During Update

```bash
# 4. Get new code
cd ~/AuraBridge-Pi
git pull origin main

# 5. Review changes
git log --oneline -5
git diff HEAD~1

# 6. Run targeted updates
# Option A: Scripts only (no compile)
git pull
./scripts/diagnose.sh --brief

# Option B: Recompile Spotify
source ~/.cargo/env
cargo install librespot --locked --no-default-features \
  --features pulseaudio-backend,rustls-tls-webpki-roots

# Option C: Full rebuild (if needed)
./scripts/setup-base.sh
./scripts/setup-pipewire.sh
./scripts/install-spotify.sh
```

### After Update

```bash
# 7. Verify everything
./scripts/diagnose.sh

# 8. Test audio
journalctl --user -u librespot.service -n 10
# (Check for errors)

# 9. Test Spotify playback
# Open Spotify, find device, play test track

# 10. Confirm config unchanged
cat ~/.config/aurabridge/output.conf
# Should still show: AURABRIDGE_OUTPUT=onboard (or whatever you set)
```

### If Something Breaks

```bash
# Restore backup configs
cp ~/.config/aurabridge/output.conf.backup ~/.config/aurabridge/output.conf
cp ~/.config/systemd/user/librespot.service.backup ~/.config/systemd/user/librespot.service

# Restart services
systemctl --user restart librespot.service pipewire.service

# Or revert code
git revert HEAD
./scripts/diagnose.sh
```

---

## Backup Strategy

### Daily/Weekly Backups (from Mac)

```bash
#!/bin/bash
# Save as ~/backup-pi.sh

BACKUP_DIR=~/backups/aurabridge/$(date +%Y%m%d)
mkdir -p "$BACKUP_DIR"

# Backup configs
sshpass -p "040720" scp -r Panda@192.168.50.151:~/.config/aurabridge/ "$BACKUP_DIR/"
sshpass -p "040720" scp -r Panda@192.168.50.151:~/.cache/librespot/ "$BACKUP_DIR/"

# Backup diagnostics
sshpass -p "040720" ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/diagnose.sh" \
  > "$BACKUP_DIR/diagnose.txt"

echo "✅ Backup saved to $BACKUP_DIR"
```

### Restore from Backup

```bash
BACKUP_DIR=~/backups/aurabridge/20260605

# Copy configs back
sshpass -p "040720" scp -r "$BACKUP_DIR/.config/aurabridge/" \
  Panda@192.168.50.151:~/.config/

# Restart service
sshpass -p "040720" ssh Panda@192.168.50.151 \
  "systemctl --user restart librespot.service"
```

---

## Version Tracking

### Check Current Versions

```bash
ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && cat <<'EOF'
=== AuraBridge Version Info ===
Project: $(git log -1 --oneline)
Spotify: $(librespot --version)
PipeWire: $(pw-dump | grep -o '"version":"[^"]*' | head -1)
WirePlumber: $(systemctl --user show -p Description wireplumber.service | grep -o '[0-9.]*')
Shairport: $(shairport-sync -V 2>&1 | head -1)
EOF"
```

### Create Version Tag

```bash
cd ~/AuraBridge-Pi
git tag -a v2.2-$(date +%Y%m%d) -m "Version tagged at deployment"
git push origin v2.2-$(date +%Y%m%d)
```

---

## Troubleshooting Updates

### Issue: "Permission denied" during compilation
```bash
# Check permissions
ls -la ~/.cargo/bin/
chmod u+x ~/.cargo/bin/librespot

# Or reinstall
source ~/.cargo/env
cargo install librespot --force
```

### Issue: "Out of disk space"
```bash
# Check disk
df -h /

# Clean up cache
rm -rf ~/.cargo/registry/cache/*
rm -rf /tmp/cargo-install*
```

### Issue: "Compilation fails"
```bash
# Check logs
cargo install librespot 2>&1 | tail -50

# Try with fresh dependencies
rm -rf ~/.cargo/registry/src/*
cargo install librespot --locked
```

### Issue: "Config lost after update"
```bash
# Restore from backup
cp ~/.config/aurabridge/output.conf.backup ~/.config/aurabridge/output.conf

# Verify
cat ~/.config/aurabridge/output.conf
```

---

## Summary: Update Checklist

```
Before Update:
  ☐ Run ./scripts/diagnose.sh
  ☐ Back up configs (optional but recommended)
  ☐ Check disk space (df -h)
  ☐ Note current versions

Update Options:
  ☐ Option A: git pull (2-5 min, scripts only)
  ☐ Option B: Incremental compile (5-15 min, one service)
  ☐ Option C: Full rebuild (20-60 min, everything)
  ☐ Option D: Fresh SD card (only if broken)

After Update:
  ☐ Run ./scripts/diagnose.sh
  ☐ Check output: "All systems nominal"
  ☐ Verify configs still present
  ☐ Test Spotify playback
  ☐ Check for errors in logs

If Problems:
  ☐ Restore config backup
  ☐ Restart services
  ☐ Revert code (git revert HEAD)
  ☐ Or restore full backup
```

---

## FAQ

**Q: Do I need to recompile everything for script changes?**  
A: No. For `.sh` script changes, just `git pull` and you're done.

**Q: Will updates overwrite my Spotify login?**  
A: No. OAuth tokens are in `~/.cache/librespot/` which is never touched.

**Q: Can I safely run updates while Spotify is playing?**  
A: No. Stop the service first: `systemctl --user stop librespot.service`

**Q: How do I know if an update will break things?**  
A: Always check `git log` and `git diff` before pulling.

**Q: What if I want to go back to an older version?**  
A: Run `git log`, find the commit, then `git revert <commit>`

**Q: Can I update while streaming music?**  
A: Not recommended. Stop music first, update, then resume.

---

## Best Practices

1. **Always backup before major updates**
2. **Test on non-critical times** (not during important listening)
3. **Keep config files separate** from code (you already do this)
4. **Version tag releases** for easy rollback
5. **Review changes before pulling** (`git diff`)
6. **Use incremental updates** when possible (faster, lower risk)
7. **Monitor logs after updates** for errors

---

*AuraBridge Pi 2.2 — Safe Update Strategy*  
*Last updated: 2026-06-05*
