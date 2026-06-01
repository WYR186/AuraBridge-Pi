#!/usr/bin/env bash
set -euo pipefail

# bluetooth-routing-spike.sh — Phase 4: OBSERVE whether a Bluetooth A2DP
# connection hijacks AirPlay / Spotify routing. This script is READ-ONLY with
# respect to the audio graph: it records state and asks the operator to perform
# manual steps. It NEVER writes WirePlumber policy.
#
# If a hijack is observed, it documents the behaviour and proposes a
# version-specific mitigation, but it explicitly requires a separate, explicit
# approval before any WirePlumber policy is written (that is a later step).
#
# See docs/bluetooth-policy.md and docs/wireplumber-versioning.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
LOG="$LOG_DIR/bluetooth-routing-spike-${TS}.txt"

have() { command -v "$1" >/dev/null 2>&1; }

mkdir -p "$LOG_DIR"
: > "$LOG"

# Echo to console AND append to the log file.
out() { printf '%s\n' "$*" | tee -a "$LOG" >/dev/null; printf '%s\n' "$*"; }
hr()  { out "------------------------------------------------------------"; }

# Run a command, capturing label + output into the log and console.
cap() {
  local label="$1"; shift
  out ""
  out ">>> ${label}"
  out "\$ $*"
  if have "${1%% *}" || command -v "$1" >/dev/null 2>&1; then
    { "$@" 2>&1 || echo "(command exited non-zero)"; } | tee -a "$LOG"
  else
    out "(command not available: $1)"
  fi
}

# A full graph snapshot (the 7 required records).
snapshot() {
  local title="$1"
  hr
  out "SNAPSHOT: ${title}  ($(date 2>/dev/null || echo no-date))"
  hr
  if have pipewire;    then cap "pipewire --version"    pipewire --version;    else out "(pipewire not installed)"; fi
  if have wireplumber; then cap "wireplumber --version" wireplumber --version; else out "(wireplumber not installed)"; fi
  if have wpctl;  then cap "wpctl status"            wpctl status;             else out "(wpctl not available)"; fi
  if have pactl;  then cap "pactl list sinks short"  pactl list sinks short;   else out "(pactl not available)"; fi
  if have pactl;  then cap "pactl list sink-inputs"  pactl list sink-inputs;   else out "(pactl not available)"; fi
  if have bluetoothctl; then cap "bluetoothctl show" bluetoothctl show;        else out "(bluetoothctl not available)"; fi
  if have bluetoothctl; then cap "bluetoothctl devices" bluetoothctl devices;  else out "(bluetoothctl not available)"; fi
}

# Prompt for a yes/no/unknown answer (records it). Non-interactive -> 'unknown'.
ask_ynq() {
  local prompt="$1" ans=""
  if [[ -t 0 ]]; then
    read -r -p "    ${prompt} [yes/no/unknown]: " ans || ans=""
  else
    ans=""
  fi
  ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
  case "$ans" in
    y|yes) ans="yes" ;;
    n|no)  ans="no" ;;
    *)     ans="unknown" ;;
  esac
  printf '%s' "$ans"
}

pause() {
  if [[ -t 0 ]]; then
    read -r -p "    >> Press ENTER when done with this step... " _ || true
  else
    out "    (non-interactive: perform this step manually, then re-run for after-state)"
  fi
}

# Detect WirePlumber version for the (proposed, NOT applied) mitigation note.
WP_VER=""
if have wireplumber; then
  WP_VER="$(wireplumber --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"
fi

out "============================================================"
out " AuraBridge Bluetooth routing spike"
out " Log file: ${LOG}"
out "============================================================"
out "This OBSERVES routing only. It changes nothing in the audio graph and"
out "writes NO WirePlumber policy. Keep the Aura Studio 3 physical volume LOW."

# --- Baseline ----------------------------------------------------------------
snapshot "BASELINE (before any Bluetooth connection)"

# --- Guided manual test ------------------------------------------------------
hr
out "MANUAL TEST STEPS"
hr
out "1) Start AirPlay playback to 'Aura Studio 3 AirPlay' and confirm you hear it."
pause
out "2) Connect your already-paired Android phone over Bluetooth (A2DP)."
pause
snapshot "AFTER Bluetooth connect (AirPlay was playing)"
out "3) Did the Bluetooth connection INTERRUPT or take over AirPlay audio?"
HIJACK_AIRPLAY="$(ask_ynq "AirPlay hijacked by Bluetooth?")"
out "    -> recorded: AirPlay hijacked = ${HIJACK_AIRPLAY}"

out "4) Stop Bluetooth playback / disconnect the phone."
pause
out "5) Start Spotify playback to 'Aura Studio 3 Spotify' and confirm you hear it."
pause
out "6) Connect Bluetooth again."
pause
snapshot "AFTER Bluetooth connect (Spotify was playing)"
out "7) Did the Bluetooth connection INTERRUPT or take over Spotify audio?"
HIJACK_SPOTIFY="$(ask_ynq "Spotify hijacked by Bluetooth?")"
out "    -> recorded: Spotify hijacked = ${HIJACK_SPOTIFY}"

# --- Verdict -----------------------------------------------------------------
hr
out "RESULT"
hr
out "AirPlay hijacked by Bluetooth : ${HIJACK_AIRPLAY}"
out "Spotify hijacked by Bluetooth : ${HIJACK_SPOTIFY}"
out "WirePlumber version           : ${WP_VER:-unknown}"

if [[ "$HIJACK_AIRPLAY" == "yes" || "$HIJACK_SPOTIFY" == "yes" || "$HIJACK_AIRPLAY" == "unknown" || "$HIJACK_SPOTIFY" == "unknown" ]]; then
  out ""
  out "HIJACK or UNCERTAIN behaviour recorded. NO POLICY HAS BEEN WRITTEN."
  out ""
  out "Proposed mitigation (NOT applied — requires explicit later approval):"
  if [[ "$WP_VER" == 0.4.* ]]; then
    out "  - WirePlumber ${WP_VER} is the 0.4.x series -> use LUA-style policy."
    out "    Disable automatic switch-on-connect for the bluez_output node, e.g. a"
    out "    0.4 Lua rule that sets node.dont-reconnect / suspends auto-routing."
  elif [[ -n "$WP_VER" ]]; then
    out "  - WirePlumber ${WP_VER} is 0.5.x+ -> use SPA-JSON (.conf) policy."
    out "    Add a wireplumber.conf.d fragment that disables 'switch on connect'"
    out "    for the Bluetooth node (e.g. via node.features.audio.no-dsp / a"
    out "    device.routes rule), version-matched to your install."
  else
    out "  - WirePlumber version unknown -> run ./scripts/wireplumber-version-check.sh"
    out "    first and choose 0.4 Lua vs 0.5+ SPA-JSON syntax accordingly."
  fi
  out ""
  out "  GATE: Do NOT write this policy yet. It must be version-matched and"
  out "        explicitly approved. As an MVP fallback, Bluetooth can stay"
  out "        DISABLED by default (stop bluetooth.service) so AirPlay/Spotify"
  out "        remain the reliable paths. See docs/bluetooth-policy.md."
else
  out ""
  out "No hijack observed. Default WirePlumber policy appears acceptable for now."
  out "Re-test after OS / WirePlumber updates."
fi

out ""
out "Full record saved to: ${LOG}"
