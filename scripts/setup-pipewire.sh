#!/usr/bin/env bash
set -euo pipefail

# setup-pipewire.sh — Phase 1: install and conservatively enable PipeWire +
# WirePlumber + pipewire-pulse. Prints versions and graph state. Then runs
# safe-volume.sh and check-ka11.sh if possible.
#
# Does NOT modify any WirePlumber policy. (No policy is written in Phase 0-3.)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '[setup-pipewire] %s\n' "$*"; }
warn() { printf '[setup-pipewire][WARN] %s\n' "$*" >&2; }

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
  warn "Running as root. PipeWire normally runs as a USER service; enable it as your"
  warn "normal login user, not root. Continuing with package install only."
else
  SUDO="sudo"
fi

if ! command -v apt-get >/dev/null 2>&1; then
  warn "apt-get not found. This script targets Raspberry Pi OS Lite / Debian."
  exit 1
fi

# PipeWire stack packages available on Debian Bookworm / Raspberry Pi OS Lite.
PACKAGES=(
  pipewire
  wireplumber
  pipewire-pulse
  pipewire-alsa
  pulseaudio-utils   # provides 'pactl'
)

log "Updating package lists..."
$SUDO apt-get update
log "Installing PipeWire stack (idempotent): ${PACKAGES[*]}"
$SUDO apt-get install -y "${PACKAGES[@]}"

# --- Detect whether PipeWire is managed as a user or system service ----------
echo
log "Detecting how PipeWire is managed..."
USER_MODE=0
SYSTEM_MODE=0
if [[ "$(id -u)" -ne 0 ]]; then
  if systemctl --user list-unit-files 2>/dev/null | grep -q '^pipewire\.service'; then
    USER_MODE=1
    log "PipeWire is available as a USER service (systemctl --user)."
  fi
fi
if systemctl list-unit-files 2>/dev/null | grep -q '^pipewire\.service'; then
  # A system-wide pipewire unit also exists on some images, usually NOT used.
  SYSTEM_MODE=1
fi
[[ "$USER_MODE" -eq 0 && "$SYSTEM_MODE" -eq 1 ]] && \
  warn "Only a system pipewire unit was found. The recommended model is the USER service."

# --- Conservatively enable the user services ---------------------------------
if [[ "$USER_MODE" -eq 1 ]]; then
  log "Enabling user services (conservative: enable --now, tolerate failure)..."
  if ! systemctl --user enable --now pipewire pipewire-pulse wireplumber 2>/dev/null; then
    warn "Could not enable/start user services automatically."
    warn "If headless, you may need: loginctl enable-linger \"\$USER\""
    warn "Then: systemctl --user enable --now pipewire pipewire-pulse wireplumber"
  fi
else
  warn "Skipping automatic enable (no user pipewire unit detected in this context)."
  warn "Log in as the normal user and run:"
  warn "  systemctl --user enable --now pipewire pipewire-pulse wireplumber"
fi

# Give the session a brief moment to come up before querying it.
sleep 1

# --- Report versions and graph state -----------------------------------------
echo
echo "===== pipewire --version ====="
command -v pipewire    >/dev/null 2>&1 && pipewire --version    || echo "(pipewire not found)"
echo
echo "===== wireplumber --version ====="
command -v wireplumber >/dev/null 2>&1 && wireplumber --version || echo "(wireplumber not found)"
echo
echo "===== wpctl status ====="
command -v wpctl >/dev/null 2>&1 && { wpctl status || echo "(no reachable PipeWire session)"; } || echo "(wpctl not found)"
echo
echo "===== pactl info ====="
command -v pactl >/dev/null 2>&1 && { pactl info  || echo "(pactl could not reach pipewire-pulse)"; } || echo "(pactl not found)"
echo
echo "===== pactl list sinks short ====="
command -v pactl >/dev/null 2>&1 && { pactl list sinks short || echo "(no sinks / pulse not reachable)"; } || echo "(pactl not found)"

# --- Follow-on Phase 1 helpers (best-effort, never abort this script) --------
echo
if [[ -x "$SCRIPT_DIR/safe-volume.sh" ]]; then
  log "Running safe-volume.sh (initial safe volume)..."
  "$SCRIPT_DIR/safe-volume.sh" || warn "safe-volume.sh reported an issue (continuing)."
else
  warn "safe-volume.sh not found/executable — run it manually after this."
fi

echo
if [[ -x "$SCRIPT_DIR/check-ka11.sh" ]]; then
  log "Running check-ka11.sh (KA11 validation)..."
  "$SCRIPT_DIR/check-ka11.sh" || warn "check-ka11.sh reported WARN/FAIL — review its output above."
else
  warn "check-ka11.sh not found/executable — run it manually after this."
fi

echo
log "PipeWire setup complete. No WirePlumber policy was modified (by design)."
