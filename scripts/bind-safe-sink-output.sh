#!/usr/bin/env bash
set -uo pipefail

# bind-safe-sink-output.sh — keep the AuraBridge Safe Sink's OUTPUT on the
# selected physical output (e.g. the FiiO KA11 USB DAC) instead of the Pi onboard
# 3.5mm jack.
#
# WHY THIS EXISTS (the "AirPlay connects but no sound" bug):
# The Safe Sink filter-chain's playback side is a PASSIVE node with
# target.object = the KA11. In WirePlumber 0.4 that target is NOT reliably
# honored: the passive output parks on the highest-priority physical sink, which
# is the Pi onboard 3.5mm jack, so audio goes there and the speaker (on the KA11)
# is silent. A one-shot move at boot does not hold because the node drifts back to
# onboard while idle. See docs/field-note-2026-06-06-reboot-no-sound.md.
#
# Modes:
#   --watch   (used by aurabridge-safe-sink-refresh.service) do an initial bind,
#             then watch and re-assert the binding WHENEVER the Safe Sink is
#             actually playing. It does nothing while idle, so it never fights
#             WirePlumber's idle parking (no churn) — it only guarantees that
#             when audio flows, it flows to the KA11.
#   --once    bind once now and exit (manual use). Falls back to
#             refresh-safe-sink.sh if the Safe Sink itself is missing.

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

# Numeric id of the selected physical output sink (KA11 by name), or empty.
target_sink_id() {
  local name; name="$(detect_output_sink 2>/dev/null || true)"
  [[ -z "$name" ]] && return 1
  pactl list sinks short 2>/dev/null | awk -v n="$name" '$2==n{print $1; exit}'
}

# sink-input id of the Safe Sink's playback stream ("<safe>.output"), or empty.
safe_out_id() {
  pactl list sink-inputs 2>/dev/null \
    | awk -v want="${SINK_NODE_NAME}.output" \
        '/^Sink Input #/{id=$3; sub(/#/,"",id)} index($0,want){print id; exit}'
}

# Numeric sink id the Safe Sink output is currently routed to, or empty.
safe_out_sink() {
  pactl list sink-inputs 2>/dev/null \
    | awk -v want="${SINK_NODE_NAME}.output" \
        '/^Sink Input #/{s=""} /^[[:space:]]*Sink:/{s=$2} index($0,want){print s; exit}'
}

# True if the Safe Sink itself is actively playing (audio is flowing).
safe_sink_running() {
  local st
  st="$(pactl list sinks short 2>/dev/null | awk -v n="$SINK_NODE_NAME" '$2==n{print $NF; exit}')"
  [[ "$st" == "RUNNING" ]]
}

# Ensure the Safe Sink output is on the target (KA11). Idempotent: only moves
# when it is not already there, so there is nothing to churn.
ensure_bound() {
  local tid soid cur
  tid="$(target_sink_id)" || return 1
  [[ -z "$tid" ]] && return 1
  soid="$(safe_out_id)"; [[ -z "$soid" ]] && return 1
  pactl set-default-sink "$SINK_NODE_NAME" >/dev/null 2>&1 || true
  pactl set-sink-mute "$tid" 0 >/dev/null 2>&1 || true
  cur="$(safe_out_sink)"
  if [[ "$cur" != "$tid" ]]; then
    if pactl move-sink-input "$soid" "$tid" >/dev/null 2>&1; then
      log "Safe Sink output (#${soid}) re-bound: sink ${cur:-?} -> ${tid} (selected DAC)."
    fi
  fi
  return 0
}

wait_for_target() {
  local i
  for ((i = 0; i <= WAIT_SECS; i++)); do
    [[ -n "$(target_sink_id 2>/dev/null || true)" ]] && return 0
    (( i == WAIT_SECS )) && return 1
    sleep 1
  done
  return 1
}

run_once() {
  if ! wait_for_target; then
    warn "Selected output sink did not appear within ${WAIT_SECS}s; leaving routing as-is."
    exit 0
  fi
  if ! ensure_bound; then
    warn "Safe Sink output not found; falling back to refresh-safe-sink.sh."
    [[ -x "$SCRIPT_DIR/refresh-safe-sink.sh" ]] && exec "$SCRIPT_DIR/refresh-safe-sink.sh"
  fi
  exit 0
}

run_watch() {
  wait_for_target || warn "Selected output sink not present yet; will bind when it appears."
  ensure_bound || true
  log "Watching: will keep the Safe Sink output on the selected DAC whenever audio plays."
  # Re-assert only while the Safe Sink is actually playing -> no idle churn.
  local ev
  pactl subscribe 2>/dev/null | while read -r ev; do
    case "$ev" in
      *sink*) safe_sink_running && ensure_bound || true ;;
    esac
  done
  warn "pactl subscribe ended; exiting for restart."
  exit 1
}

case "${1:-}" in
  --watch) run_watch ;;
  ""|--once) run_once ;;
  *) printf 'usage: %s [--watch|--once]\n' "$(basename "$0")" >&2; exit 2 ;;
esac
