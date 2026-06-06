#!/usr/bin/env bash
set -euo pipefail

# check-safe-sink-gate.sh — strict gate for DLNA / other untrusted clients.
#
# A Safe Sink marker is only valid for the gain that was actually tested. If the
# fixed gain changes, the old marker must not keep DLNA unblocked.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MARKER="$REPO_ROOT/logs/safe-sink-verified.txt"
CONF_PATH="${HOME}/.config/pipewire/pipewire.conf.d/99-aurabridge-safe-sink.conf"

fail() {
  printf 'DLNA is blocked until real-time audio safety is verified.\n' >&2
  printf '[safe-sink-gate][ERROR] %s\n' "$*" >&2
  exit 1
}

marker_value() {
  local key="$1"
  [[ -r "$MARKER" ]] || return 0
  sed -nE "s/^${key}=([^[:space:]]+).*/\\1/p" "$MARKER" 2>/dev/null | tail -n1
}

current_gain() {
  [[ -r "$CONF_PATH" ]] || return 0
  sed -nE 's/.*"mult"[[:space:]]*=[[:space:]]*([0-9]+([.][0-9]+)?).*/\1/p' "$CONF_PATH" 2>/dev/null | head -n1
}

verified="$(marker_value SAFE_SINK_VERIFIED)"
marker_gain="$(marker_value gain)"
active_gain="$(current_gain)"

[[ "$verified" == "yes" ]] || fail "No verified Safe Sink marker at ${MARKER}."
[[ -n "$marker_gain" ]] || fail "Safe Sink marker has no gain= entry."
[[ -n "$active_gain" ]] || fail "Active Safe Sink config has no readable gain at ${CONF_PATH}."
[[ "$marker_gain" == "$active_gain" ]] || fail "Safe Sink gain changed: marker=${marker_gain}, active=${active_gain}. Re-run test-safe-sink.sh before DLNA."

printf '[safe-sink-gate] verified=yes gain=%s\n' "$active_gain"
