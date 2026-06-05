#!/usr/bin/env bash
set -euo pipefail

# check-output.sh — validate the CURRENTLY SELECTED AuraBridge output, whether
# that is the Pi's onboard 3.5 mm AUX (bcm2835) or a USB DAC dongle (小尾巴).
#
# This is the target-aware sibling of check-ka11.sh. It uses the shared selection
# (scripts/lib/output-target.sh): env AURABRIDGE_OUTPUT > config > auto.
#
# For the USB target it still cares about USB enumeration; for the onboard target
# USB is irrelevant and it validates the ALSA bcm2835 card + the PipeWire sink.
# Detection is always DYNAMIC by name — never a hardcoded card number.
#
# Exit code: 0 on PASS/WARN, non-zero only on FAIL (selected output not usable).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/output-target.sh
. "$SCRIPT_DIR/lib/output-target.sh"

have() { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n===== %s =====\n' "$*"; }

TARGET="$(output_effective_target)"

section "Selected output"
echo "Configured : $(output_configured_target)"
echo "Effective  : ${TARGET}  — $(describe_output_target)"

# ---------------------------------------------------------------------------
# USB target → delegate to the dedicated, thorough KA11 validator.
# ---------------------------------------------------------------------------
if [[ "$TARGET" == "usb" ]]; then
  section "Delegating to check-ka11.sh (USB DAC validation)"
  if [[ -x "$SCRIPT_DIR/check-ka11.sh" ]]; then
    exec "$SCRIPT_DIR/check-ka11.sh"
  else
    echo "check-ka11.sh not found/executable."
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Onboard target.
# ---------------------------------------------------------------------------
alsa_found=0
sink_found=0
pw_running=0

section "aplay -l (ALSA playback cards)"
if have aplay; then
  aplay -l 2>/dev/null || echo "(aplay -l reported no cards)"
  if aplay -l 2>/dev/null | grep -iE 'headphone|bcm2835|built-in' >/dev/null 2>&1; then
    alsa_found=1
    echo
    echo ">> Onboard analog card matched:"
    aplay -l 2>/dev/null | grep -iE 'headphone|bcm2835|built-in' || true
  fi
else
  echo "(aplay not available — install 'alsa-utils' via setup-base.sh)"
fi

section "wpctl status (PipeWire graph)"
if have wpctl; then
  wpctl status 2>/dev/null && pw_running=1 || echo "(wpctl could not reach a PipeWire session)"
else
  echo "(wpctl not available — install 'wireplumber')"
fi

section "Onboard PipeWire sink detection"
onboard_sink="$(detect_sink_by_kind onboard || true)"
if [[ -n "$onboard_sink" ]]; then
  sink_found=1
  pw_running=1
  echo "Detected onboard sink: ${onboard_sink}"
else
  echo "Onboard sink NOT detected as a PipeWire sink yet."
fi

section "SUMMARY"
echo "ALSA onboard card (aplay -l) : $([[ $alsa_found -eq 1 ]] && echo yes || echo no)"
echo "PipeWire session reachable   : $([[ $pw_running -eq 1 ]] && echo yes || echo no)"
echo "Onboard PipeWire sink        : $([[ $sink_found -eq 1 ]] && echo yes || echo no)"
echo

if [[ "$alsa_found" -eq 0 ]]; then
  echo "RESULT: FAIL — the onboard analog card was not found."
  echo "        Ensure 'dtparam=audio=on' in the boot config and REBOOT:"
  echo "          ./scripts/setup-onboard-audio.sh"
  echo "        See docs/onboard-audio.md."
  exit 1
fi

if [[ "$alsa_found" -eq 1 && "$sink_found" -eq 1 ]]; then
  echo "RESULT: PASS — onboard AUX present at ALSA and PipeWire layers."
  echo "        Next: ./scripts/select-output.sh onboard, then a LOW-volume test."
  exit 0
fi

echo "RESULT: WARN — onboard card exists but is not a PipeWire sink yet."
echo "        Run ./scripts/setup-pipewire.sh, confirm 'wpctl status', then re-run."
exit 0
