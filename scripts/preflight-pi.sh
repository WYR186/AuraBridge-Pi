#!/usr/bin/env bash
set -euo pipefail

# preflight-pi.sh — safe host readiness check before first Raspberry Pi install.
# Read-only except for optional sudo credential validation.

warn_count=0

section() { printf '\n========== %s ==========\n' "$*"; }
ok() { printf '[preflight-pi][OK] %s\n' "$*"; }
warn() { printf '[preflight-pi][WARN] %s\n' "$*" >&2; warn_count=$((warn_count + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

section "OS"
if [[ -r /etc/os-release ]]; then
  cat /etc/os-release
else
  warn "/etc/os-release not readable"
fi

section "Kernel / Architecture"
uname -a || warn "uname failed"
printf 'Architecture: %s\n' "$(uname -m 2>/dev/null || echo unknown)"

section "Raspberry Pi Detection"
pi_model=""
if [[ -r /proc/device-tree/model ]]; then
  pi_model="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
elif [[ -r /sys/firmware/devicetree/base/model ]]; then
  pi_model="$(tr -d '\0' </sys/firmware/devicetree/base/model 2>/dev/null || true)"
fi
if printf '%s' "$pi_model" | grep -qi 'raspberry pi'; then
  ok "Raspberry Pi model detected: $pi_model"
else
  warn "Could not confirm Raspberry Pi hardware. Detected model: ${pi_model:-unknown}"
fi

section "Required Commands"
for cmd in sudo git systemctl apt-get; do
  if have "$cmd"; then
    ok "$cmd found: $(command -v "$cmd")"
  else
    warn "$cmd not found"
  fi
done

section "sudo"
if have sudo; then
  if sudo -v; then
    ok "sudo credentials available"
  else
    warn "sudo validation failed"
  fi
else
  warn "sudo unavailable"
fi

section "systemd"
if have systemctl; then
  if systemctl is-system-running >/dev/null 2>&1; then
    ok "systemd reports running/degraded state"
  else
    state="$(systemctl is-system-running 2>/dev/null || echo unknown)"
    warn "systemd state is: $state"
  fi
else
  warn "systemctl unavailable"
fi

section "Network"
if have hostname; then
  printf 'Hostname: %s\n' "$(hostname 2>/dev/null || echo unknown)"
  hostname -I 2>/dev/null || true
fi
if have ip; then
  ip route 2>/dev/null || warn "could not print route table"
else
  warn "ip command unavailable"
fi
if have ping; then
  if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
    ok "network can reach 1.1.1.1"
  else
    warn "ping to 1.1.1.1 failed"
  fi
else
  warn "ping unavailable"
fi

section "Git Repository"
if have git && git rev-parse --show-toplevel >/dev/null 2>&1; then
  printf 'Repo: %s\n' "$(git rev-parse --show-toplevel)"
  printf 'Branch: %s\n' "$(git branch --show-current 2>/dev/null || echo unknown)"
else
  warn "not inside a git checkout or git unavailable"
fi

section "Safety Reminders"
cat <<'REMINDERS'
- Keep Aura Studio 3 physical volume LOW.
- Do not run setup-safe-sink.sh --apply during first bring-up.
- Do not run install-dlna.sh or start gmrender.service.
- Do not modify WirePlumber policy.
- Do not route services directly to ALSA hw: or plughw: devices.
REMINDERS

section "Result"
if [[ "$warn_count" -eq 0 ]]; then
  ok "Pi preflight passed"
else
  warn "$warn_count warning(s); review before continuing"
fi
