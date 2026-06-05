# AuraBridge Pi 2.2 — Quick Reference Card

## 🚀 One-Liners

### Check Status (from Mac)
```bash
sshpass -p "040720" ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/diagnose.sh"
```

### Quick Check Only
```bash
sshpass -p "040720" ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/diagnose.sh --brief"
```

### Full Diagnostic
```bash
sshpass -p "040720" ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/diagnose.sh --full"
```

---

## 📋 Common Tasks

### Restart Spotify
```bash
ssh Panda@192.168.50.151 "systemctl --user restart librespot.service"
```

### Check Spotify Logs
```bash
ssh Panda@192.168.50.151 "journalctl --user -u librespot.service -n 20"
```

### See Current Output Config
```bash
ssh Panda@192.168.50.151 "cat ~/.config/aurabridge/output.conf"
```

### Switch to USB DAC (when it arrives)
```bash
ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/select-output.sh usb"
```

### Switch to Onboard Audio
```bash
ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/select-output.sh onboard"
```

### Auto Mode (detect & switch)
```bash
ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/select-output.sh auto"
```

---

## 🔗 Connection Info

| Item | Value |
|------|-------|
| **Host** | `192.168.50.151` or `raspberrypanda.local` |
| **Username** | `Panda` |
| **Password** | `040720` |
| **Project** | `~/AuraBridge-Pi` |

---

## 📊 Status Meanings

| Status | Meaning |
|--------|---------|
| ✅ All systems nominal (8/8) | Ready for playback! |
| ℹ️ Most systems operational (7/8) | Working, check warnings |
| ⚠️ Partial functionality | Some services missing |
| ❌ Critical issues | Needs immediate fix |

---

## 🎵 Testing Checklist

- [ ] Open Spotify app
- [ ] Find "AuraStudio3Spotify" device
- [ ] Click to connect
- [ ] Select a song
- [ ] Press play
- [ ] Listen for audio on Aura Studio 3
- [ ] Check volume is safe

---

## 🔧 Troubleshooting

### Spotify device not appearing
```bash
ssh Panda@192.168.50.151 "systemctl --user restart librespot.service && sleep 2 && systemctl --user status librespot.service"
```

### No sound
```bash
ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/check-output.sh"
```

### System issues
```bash
ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/diagnose.sh --full"
```

---

## 📁 Key Files

| File | Purpose |
|------|---------|
| `scripts/diagnose.sh` | System status check |
| `scripts/select-output.sh` | Switch outputs |
| `docs/DIAGNOSE_GUIDE.md` | Diagnostic guide |
| `docs/DEPLOYMENT_STATUS.md` | Current setup status |
| `~/.config/aurabridge/output.conf` | Output config (on Pi) |

---

## 🌐 Aliases for Your Mac (Optional)

Add these to `~/.zshrc` or `~/.bash_profile`:

```bash
# AuraBridge shortcuts
alias pi-status="sshpass -p '040720' ssh Panda@192.168.50.151 'cd ~/AuraBridge-Pi && ./scripts/diagnose.sh'"
alias pi-brief="sshpass -p '040720' ssh Panda@192.168.50.151 'cd ~/AuraBridge-Pi && ./scripts/diagnose.sh --brief'"
alias pi-full="sshpass -p '040720' ssh Panda@192.168.50.151 'cd ~/AuraBridge-Pi && ./scripts/diagnose.sh --full'"
alias pi-restart-spotify="ssh Panda@192.168.50.151 'systemctl --user restart librespot.service'"
alias pi-logs="ssh Panda@192.168.50.151 'journalctl --user -u librespot.service -n 20'"
```

Then reload:
```bash
source ~/.zshrc
```

Now you can just run:
```bash
pi-status
pi-brief
pi-full
pi-restart-spotify
pi-logs
```

---

## 🔌 USB DAC Detection (小尾巴)

### Check What's Connected
```bash
sshpass -p "040720" ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/diagnose.sh" | grep -A5 "USB Audio"
```

### Supported DACs
- ✅ FiiO KA11 (2204:0003) — Planned target
- ✅ FiiO KA13 (2204:0004)
- ✅ Meizu HiFi DAC (2a45:0126) — Currently in test setup
- ✅ Other USB audio devices (with detection)

### When FiiO KA11 Arrives
```bash
# 1. Plug in the KA11
# 2. Verify it's detected
sshpass -p "040720" ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/diagnose.sh | grep -i fiio"

# 3. Switch to USB output
sshpass -p "040720" ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/select-output.sh usb"

# 4. Verify
sshpass -p "040720" ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/check-output.sh | grep -i fiio"
```

---

## 📝 Pi Credentials

**Keep these secure!**

```
Host:     192.168.50.151
Username: Panda
Password: 040720
SSH Key:  None (password auth)
```

See `docs/RASPBERRY_PI_CREDENTIALS.md` for full details.

---

## 🎯 When FiiO KA11 Arrives

1. Connect USB-A → Type-C adapter to Pi
2. Run: `ssh Panda@192.168.50.151 "cd ~/AuraBridge-Pi && ./scripts/select-output.sh usb"`
3. Run: `pi-status` to verify
4. Spotify will automatically use USB DAC

That's it! No other changes needed.

---

## 💡 Pro Tips

- **Bookmark this file** — Save to Desktop or Docs
- **Use aliases** — Add to your shell profile for 1-keystroke access
- **Run diagnose regularly** — Catch issues early
- **Check --full before troubleshooting** — Always get complete info
- **Monitor from Mac** — No need to SSH into Pi every time

---

*AuraBridge Pi 2.2 — Setup complete, ready for testing!*
