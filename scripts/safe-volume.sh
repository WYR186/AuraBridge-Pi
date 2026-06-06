#!/usr/bin/env bash
set -euo pipefail

# safe-volume.sh — Phase 1: apply the SAFE INITIAL volume to the default sink.
#
# IMPORTANT: This is only initial volume setup. It is NOT real-time speaker
# protection. It runs once and does not watch for or block volume spikes.
# See docs/volume-safety.md.

SAFE_VOLUME="${SAFE_VOLUME:-1.00}"

log()  { printf '[safe-volume] %s\n' "$*"; }
warn() { printf '[safe-volume][WARN] %s\n' "$*" >&2; }

if ! command -v wpctl >/dev/null 2>&1; then
  warn "wpctl not found — PipeWire/WirePlumber does not appear to be installed."
  warn "Run ./scripts/setup-pipewire.sh first. Not changing any volume."
  exit 1
fi

log "Setting @DEFAULT_AUDIO_SINK@ volume to ${SAFE_VOLUME} and unmuting..."

if ! wpctl set-volume @DEFAULT_AUDIO_SINK@ "${SAFE_VOLUME}"; then
  warn "Could not set volume. Is a PipeWire session running for this user?"
  warn "Check: systemctl --user status pipewire wireplumber"
  exit 1
fi

wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 || warn "Could not unmute default sink."

log "Done. Default sink volume is now ${SAFE_VOLUME} (unmuted)."
echo
echo "WARNING: This is only initial volume setup. It is not real-time speaker protection."
echo "Keep the Aura Studio 3 physical volume LOW during tests. Raise volume slowly."
