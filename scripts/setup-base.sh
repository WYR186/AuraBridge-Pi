#!/usr/bin/env bash
set -euo pipefail

# setup-base.sh — Phase 1: install base OS tooling for AuraBridge Pi.
#
# - Idempotent: safe to run repeatedly (apt-get install is a no-op if present).
# - Does NOT reboot.
# - Installs nothing audio-service specific; just build tools and utilities.

log()  { printf '[setup-base] %s\n' "$*"; }
warn() { printf '[setup-base][WARN] %s\n' "$*" >&2; }

# Use sudo only when not already root.
if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

if ! command -v apt-get >/dev/null 2>&1; then
  warn "apt-get not found. This script targets Raspberry Pi OS Lite / Debian."
  exit 1
fi

# Base tools required by later phases (build toolchain, mDNS, USB/ALSA tools).
PACKAGES=(
  git curl wget
  build-essential autoconf automake libtool pkg-config
  jq bc
  alsa-utils
  avahi-daemon
  net-tools iw usbutils
  ca-certificates
)

log "Updating package lists (apt update)..."
if command -v apt >/dev/null 2>&1; then
  $SUDO apt update
else
  $SUDO apt-get update
fi

log "Installing base tools (idempotent):"
log "  ${PACKAGES[*]}"
$SUDO apt-get install -y "${PACKAGES[@]}"

log "Base tools installed successfully."
echo
log "No reboot was performed (by design)."
echo
cat <<'NEXT'
Next manual steps (Phase 1 continues):
  1. ./scripts/setup-pipewire.sh          # install PipeWire + WirePlumber + pipewire-pulse
  2. ./scripts/wireplumber-version-check.sh   # record WirePlumber version & config model
  3. ./scripts/check-ka11.sh               # validate the FiiO KA11 USB DAC (must PASS)
  4. ./scripts/safe-volume.sh              # set safe initial volume (0.01) BEFORE any test

Reminder: keep the Aura Studio 3 physical volume LOW for the first playback test.
The FiiO KA11 is a DAC / headphone amplifier, not a fixed-level line-out.
NEXT
