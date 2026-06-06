#!/usr/bin/env bash
set -euo pipefail

# select-output.sh — choose which physical output AuraBridge uses, and (if a
# PipeWire session is reachable) switch to it now.
#
#   onboard   Raspberry Pi built-in 3.5 mm AUX jack (bcm2835 Headphones)
#   usb       external USB DAC dongle "小尾巴" (e.g. FiiO KA11)
#   auto      prefer the USB dongle when one is present, else onboard (default)
#   status    print the current selection and what is detected, change nothing
#
# This writes the choice to a small config file so every other AuraBridge script
# (safe-sink, status, check-output, …) follows the same target. It NEVER routes
# to ALSA hw:/plughw: directly and never hardcodes a card number — it sets the
# PipeWire default sink by its dynamically detected name.
#
# Usage:
#   ./scripts/select-output.sh onboard
#   ./scripts/select-output.sh usb
#   ./scripts/select-output.sh auto
#   ./scripts/select-output.sh status
#
# Env:
#   ASSUME_YES=1   do not prompt (kept for symmetry; this script is low-risk)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/output-target.sh
. "$SCRIPT_DIR/lib/output-target.sh"

log()  { printf '[select-output] %s\n' "$*"; }
warn() { printf '[select-output][WARN] %s\n' "$*" >&2; }
die()  { printf '[select-output][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

write_choice() {
  local choice="$1"
  mkdir -p "$AURABRIDGE_CONF_DIR"
  cat > "$AURABRIDGE_OUTPUT_CONF" <<EOF
# AuraBridge output selection — written by scripts/select-output.sh
# One of: onboard | usb | auto
#   onboard = Pi built-in 3.5 mm AUX (bcm2835 Headphones)
#   usb     = external USB DAC dongle (小尾巴, e.g. FiiO KA11)
#   auto    = prefer the USB dongle when present, else onboard
AURABRIDGE_OUTPUT=${choice}
EOF
  log "Saved selection '${choice}' to ${AURABRIDGE_OUTPUT_CONF}"
}

# Try to make the resolved sink the PipeWire default and apply a safe volume.
apply_now() {
  have pactl || { warn "pactl not available — selection saved, but cannot switch now. Run setup-pipewire.sh."; return; }
  local sink; sink="$(detect_output_sink)"
  if [[ -z "$sink" ]]; then
    warn "Target '$(output_effective_target)' is not visible as a PipeWire sink yet."
    case "$(output_effective_target)" in
      onboard) warn "Run ./scripts/setup-onboard-audio.sh (it enables the onboard jack)."; ;;
      usb)     warn "Plug in the USB dongle and run ./scripts/check-output.sh."; ;;
    esac
    return
  fi
  log "Effective target: $(describe_output_target)"
  log "Setting default sink -> ${sink}"
  if pactl set-default-sink "$sink" 2>/dev/null; then
    log "Default sink is now '${sink}'."
  else
    warn "Could not set default sink. Try: pactl set-default-sink ${sink}"
  fi
  if [[ -x "$SCRIPT_DIR/safe-volume.sh" ]]; then
    "$SCRIPT_DIR/safe-volume.sh" || warn "safe-volume.sh reported an issue (continuing)."
  fi
}

print_status() {
  local src="from config/default"
  [[ -n "${AURABRIDGE_OUTPUT:-}" ]] && src="from \$AURABRIDGE_OUTPUT"
  echo "Configured selection : $(output_configured_target)   (${src})"
  echo "Effective target     : $(output_effective_target)  — $(describe_output_target)"
  echo "Config file          : ${AURABRIDGE_OUTPUT_CONF}$( [[ -r "$AURABRIDGE_OUTPUT_CONF" ]] && echo "" || echo " (not written yet; using default)")"
  echo
  echo "Detected PipeWire sinks:"
  echo "  onboard (bcm2835): $(detect_sink_by_kind onboard || true)"
  echo "  usb dongle/DAC   : $(detect_sink_by_kind usb || true)"
  if have pactl; then
    echo "  current default  : $(pactl get-default-sink 2>/dev/null || echo unknown)"
  fi
}

main() {
  local arg="${1:-status}"
  case "$arg" in
    onboard|usb|auto)
      write_choice "$arg"
      echo
      apply_now
      echo
      print_status
      ;;
    status|"")
      print_status ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//' ;;
    *)
      die "Unknown argument '$arg'. Use: onboard | usb | auto | status | --help" ;;
  esac
}

main "$@"
