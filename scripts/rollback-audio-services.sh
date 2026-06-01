#!/usr/bin/env bash
set -euo pipefail

# rollback-audio-services.sh — stop/disable AuraBridge audio services safely.
# Does not remove packages and does not delete configs.

log() { printf '[rollback] %s\n' "$*"; }
warn() { printf '[rollback][WARN] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

system_stop_disable() {
  local unit="$1"
  if ! have systemctl; then
    warn "systemctl not found; cannot manage $unit"
    return
  fi
  if systemctl cat "$unit" >/dev/null 2>&1; then
    log "Stopping system service: $unit"
    $SUDO systemctl stop "$unit" 2>/dev/null || warn "could not stop $unit"
    log "Disabling system service: $unit"
    $SUDO systemctl disable "$unit" 2>/dev/null || warn "could not disable $unit"
  else
    log "System service not installed: $unit"
  fi
}

user_stop_disable() {
  local unit="$1"
  if ! have systemctl; then
    warn "systemctl not found; cannot manage user $unit"
    return
  fi
  if systemctl --user cat "$unit" >/dev/null 2>&1; then
    log "Stopping user service/timer: $unit"
    systemctl --user stop "$unit" 2>/dev/null || warn "could not stop user $unit"
    log "Disabling user service/timer: $unit"
    systemctl --user disable "$unit" 2>/dev/null || warn "could not disable user $unit"
  else
    log "User unit not installed: $unit"
  fi
}

cat <<'INTRO'
AuraBridge safe rollback:
- Stops/disables AirPlay, NQPTP, Spotify, and AuraBridge volume guard units.
- Does not remove packages.
- Does not delete configs or user data.
- Does not modify WirePlumber policy.
INTRO

system_stop_disable shairport-sync.service
system_stop_disable nqptp.service

user_stop_disable librespot.service
user_stop_disable aurabridge-volume-guard.timer
user_stop_disable aurabridge-volume-guard.service

if [[ "${STOP_BLUETOOTH:-0}" == "1" ]]; then
  system_stop_disable bluetooth.service
else
  log "Bluetooth left unchanged. To include it: STOP_BLUETOOTH=1 $0"
fi

if have systemctl; then
  systemctl --user daemon-reload 2>/dev/null || true
fi

cat <<'DONE'

Rollback complete.
If audio was too loud, turn the Aura Studio 3 physical volume down now.
To gather diagnostics before changing more state:
  ./scripts/collect-report.sh
DONE
