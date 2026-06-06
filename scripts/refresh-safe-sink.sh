#!/usr/bin/env bash
set -euo pipefail

# refresh-safe-sink.sh — make the PipeWire Safe Sink follow the selected
# physical output after boot.
#
# Why this exists:
# USB DACs can appear a few seconds after the user PipeWire graph starts. If the
# Safe Sink filter-chain loads before the selected downstream sink exists,
# PipeWire may autoconnect its playback side to another sink (usually the Pi
# onboard AUX). This script waits for the selected sink and reapplies the Safe
# Sink so audio lands on the intended output.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/output-target.sh
. "$SCRIPT_DIR/lib/output-target.sh"

PW_CONF_DIR="${HOME}/.config/pipewire/pipewire.conf.d"
CONF_PATH="${PW_CONF_DIR}/99-aurabridge-safe-sink.conf"
SS_MARKER="$(cd "$SCRIPT_DIR/.." && pwd)/logs/safe-sink-verified.txt"
SINK_NODE_NAME="aurabridge_safe_sink"
WAIT_SECS="${AURABRIDGE_SAFE_SINK_WAIT_SECS:-45}"

log()  { printf '[safe-sink-refresh] %s\n' "$*"; }
warn() { printf '[safe-sink-refresh][WARN] %s\n' "$*" >&2; }
die()  { printf '[safe-sink-refresh][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ ! -f "$CONF_PATH" ]]; then
  log "No active Safe Sink config found at ${CONF_PATH}; nothing to refresh."
  exit 0
fi

have pactl || die "pactl is not available; cannot detect the selected output sink."

log "Configured output: $(output_configured_target); effective target: $(output_effective_target) — $(describe_output_target)"

target=""
for ((i = 0; i <= WAIT_SECS; i++)); do
  target="$(detect_output_sink 2>/dev/null || true)"
  if [[ -n "$target" ]]; then
    break
  fi
  if (( i == WAIT_SECS )); then
    break
  fi
  log "Waiting for selected PipeWire sink to appear (${i}/${WAIT_SECS})..."
  sleep 1
done

[[ -n "$target" ]] || die "Selected output sink did not appear within ${WAIT_SECS}s."

log "Selected sink is present: ${target}"
log "Reapplying Safe Sink so '${SINK_NODE_NAME}' targets the selected output."

if [[ -z "${SAFE_SINK_GAIN:-}" && -r "$SS_MARKER" ]] && grep -q '^SAFE_SINK_VERIFIED=yes' "$SS_MARKER"; then
  marker_gain="$(sed -nE 's/^gain=([0-9]+([.][0-9]+)?).*/\1/p' "$SS_MARKER" 2>/dev/null | tail -n1)"
  if [[ -n "$marker_gain" ]]; then
    export SAFE_SINK_GAIN="$marker_gain"
    log "Using verified Safe Sink gain from marker: ${SAFE_SINK_GAIN}"
  fi
fi

AURABRIDGE_SAFE_SINK_SKIP_ENABLE=1 ASSUME_YES=1 "$SCRIPT_DIR/setup-safe-sink.sh" --apply

if pactl list sinks short 2>/dev/null | grep -q "$SINK_NODE_NAME"; then
  log "Safe Sink is present after refresh."
else
  die "Safe Sink is still missing after refresh."
fi
