#!/usr/bin/env bash
# output-target.sh — shared library: which physical audio output AuraBridge uses.
#
# AuraBridge can send audio to EITHER:
#   onboard  — the Raspberry Pi's built-in 3.5 mm AUX jack (bcm2835 Headphones)
#   usb      — an external USB DAC "小尾巴" / dongle (e.g. FiiO KA11)
#
# This library is the SINGLE place that knows how to recognise each device and
# how to pick one. Source it; never run it directly. It does not change the
# audio graph by itself — it only resolves names and the selected target so the
# other scripts (safe-sink, status, check-output, select-output, …) all agree.
#
# Selection order (first match wins):
#   1. $AURABRIDGE_OUTPUT environment variable   (onboard | usb | auto)
#   2. the config file written by select-output.sh
#   3. built-in default: "auto"
#
# "auto" prefers the USB dongle when one is actually present (so the moment your
# 小尾巴 hardware arrives and is plugged in, it takes over), and otherwise falls
# back to the Pi's onboard AUX. This is what makes the same image work before
# and after the dongle shows up.
#
# Sinks are ALWAYS referenced by their dynamically detected PipeWire sink NAME,
# never a hardcoded ALSA card number — consistent with the rest of the project.

# --- config location ---------------------------------------------------------
# Honour XDG; fall back to ~/.config. Overridable for tests via AURABRIDGE_CONF_DIR.
AURABRIDGE_CONF_DIR="${AURABRIDGE_CONF_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/aurabridge}"
AURABRIDGE_OUTPUT_CONF="${AURABRIDGE_CONF_DIR}/output.conf"

# --- device recognition hints (case-insensitive, matched on sink NAME) -------
# USB dongle / DAC. Mirrors the hints used by check-ka11.sh historically.
OUTPUT_USB_HINTS='fiio|ka11|meizu|usb audio|usb-audio|usb dac|\bdac\b'
# Pi onboard analog. PipeWire names the card 'alsa_output.platform-bcm2835...'.
OUTPUT_ONBOARD_HINTS='bcm2835|platform-bcm2835|built-in audio|onboard'
# Things that are NEVER a final physical output (our own virtual sink).
OUTPUT_EXCLUDE='aurabridge|safe.?sink'

_ot_have() { command -v "$1" >/dev/null 2>&1; }

# Read AURABRIDGE_OUTPUT= from the config file, if present. Echoes value or "".
_ot_read_conf() {
  [[ -r "$AURABRIDGE_OUTPUT_CONF" ]] || { echo ""; return; }
  # Accept lines like: AURABRIDGE_OUTPUT=onboard  (ignore comments/space)
  sed -nE 's/^[[:space:]]*AURABRIDGE_OUTPUT[[:space:]]*=[[:space:]]*"?([A-Za-z]+)"?.*/\1/p' \
    "$AURABRIDGE_OUTPUT_CONF" 2>/dev/null | tail -n1 | tr '[:upper:]' '[:lower:]'
}

# Resolve the CONFIGURED target (may be "auto"): env > conf > default.
# Echoes one of: onboard | usb | auto
output_configured_target() {
  local t="${AURABRIDGE_OUTPUT:-}"
  [[ -z "$t" ]] && t="$(_ot_read_conf)"
  [[ -z "$t" ]] && t="auto"
  t="$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')"
  case "$t" in
    onboard|usb|auto) printf '%s' "$t" ;;
    aux|headphone|headphones|jack)   printf 'onboard' ;;
    dongle|dac|ka11|fiio|xiaoweiba)  printf 'usb' ;;
    *) printf 'auto' ;;
  esac
}

# Detect the PipeWire sink NAME for a specific kind ("usb" or "onboard").
# Echoes the sink name or "" if not found. Needs pactl.
detect_sink_by_kind() {
  local kind="$1" hints
  case "$kind" in
    usb)     hints="$OUTPUT_USB_HINTS" ;;
    onboard) hints="$OUTPUT_ONBOARD_HINTS" ;;
    *) echo ""; return ;;
  esac
  _ot_have pactl || { echo ""; return; }
  pactl list sinks short 2>/dev/null \
    | grep -iE "$hints" \
    | grep -ivE "$OUTPUT_EXCLUDE" \
    | awk '{print $2}' \
    | head -n1
}

# Resolve the EFFECTIVE target after applying "auto" logic, based on what is
# actually present right now. Echoes: onboard | usb
output_effective_target() {
  local cfg; cfg="$(output_configured_target)"
  case "$cfg" in
    usb|onboard) printf '%s' "$cfg" ;;
    auto)
      if [[ -n "$(detect_sink_by_kind usb)" ]]; then
        printf 'usb'
      else
        printf 'onboard'
      fi
      ;;
  esac
}

# Detect the PipeWire sink NAME for the effective target. Echoes name or "".
# This is what safe-sink and friends should target.
detect_output_sink() {
  detect_sink_by_kind "$(output_effective_target)"
}

# Human description of the effective target, for logs/status.
describe_output_target() {
  case "$(output_effective_target)" in
    usb)     echo "USB DAC dongle (小尾巴, e.g. FiiO KA11) → 3.5 mm AUX" ;;
    onboard) echo "Raspberry Pi onboard 3.5 mm AUX (bcm2835 Headphones)" ;;
  esac
}
