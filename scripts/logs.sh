#!/usr/bin/env bash
set -euo pipefail

# logs.sh — Phase 1: collect useful diagnostics. Never fails if a service does
# not exist. Read-only. Lines per unit configurable via LOG_LINES (default 100).

LOG_LINES="${LOG_LINES:-100}"

section() { printf '\n========== %s ==========\n' "$*"; }

# System-scope service journal (tolerates missing units).
sys_log() {
  local unit="$1"
  section "system: ${unit} (last ${LOG_LINES})"
  if systemctl cat "$unit" >/dev/null 2>&1; then
    journalctl -u "$unit" -n "$LOG_LINES" --no-pager 2>/dev/null \
      || echo "(could not read journal for ${unit}; try with sudo)"
  else
    echo "(${unit} not installed)"
  fi
}

# User-scope service journal (tolerates missing units / no user session).
user_log() {
  local unit="$1"
  section "user: ${unit} (last ${LOG_LINES})"
  if systemctl --user cat "$unit" >/dev/null 2>&1; then
    journalctl --user -u "$unit" -n "$LOG_LINES" --no-pager 2>/dev/null \
      || echo "(could not read user journal for ${unit})"
  else
    echo "(user unit ${unit} not installed)"
  fi
}

echo "AuraBridge Pi — diagnostic logs ($(date 2>/dev/null || echo 'date n/a'))"

# Phase 2/3 + future-phase system services
sys_log shairport-sync.service
sys_log nqptp.service
sys_log bluetooth.service

# librespot is installed as a USER service in this build; also try system scope.
user_log librespot.service
sys_log  librespot.service

# DLNA renderer (Phase 6) is a USER service, gated + off by default.
user_log gmrender.service

# PipeWire user stack
user_log pipewire.service
user_log pipewire-pulse.service
user_log wireplumber.service

# avahi (mDNS) — system service
sys_log avahi-daemon.service

# Bluetooth (Phase 4) — service journal + current controller state.
sys_log bluetooth.service
section "bluetoothctl show / devices"
if command -v bluetoothctl >/dev/null 2>&1; then
  bluetoothctl show 2>/dev/null || echo "(bluetoothctl show failed)"
  echo "--- paired/known devices ---"
  bluetoothctl devices 2>/dev/null || echo "(bluetoothctl devices failed)"
else
  echo "(bluetoothctl not installed — Phase 4 not set up)"
fi

# Safe Sink (Phase 5) — config presence + verification marker.
section "AuraBridge Safe Sink (Phase 5)"
PW_CONF_DIR="${HOME}/.config/pipewire/pipewire.conf.d"
if ls "$PW_CONF_DIR"/*aurabridge-safe-sink* >/dev/null 2>&1; then
  echo "Safe Sink config files:"
  ls -l "$PW_CONF_DIR"/*aurabridge-safe-sink* 2>/dev/null
else
  echo "(no Safe Sink config in ${PW_CONF_DIR})"
fi
SS_MARKER="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/logs/safe-sink-verified.txt"
if [[ -f "$SS_MARKER" ]]; then
  echo "--- verification marker (${SS_MARKER}) ---"
  cat "$SS_MARKER" 2>/dev/null || true
else
  echo "(no verification marker -> Safe Sink NOT verified -> DLNA blocked)"
fi

# USB-related kernel messages (KA11 enumeration / resets)
section "dmesg | grep -i usb (last 40 matching)"
if dmesg 2>/dev/null | grep -i usb >/dev/null 2>&1; then
  dmesg 2>/dev/null | grep -i usb | tail -n 40 || true
else
  echo "(dmesg not readable without privileges, or no USB lines; try: sudo dmesg | grep -i usb)"
fi

echo
echo "Done."
