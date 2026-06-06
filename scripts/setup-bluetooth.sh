#!/usr/bin/env bash
set -euo pipefail

# setup-bluetooth.sh — Phase 4: enable Bluetooth A2DP *receiving* in a CONTROLLED
# way (BlueZ + PipeWire Bluetooth support), set the adapter alias, keep the
# adapter NON-discoverable / NON-pairable by default, AND (new) install a
# version-matched WirePlumber policy that enforces node priority and stops a
# Bluetooth connection from hijacking the active audio route.
#
# Rules (from PROJECT_OVERVIEW_2_2.md sections 13 & 14, and docs/bluetooth-policy.md):
#   - Device name / alias: "Aura Studio 3 BT".
#   - Bluetooth must NOT be permanently discoverable (pairing is a timed window
#     opened separately by bt-pairing-window.sh).
#   - No direct ALSA hw:/plughw: routing. A2DP audio flows through the PipeWire
#     graph and the AuraBridge output (Safe Sink if present, else the selected
#     physical sink).
#
# WirePlumber policy (Directive 2 — anti-hijack):
#   - The installed WirePlumber version is detected FIRST (`wireplumber --version`)
#     and the matching config MODEL is used. A 0.4.x rule does NOT work on 0.5.x
#     and vice versa, so we never blindly copy one onto the other:
#       * 0.4.x   -> Lua  rule in   ~/.config/wireplumber/main.lua.d/
#       * 0.5.x+  -> SPA-JSON in     ~/.config/wireplumber/wireplumber.conf.d/
#   - The policy:
#       1. pins the AuraBridge output sink as the highest-priority session default
#          (node.priority = priority.session = 10000) so a phone connecting over
#          A2DP cannot steal the route from AirPlay / Spotify;
#       2. forces Bluetooth A2DP *source* nodes (media.class=Audio/Source,
#          device.api=bluez5) to target that sink and disables switch-on-connect.
#   - The target node is resolved dynamically (Safe Sink -> selected output via
#     scripts/lib/output-target.sh), never a hardcoded card number. Override with
#     TARGET_NODE=... (alias KA11_NODE_NAME=...).
#
# Run this AS THE NORMAL USER (e.g. Panda), not via sudo: WirePlumber is a user
# service and its config lives under your $HOME. sudo is used only for apt and the
# system bluetooth service.
#
# Modes:
#   (default)          enable the adapter AND install the anti-hijack policy.
#   --no-policy        only enable the adapter (no WirePlumber policy written).
#   --rollback-policy  remove the AuraBridge BT policy and restart WirePlumber.
#   --help
#
# Idempotent: safe to re-run; it only re-asserts the desired state.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/output-target.sh
. "$SCRIPT_DIR/lib/output-target.sh"

BT_ALIAS="${BT_ALIAS:-Aura Studio 3 BT}"
WP_USER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber"
POLICY_LUA="${WP_USER_CONFIG}/main.lua.d/51-aurabridge-bt-policy.lua"
POLICY_CONF="${WP_USER_CONFIG}/wireplumber.conf.d/51-aurabridge-bt-policy.conf"

log()  { printf '[bluetooth] %s\n' "$*"; }
warn() { printf '[bluetooth][WARN] %s\n' "$*" >&2; }
die()  { printf '[bluetooth][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

MODE="setup"
case "${1:-}" in
  ""|setup)          MODE="setup" ;;
  --no-policy)       MODE="no-policy" ;;
  --rollback-policy) MODE="rollback" ;;
  -h|--help)
    grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *) die "Unknown argument '$1'. Use: (no arg) | --no-policy | --rollback-policy | --help" ;;
esac

if [[ "$(id -u)" -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

# Extract the first x.y(.z) token from a --version line.
extract_version() { grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true; }

# Map a WirePlumber version to its config MODEL: lua | spajson | unknown.
wp_model() {
  local ver="$1" major minor rest
  [[ -n "$ver" ]] || { echo unknown; return; }
  major="${ver%%.*}"; rest="${ver#*.}"; minor="${rest%%.*}"
  if [[ "$major" == "0" && "$minor" == "4" ]]; then
    echo lua
  elif [[ "$major" == "0" && "$minor" -ge 5 ]] || [[ "$major" -ge 1 ]]; then
    echo spajson
  else
    echo unknown
  fi
}

# Resolve the node the policy should pin/target: Safe Sink if present, else the
# currently selected physical output. Override with TARGET_NODE / KA11_NODE_NAME.
resolve_target_node() {
  local override="${TARGET_NODE:-${KA11_NODE_NAME:-}}"
  if [[ -n "$override" ]]; then printf '%s' "$override"; return; fi
  if have pactl && pactl list sinks short 2>/dev/null | grep -q 'aurabridge_safe_sink'; then
    printf '%s' 'aurabridge_safe_sink'; return
  fi
  have pactl && detect_output_sink 2>/dev/null || true
}

restart_wireplumber() {
  if systemctl --user restart wireplumber 2>/dev/null; then
    log "Restarted user WirePlumber (systemctl --user restart wireplumber)."
  else
    warn "Could not restart WirePlumber via 'systemctl --user'. Restart it in your"
    warn "user session, or reboot, for the policy to take effect."
  fi
}

# ---------------------------------------------------------------------------
# Policy writers (version-matched). $1 = target node name.
# ---------------------------------------------------------------------------
emit_policy_lua() {
  local node="$1"
  cat <<EOF
-- 51-aurabridge-bt-policy.lua
-- AuraBridge Bluetooth A2DP anti-hijack + node-priority policy.
-- WirePlumber 0.4.x (Lua model). Target AuraBridge output node: "${node}".
-- Generated by scripts/setup-bluetooth.sh. To roll back: delete this file and run
--   systemctl --user restart wireplumber
--   (or: ./scripts/setup-bluetooth.sh --rollback-policy)

-- 1) Pin the AuraBridge output sink as the highest-priority session default so a
--    Bluetooth A2DP connection can never steal the active route from AirPlay or
--    Spotify. Applies to the ALSA-backed sink (onboard AUX or USB DAC).
if alsa_monitor ~= nil then
  alsa_monitor.rules = alsa_monitor.rules or {}
  table.insert(alsa_monitor.rules, {
    matches = {
      { { "node.name", "equals", "${node}" } },
    },
    apply_properties = {
      ["node.priority"]    = 10000,
      ["priority.session"] = 10000,
      ["priority.driver"]  = 10000,
    },
  })
end

-- 2) Force Bluetooth A2DP *source* nodes (phone -> Pi) to render into the
--    AuraBridge output, and forbid switch-on-connect / becoming the default.
if bluez_monitor ~= nil then
  bluez_monitor.rules = bluez_monitor.rules or {}
  table.insert(bluez_monitor.rules, {
    matches = {
      { { "media.class", "equals", "Audio/Source" },
        { "device.api",  "equals", "bluez5" } },
    },
    apply_properties = {
      ["target.node"]         = "${node}",
      ["node.dont-reconnect"] = true,
      ["node.priority"]       = 100,
      ["priority.session"]    = 100,
    },
  })
end
EOF
}

emit_policy_spajson() {
  local node="$1"
  cat <<EOF
# 51-aurabridge-bt-policy.conf
# AuraBridge Bluetooth A2DP anti-hijack + node-priority policy.
# WirePlumber 0.5.x+ (SPA-JSON model). Target AuraBridge output node: "${node}".
# Generated by scripts/setup-bluetooth.sh. To roll back: delete this file and run
#   systemctl --user restart wireplumber
#   (or: ./scripts/setup-bluetooth.sh --rollback-policy)

# 1) Pin the AuraBridge output sink as the highest-priority session default so a
#    Bluetooth A2DP connection can never steal the active route (AirPlay/Spotify).
monitor.alsa.rules = [
  {
    matches = [ { node.name = "${node}" } ]
    actions = {
      update-props = {
        node.priority    = 10000
        priority.session = 10000
        priority.driver  = 10000
      }
    }
  }
]

# 2) Force Bluetooth A2DP source nodes (phone -> Pi) to target that sink and
#    disable switch-on-connect / default promotion.
monitor.bluez.rules = [
  {
    matches = [
      { media.class = "Audio/Source", device.api = "bluez5" }
    ]
    actions = {
      update-props = {
        target.node         = "${node}"
        node.dont-reconnect = true
        node.priority       = 100
        priority.session    = 100
      }
    }
  }
]
EOF
}

apply_policy() {
  if [[ "$(id -u)" -eq 0 ]]; then
    warn "Running as root: WirePlumber policy would be written to root's \$HOME and"
    warn "'systemctl --user' would target root, NOT your audio session. Re-run as the"
    warn "normal user (e.g. Panda) to apply the policy. Skipping policy."
    return 1
  fi

  have wireplumber || { warn "wireplumber not installed; cannot write a matched policy. Run setup-pipewire.sh first."; return 1; }
  local ver model
  ver="$(wireplumber --version 2>/dev/null | extract_version)"
  model="$(wp_model "$ver")"
  log "WirePlumber version: ${ver:-unknown}  ->  config model: ${model}"
  if [[ "$model" == "unknown" ]]; then
    warn "Unrecognized WirePlumber series '${ver}'. Refusing to guess a config model."
    warn "Verify with ./scripts/wireplumber-version-check.sh and apply policy manually."
    return 1
  fi

  local node; node="$(resolve_target_node)"
  if [[ -z "$node" ]]; then
    warn "Could not resolve the AuraBridge output node (Safe Sink / selected sink)."
    warn "Run ./scripts/check-output.sh (and ./scripts/select-output.sh) so a sink is"
    warn "visible, or set TARGET_NODE=<node.name>, then re-run. Skipping policy."
    return 1
  fi
  log "Anti-hijack policy target node: ${node}"

  local ts; ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
  if [[ "$model" == "lua" ]]; then
    mkdir -p "$(dirname "$POLICY_LUA")"
    [[ -f "$POLICY_LUA" ]] && cp -a "$POLICY_LUA" "${POLICY_LUA}.bak.${ts}"
    emit_policy_lua "$node" > "$POLICY_LUA"
    log "Wrote 0.4.x Lua policy: ${POLICY_LUA}"
  else
    mkdir -p "$(dirname "$POLICY_CONF")"
    [[ -f "$POLICY_CONF" ]] && cp -a "$POLICY_CONF" "${POLICY_CONF}.bak.${ts}"
    emit_policy_spajson "$node" > "$POLICY_CONF"
    log "Wrote 0.5.x+ SPA-JSON policy: ${POLICY_CONF}"
  fi

  restart_wireplumber
  sleep 2
  verify_policy "$node"
  return 0
}

verify_policy() {
  local node="$1"
  echo
  if have wpctl; then
    log "wpctl status — confirm '${node}' is the default sink (marked with '*'):"
    wpctl status 2>/dev/null | sed -n '/Audio/,/Video/p' | sed 's/^/    /' || true
  else
    warn "wpctl not available; cannot show the live graph."
  fi
  echo
  warn "Anti-hijack is INSTALLED but not yet PROVEN on hardware. Verify on the Pi:"
  warn "  1. Start AirPlay or Spotify playing to '${node}'."
  warn "  2. Connect your phone over Bluetooth (open a window: bt-pairing-window.sh)."
  warn "  3. Re-run 'wpctl status' — the default sink MUST still be '${node}',"
  warn "     and the phone's A2DP stream should route INTO it, not replace it."
  warn "  (See docs/bluetooth-policy.md and ./scripts/bluetooth-routing-spike.sh.)"
}

rollback_policy() {
  local removed=0 ts; ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
  for f in "$POLICY_LUA" "$POLICY_CONF"; do
    if [[ -f "$f" ]]; then
      mv -f "$f" "${f}.removed.${ts}"
      log "Removed policy -> ${f}.removed.${ts}"
      removed=1
    fi
  done
  if [[ "$removed" -eq 0 ]]; then
    log "No AuraBridge BT policy file found (nothing to roll back)."
  else
    restart_wireplumber
    log "Policy rolled back. Bluetooth now uses WirePlumber's default routing again."
  fi
}

# ---------------------------------------------------------------------------
# Adapter enable (BlueZ + PipeWire Bluetooth support). Unchanged safe behaviour.
# ---------------------------------------------------------------------------
enable_adapter() {
  have apt-get || die "apt-get not found (need Raspberry Pi OS / Debian)."

  local need_install=0
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

  log "Enabling and starting bluetooth.service..."
  $SUDO systemctl enable --now bluetooth.service 2>/dev/null \
    || warn "Could not enable/start bluetooth.service via systemd (continuing)."

  sleep 1

  if ! bluetoothctl show >/dev/null 2>&1 || [[ -z "$(bluetoothctl list 2>/dev/null)" ]]; then
    warn "No Bluetooth controller detected (bluetoothctl show/list is empty)."
    warn "If this Pi has no built-in/attached Bluetooth adapter, Bluetooth A2DP"
    warn "cannot work. Fix the adapter, then re-run."
  fi

  # One-shot bluetoothctl commands; never leave the adapter discoverable/pairable.
  bt() { bluetoothctl "$@" 2>/dev/null || warn "bluetoothctl $* failed (continuing)."; }

  log "Powering on the controller..."
  bt power on
  log "Setting Bluetooth alias to '${BT_ALIAS}'..."
  bt system-alias "$BT_ALIAS"
  log "Forcing discoverable OFF and pairable OFF (default safe state)..."
  bt discoverable off
  bt pairable off

  echo
  log "Bluetooth controller status:"
  bluetoothctl show 2>/dev/null | sed 's/^/    /' || warn "Could not read controller status."
  echo
  if have pipewire;    then log "PipeWire:    $(pipewire --version 2>/dev/null | extract_version)"; else warn "pipewire not found (run ./scripts/setup-pipewire.sh)."; fi
  if have wireplumber; then log "WirePlumber: $(wireplumber --version 2>/dev/null | extract_version)"; else warn "wireplumber not found."; fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ "$MODE" == "rollback" ]]; then
  rollback_policy
  exit 0
fi

enable_adapter
echo

case "$MODE" in
  setup)
    log "Installing the version-matched Bluetooth anti-hijack WirePlumber policy..."
    if apply_policy; then
      echo
      log "Bluetooth A2DP receiving + anti-hijack policy are set up."
    else
      echo
      warn "Adapter is ready, but the WirePlumber policy was NOT applied (see above)."
      warn "Resolve the cause and re-run, or apply manually per docs/bluetooth-policy.md."
    fi
    ;;
  no-policy)
    warn "Adapter enabled WITHOUT a WirePlumber policy (--no-policy)."
    warn "Routing relies on WirePlumber defaults; a phone may hijack the active route."
    warn "Install the policy later with: ./scripts/setup-bluetooth.sh"
    ;;
esac

echo
log "The adapter is NOT discoverable and NOT pairable right now (by design)."
log "Open a controlled pairing window only when needed:  ./scripts/bt-pairing-window.sh"
log "Measure routing behaviour on the Pi:               ./scripts/bluetooth-routing-spike.sh"
