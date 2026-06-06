#!/usr/bin/env bash
set -euo pipefail

# test-safe-sink.sh — Phase 5: verify the AuraBridge Safe Sink on real hardware.
#
# This is the ONLY thing that may mark the Safe Sink "verified". Verification
# requires a HUMAN to confirm, with the Aura Studio 3 physical volume LOW, that a
# 100% client-side volume does NOT produce dangerous analog output. The result
# is written to logs/safe-sink-verified.txt, which install-dlna.sh checks before
# it will do anything. See docs/safe-sink.md and docs/volume-safety.md.
#
# Exit code: 0 = VERIFIED, 1 = NOT VERIFIED (the safe default).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$REPO_ROOT/logs"
MARKER="$LOG_DIR/safe-sink-verified.txt"
SINK_NODE_NAME="aurabridge_safe_sink"
SAFE_SINK_GAIN="${SAFE_SINK_GAIN:-1.30}"
TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
TESTLOG="$LOG_DIR/safe-sink-test-${TS}.txt"

have() { command -v "$1" >/dev/null 2>&1; }
mkdir -p "$LOG_DIR"
: > "$TESTLOG"

out() { printf '%s\n' "$*" | tee -a "$TESTLOG" >/dev/null; printf '%s\n' "$*"; }
hr()  { out "------------------------------------------------------------"; }

ask_ynq() {
  local prompt="$1" ans=""
  if [[ -t 0 ]]; then read -r -p "    ${prompt} [yes/no/unknown]: " ans || ans=""; fi
  ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
  case "$ans" in y|yes) echo yes ;; n|no) echo no ;; *) echo unknown ;; esac
}

write_marker() {
  local verified="$1" through="$2" danger="$3" default_sink="$4" ka11="$5"
  {
    echo "# AuraBridge Safe Sink verification marker — written by test-safe-sink.sh"
    echo "# install-dlna.sh refuses to proceed unless SAFE_SINK_VERIFIED=yes."
    echo "SAFE_SINK_VERIFIED=${verified}"
    echo "timestamp=${TS}"
    echo "safe_sink=${SINK_NODE_NAME}"
    echo "default_sink=${default_sink}"
    echo "ka11_sink=${ka11}"
    echo "gain=${SAFE_SINK_GAIN}"
    echo "audio_through_controlled_path=${through}"
    echo "dangerous_at_100pct=${danger}"
    echo "test_log=${TESTLOG}"
  } > "$MARKER"
}

# Play a short, quiet test sound to the default sink (which should be the Safe
# Sink). Best-effort; if no player/sample, ask the operator to play manually.
play_test() {
  local wav="/usr/share/sounds/alsa/Front_Center.wav"
  if have pw-play && [[ -f "$wav" ]]; then
    out "    (playing ${wav} via pw-play to the default sink)"
    pw-play "$wav" 2>>"$TESTLOG" || out "    (pw-play failed; play something manually)"
  elif have paplay && [[ -f "$wav" ]]; then
    out "    (playing ${wav} via paplay to ${SINK_NODE_NAME})"
    paplay --device="$SINK_NODE_NAME" "$wav" 2>>"$TESTLOG" || out "    (paplay failed; play something manually)"
  else
    out "    (no test sample/player found — play a short track from your phone now)"
    [[ -t 0 ]] && read -r -p "    >> Press ENTER once you have played a short test... " _ || true
  fi
}

KA11_HINTS='fiio|ka11|usb audio|usb-audio|\bdac\b|headphone|usb dac'
detect_ka11_sink() {
  have pactl || return 0
  pactl list sinks short 2>/dev/null | grep -iE "$KA11_HINTS" \
    | grep -ivE 'aurabridge|safe.?sink' | awk '{print $2}' | head -n1
}

out "============================================================"
out " AuraBridge Safe Sink verification"
out " Log: ${TESTLOG}"
out "============================================================"
out "SAFETY: the KA11 is a headphone amplifier. This test deliberately raises the"
out "Safe Sink to 100% to check the hard cap. Keep the Aura Studio 3 PHYSICAL"
out "volume LOW so a failed cap cannot blast the speaker."
echo

have pactl || { out "RESULT: NOT VERIFIED — pactl unavailable (no PipeWire session)."; write_marker no unknown unknown unknown unknown; exit 1; }

if [[ -t 0 ]]; then
  read -r -p "Is the Aura Studio 3 PHYSICAL volume turned DOWN low? [yes/no]: " low || low=""
  if [[ ! "$(printf '%s' "$low" | tr '[:upper:]' '[:lower:]')" =~ ^y(es)?$ ]]; then
    out "RESULT: NOT VERIFIED — operator did not confirm low physical volume. Aborting safely."
    write_marker no unknown unknown unknown unknown
    exit 1
  fi
fi

# --- 1. Safe Sink present? ---------------------------------------------------
hr; out "1) Safe Sink presence"
DEFAULT_SINK="$(pactl get-default-sink 2>/dev/null || echo unknown)"
KA11_SINK="$(detect_ka11_sink)"
out "    default sink : ${DEFAULT_SINK}"
out "    KA11 sink    : ${KA11_SINK:-not detected}"

if ! pactl list sinks short 2>/dev/null | grep -q "$SINK_NODE_NAME"; then
  out "RESULT: NOT VERIFIED — Safe Sink '${SINK_NODE_NAME}' not found."
  out "        Install it first: ./scripts/setup-safe-sink.sh --apply"
  write_marker no no unknown "$DEFAULT_SINK" "${KA11_SINK:-unknown}"
  exit 1
fi
out "    Safe Sink '${SINK_NODE_NAME}' is present. OK."

# --- 2. KA11 must NOT be the default sink ------------------------------------
hr; out "2) KA11 physical sink must not be the default"
if [[ -n "$KA11_SINK" && "$DEFAULT_SINK" == "$KA11_SINK" ]]; then
  out "RESULT: NOT VERIFIED — KA11 is the DEFAULT sink; normal clients would bypass the Safe Sink."
  out "        Fix: pactl set-default-sink ${SINK_NODE_NAME}"
  write_marker no no unknown "$DEFAULT_SINK" "$KA11_SINK"
  exit 1
fi
if [[ "$DEFAULT_SINK" != "$SINK_NODE_NAME" ]]; then
  out "    NOTE: default sink is '${DEFAULT_SINK}', not the Safe Sink. Set it with:"
  out "          pactl set-default-sink ${SINK_NODE_NAME}"
fi
out "    KA11 is not the default sink. OK."

# --- 3. Controlled-path audio at SAFE volume ---------------------------------
hr; out "3) Low-volume audio through the controlled path"
if [[ -x "$SCRIPT_DIR/safe-volume.sh" ]]; then "$SCRIPT_DIR/safe-volume.sh" >>"$TESTLOG" 2>&1 || true; fi
out "    Default sink set to calibrated initial volume (~1.00). Playing a short test..."
play_test
THROUGH="$(ask_ynq "Did you hear the test through the KA11 -> Aura Studio 3?")"
out "    -> audio through controlled path = ${THROUGH}"

# --- 4. The 100% danger test -------------------------------------------------
hr; out "4) 100% client-volume hard-cap test (physical volume LOW!)"
DANGER="unknown"
if [[ -t 0 ]] && have wpctl; then
  read -r -p "    Run the 100% test now? Physical volume LOW. [yes/no]: " go || go=""
  if [[ "$(printf '%s' "$go" | tr '[:upper:]' '[:lower:]')" =~ ^y(es)?$ ]]; then
    out "    Setting ${SINK_NODE_NAME} to 100% and playing a short test..."
    wpctl set-volume "$SINK_NODE_NAME" 1.0 2>>"$TESTLOG" || out "    (could not set 100% via wpctl)"
    play_test
    DANGER="$(ask_ynq "At 100% Safe Sink volume, was the analog output DANGEROUSLY loud?")"
    # Restore safe level no matter what.
    wpctl set-volume "$SINK_NODE_NAME" 1.00 2>>"$TESTLOG" || true
    out "    Restored ${SINK_NODE_NAME} to 1.00."
  else
    out "    100% test skipped -> danger stays 'unknown' (cannot verify)."
  fi
else
  out "    Non-interactive or wpctl missing -> danger stays 'unknown' (cannot verify)."
fi
out "    -> dangerous at 100% = ${DANGER}"

# --- Verdict -----------------------------------------------------------------
hr; out "VERDICT"
if [[ "$THROUGH" == "yes" && "$DANGER" == "no" ]]; then
  out "RESULT: VERIFIED — audio reaches the KA11 through the Safe Sink and a 100%"
  out "        client volume did NOT produce dangerous output (operator-confirmed)."
  write_marker yes "$THROUGH" "$DANGER" "$DEFAULT_SINK" "${KA11_SINK:-unknown}"
  out "        Marker written: ${MARKER}"
  out "        DLNA MAY now be enabled MANUALLY via ./scripts/install-dlna.sh (still off by default)."
  exit 0
else
  out "RESULT: NOT VERIFIED — Safe Sink is not confirmed safe."
  out "        (need audio_through_controlled_path=yes AND dangerous_at_100pct=no)"
  out "        got: through=${THROUGH}, danger=${DANGER}"
  write_marker no "$THROUGH" "$DANGER" "$DEFAULT_SINK" "${KA11_SINK:-unknown}"
  out "        Marker written: ${MARKER}"
  out "        DLNA REMAINS BLOCKED."
  exit 1
fi
