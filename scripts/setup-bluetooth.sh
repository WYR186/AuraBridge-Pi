#!/usr/bin/env bash
set -euo pipefail

# setup-bluetooth.sh — Phase 4: enable Bluetooth A2DP *receiving* in a CONTROLLED
# way (BlueZ + PipeWire Bluetooth support), set the adapter alias, and keep the
# adapter NON-discoverable and NON-pairable by default.
#
# Rules (from PROJECT_OVERVIEW_2_2.md sections 13 & 14):
#   - Device name / alias: "Aura Studio 3 BT".
#   - Bluetooth must NOT be permanently discoverable (pairing is a timed window
#     opened separately by bt-pairing-window.sh).
#   - Do NOT write WirePlumber policy here. Routing behaviour must be tested
#     first with bluetooth-routing-spike.sh; any policy is version-specific and
#     needs explicit later approval.
#   - No direct ALSA hw:/plughw: routing. A2DP audio flows through the PipeWire
#     graph (and the Safe Sink later, if implemented).
#
# Idempotent: safe to re-run; it only re-asserts the desired state.

BT_ALIAS="${BT_ALIAS:-Aura Studio 3 BT}"

log()  { printf '[bluetooth] %s\n' "$*"; }
warn() { printf '[bluetooth][WARN] %s\n' "$*" >&2; }
die()  { printf '[bluetooth][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ "$(id -u)" -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi
have apt-get || die "apt-get not found (need Raspberry Pi OS / Debian)."

# --- Install BlueZ + PipeWire Bluetooth support only if needed ---------------
need_install=0
have bluetoothctl || need_install=1
if have dpkg && ! dpkg -s libspa-0.2-bluetooth >/dev/null 2>&1; then
  need_install=1
fi

if [[ "$need_install" -eq 1 ]]; then
  log "Installing BlueZ and PipeWire Bluetooth support (bluez, libspa-0.2-bluetooth)..."
  $SUDO apt-get update
  $SUDO apt-get install -y bluez libspa-0.2-bluetooth
else
  log "BlueZ and PipeWire Bluetooth support already present — skipping install."
fi
have bluetoothctl || die "bluetoothctl still not available after install. Check the bluez package."

# --- Enable the bluetooth service --------------------------------------------
log "Enabling and starting bluetooth.service..."
$SUDO systemctl enable --now bluetooth.service 2>/dev/null \
  || warn "Could not enable/start bluetooth.service via systemd (continuing)."

# Give the controller a moment to appear.
sleep 1

# --- Confirm a controller exists ---------------------------------------------
if ! bluetoothctl show >/dev/null 2>&1 || [[ -z "$(bluetoothctl list 2>/dev/null)" ]]; then
  warn "No Bluetooth controller detected (bluetoothctl show/list is empty)."
  warn "If this Pi has no built-in/attached Bluetooth adapter, Bluetooth A2DP"
  warn "cannot work. Fix the adapter, then re-run. Not changing anything else."
  # Still print versions below; do not hard-fail — this is a setup helper.
fi

# --- Power on, set alias, and LOCK DOWN discoverability ----------------------
# One-shot bluetoothctl commands. Each is best-effort; we never leave the
# adapter discoverable/pairable as a side effect of failure.
bt() { bluetoothctl "$@" 2>/dev/null || warn "bluetoothctl $* failed (continuing)."; }

log "Powering on the controller..."
bt power on

log "Setting Bluetooth alias to '${BT_ALIAS}'..."
bt system-alias "$BT_ALIAS"

log "Forcing discoverable OFF and pairable OFF (default safe state)..."
bt discoverable off
bt pairable off

# --- Report controller status ------------------------------------------------
echo
log "Bluetooth controller status:"
bluetoothctl show 2>/dev/null | sed 's/^/    /' || warn "Could not read controller status."

# --- Report audio stack versions (for the routing spike record) --------------
echo
if have pipewire;    then log "PipeWire:    $(pipewire --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"; else warn "pipewire not found (run ./scripts/setup-pipewire.sh)."; fi
if have wireplumber; then log "WirePlumber: $(wireplumber --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"; else warn "wireplumber not found."; fi

# --- Final guidance ----------------------------------------------------------
echo
log "Bluetooth A2DP receiving is set up, but routing behaviour is NOT yet verified."
log "The adapter is NOT discoverable and NOT pairable right now (by design)."
echo
log "Next steps:"
log "  1. Open a controlled pairing window:   ./scripts/bt-pairing-window.sh"
log "  2. Pair your phone DURING that window only."
log "  3. Run the routing spike to check for AirPlay/Spotify hijack:"
log "       ./scripts/bluetooth-routing-spike.sh"
echo
warn "No WirePlumber policy was written. Do not add Bluetooth routing policy"
warn "until the routing spike shows it is needed AND the version-specific change"
warn "is explicitly approved. See docs/bluetooth-policy.md."
