#!/usr/bin/env bash
set -euo pipefail

# bt-pairing-window.sh — Phase 4: open a SHORT, controlled Bluetooth pairing
# window, then force the adapter back to NON-discoverable / NON-pairable.
#
# The adapter must NEVER be left permanently discoverable. A trap guarantees the
# window is closed even if the script is interrupted (Ctrl-C) or errors out.
#
# Window length (seconds), in priority order:
#   1. CLI argument:        ./scripts/bt-pairing-window.sh 60
#   2. Env var:             BT_PAIRING_SECONDS=60 ./scripts/bt-pairing-window.sh
#   3. Default:             120
#
# See docs/bluetooth-policy.md.

DEFAULT_SECONDS=120
WINDOW="${1:-${BT_PAIRING_SECONDS:-$DEFAULT_SECONDS}}"

log()  { printf '[bt-pairing] %s\n' "$*"; }
warn() { printf '[bt-pairing][WARN] %s\n' "$*" >&2; }
die()  { printf '[bt-pairing][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

have bluetoothctl || die "bluetoothctl not found. Run ./scripts/setup-bluetooth.sh first."

# Validate the window is a positive integer.
if ! [[ "$WINDOW" =~ ^[0-9]+$ ]] || [[ "$WINDOW" -le 0 ]]; then
  die "Invalid pairing window '${WINDOW}'. Use a positive integer number of seconds."
fi

bt() { bluetoothctl "$@" 2>/dev/null || warn "bluetoothctl $* failed (continuing)."; }

show_state() {
  bluetoothctl show 2>/dev/null \
    | grep -iE 'Name|Alias|Powered|Discoverable|Pairable' \
    | sed 's/^/    /' \
    || warn "Could not read controller state."
}

# --- Cleanup runs exactly once, on any exit path -----------------------------
AGENT_PID=""
_cleanup_done=0
cleanup() {
  [[ "$_cleanup_done" -eq 1 ]] && return 0
  _cleanup_done=1
  echo
  log "Closing pairing window: forcing discoverable OFF and pairable OFF..."
  bluetoothctl discoverable off >/dev/null 2>&1 || true
  bluetoothctl pairable off     >/dev/null 2>&1 || true
  if [[ -n "$AGENT_PID" ]] && kill -0 "$AGENT_PID" 2>/dev/null; then
    kill "$AGENT_PID" 2>/dev/null || true
  fi
  log "Pairing window closed. Final state:"
  show_state
}
trap cleanup INT TERM EXIT

# --- Confirm a controller exists ---------------------------------------------
if ! bluetoothctl show >/dev/null 2>&1 || [[ -z "$(bluetoothctl list 2>/dev/null)" ]]; then
  die "No Bluetooth controller detected. Run ./scripts/setup-bluetooth.sh and check the adapter."
fi

echo
log "State BEFORE opening the window:"
show_state

# --- Optional headless auto-accept agent (best-effort) -----------------------
# A 'just works' agent lets a phone pair without a console prompt. Only used if
# bt-agent (bluez-tools) is installed; otherwise pairing may need manual accept.
if have bt-agent; then
  log "Starting a NoInputNoOutput pairing agent (bt-agent) for this window..."
  bt-agent --capability=NoInputNoOutput >/dev/null 2>&1 &
  AGENT_PID=$!
else
  warn "bt-agent not installed — relying on the default BlueZ agent."
  warn "If pairing is rejected, run 'bluetoothctl' interactively: agent on; default-agent."
fi

# --- Open the window ---------------------------------------------------------
log "Opening pairing window for ${WINDOW}s..."
bt power on
bt pairable on
bt discoverable on

echo
log "Adapter is now DISCOVERABLE and PAIRABLE for ${WINDOW}s."
log "On your phone: open Bluetooth settings and pair with the adapter alias"
log "(default 'Aura Studio 3 BT'). Keep the Aura Studio 3 physical volume LOW."
echo

# Count down without spamming; tolerate Ctrl-C (trap closes the window).
remaining="$WINDOW"
while [[ "$remaining" -gt 0 ]]; do
  step=$(( remaining > 10 ? 10 : remaining ))
  sleep "$step"
  remaining=$(( remaining - step ))
  [[ "$remaining" -gt 0 ]] && log "  ${remaining}s remaining..."
done

# Normal end -> EXIT trap closes the window and prints the final state.
log "Window elapsed."
