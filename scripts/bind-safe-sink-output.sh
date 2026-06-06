#!/usr/bin/env bash
set -uo pipefail

# bind-safe-sink-output.sh — make the AuraBridge Safe Sink's OUTPUT land on the
# selected physical output (e.g. the FiiO KA11 USB DAC) instead of the Pi onboard
# 3.5mm jack.
#
# WHY THIS EXISTS (the "AirPlay connects but no sound after reboot" bug):
# A USB DAC enumerates a few seconds AFTER the user PipeWire graph starts. The
# Safe Sink filter-chain (target.object = the KA11) therefore loads before the
# KA11 exists, so PipeWire binds its playback side to whatever sink is available
# (the onboard bcm2835 jack). It never moves to the KA11 when it appears, so
# audio goes to the Pi's headphone jack — the speaker is silent even though
# AirPlay "connected". See docs/field-note-2026-06-06-reboot-no-sound.md.
#
# This is the LIGHT fix: wait for the selected sink, then MOVE the Safe Sink
# output sink-input onto it (idempotent, no PipeWire restart). If the Safe Sink
# itself is missing, fall back to the heavier refresh-safe-sink.sh (full reapply).
# Runs at boot via aurabridge-safe-sink-refresh.service (user).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/output-target.sh
. "$SCRIPT_DIR/lib/output-target.sh"

SINK_NODE_NAME="aurabridge_safe_sink"
WAIT_SECS="${AURABRIDGE_SAFE_SINK_WAIT_SECS:-45}"

log()  { printf '[safe-sink-bind] %s\n' "$*"; }
warn() { printf '[safe-sink-bind][WARN] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# When run outside a user systemd service (e.g. by hand over SSH), make sure we
# can reach the user PipeWire/PulseAudio session.
if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
  XDG_RUNTIME_DIR="/run/user/$(id -u)"
  export XDG_RUNTIME_DIR
fi

have pactl || { warn "pactl not available; cannot rebind."; exit 0; }

# Wait for the selected physical output sink (KA11 by name) to appear.
target_name=""
for ((i = 0; i <= WAIT_SECS; i++)); do
  target_name="$(detect_output_sink 2>/dev/null || true)"
  [[ -n "$target_name" ]] && break
  (( i == WAIT_SECS )) && break
  sleep 1
done

if [[ -z "$target_name" ]]; then
  warn "Selected output sink did not appear within ${WAIT_SECS}s; leaving routing as-is."
  exit 0
fi
log "Selected output sink present: ${target_name}"

# Numeric id of the target sink.
target_id="$(pactl list sinks short 2>/dev/null | awk -v n="$target_name" '$2==n{print $1; exit}')"
if [[ -z "$target_id" ]]; then
  warn "Could not resolve numeric id for ${target_name}; leaving routing as-is."
  exit 0
fi

# The Safe Sink's playback stream ("<safe>.output"). If it is missing the Safe
# Sink filter-chain is not loaded — fall back to the full reapply.
safe_out_id="$(pactl list sink-inputs 2>/dev/null \
  | awk -v want="${SINK_NODE_NAME}.output" \
      '/Sink Input #/{id=$3; sub(/#/,"",id)} index($0,want){print id; exit}')"

if [[ -z "$safe_out_id" ]]; then
  warn "Safe Sink output stream not found. Falling back to refresh-safe-sink.sh."
  if [[ -x "$SCRIPT_DIR/refresh-safe-sink.sh" ]]; then
    exec "$SCRIPT_DIR/refresh-safe-sink.sh"
  fi
  exit 0
fi

# Make the Safe Sink the default sink, route its output to the target, unmute it.
# All idempotent — safe to run repeatedly / every boot.
pactl set-default-sink "$SINK_NODE_NAME" >/dev/null 2>&1 || true
pactl set-sink-mute "$target_id" 0 >/dev/null 2>&1 || true
if pactl move-sink-input "$safe_out_id" "$target_id" >/dev/null 2>&1; then
  log "Safe Sink output (#${safe_out_id}) -> ${target_name} (#${target_id})."
else
  warn "move-sink-input failed (already there?). Current routing:"
fi

# Report final routing for the journal.
pactl list sink-inputs 2>/dev/null \
  | awk '/Sink Input #/{h=$0} index($0,"'"${SINK_NODE_NAME}"'.output"){print h; found=1} /Sink:/{if(found){print "  "$0; found=0}}' \
  | sed 's/^/[safe-sink-bind] /' || true
exit 0
