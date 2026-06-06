#!/usr/bin/env bash
set -euo pipefail

# setup-onboard-audio.sh — Phase 1 (onboard-AUX variant): make the Raspberry Pi's
# built-in 3.5 mm AUX jack (bcm2835 Headphones) usable as the AuraBridge output.
#
# Use this when you do NOT yet have the USB DAC dongle (小尾巴). Everything else
# in the project (AirPlay, Spotify, Safe Sink, status) then targets the onboard
# jack instead of the KA11. When the dongle arrives later, run:
#     ./scripts/select-output.sh usb     (or 'auto')
# and the whole stack switches over — nothing here is destructive to that path.
#
# What it does (all idempotent, all reversible):
#   1. Ensures 'dtparam=audio=on' in the boot config so the bcm2835 audio device
#      enumerates. Backs up the file first. A REBOOT is required if it changed.
#   2. Records 'onboard' as the AuraBridge output selection (select-output.sh).
#   3. Best-effort unmutes the onboard ALSA mixer controls.
#   4. Sets the onboard PipeWire sink as the default and applies the safe volume.
#
# It NEVER routes clients to ALSA hw:/plughw: and never hardcodes a card number.
#
# A NOTE ON QUALITY: the Pi's onboard 3.5 mm output is PWM-based and noticeably
# noisier/weaker than a real USB DAC. It is perfect for bring-up and testing, but
# the USB dongle remains the intended final output. See docs/onboard-audio.md.
#
# Env:
#   SAFE_VOLUME=0.01   initial volume passed through to safe-volume.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/output-target.sh
. "$SCRIPT_DIR/lib/output-target.sh"

log()  { printf '[onboard-audio] %s\n' "$*"; }
warn() { printf '[onboard-audio][WARN] %s\n' "$*" >&2; }
die()  { printf '[onboard-audio][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

SUDO=""
[[ "$(id -u)" -ne 0 ]] && SUDO="sudo"

# --- 1. Ensure dtparam=audio=on in the boot config ---------------------------
reboot_needed=0
BOOT_CONF=""
for c in /boot/firmware/config.txt /boot/config.txt; do
  [[ -f "$c" ]] && { BOOT_CONF="$c"; break; }
done

if [[ -z "$BOOT_CONF" ]]; then
  warn "No boot config.txt found (not on a Pi, or unusual image). Skipping dtparam step."
  warn "On the Pi, ensure 'dtparam=audio=on' is set in /boot/firmware/config.txt."
else
  log "Boot config: ${BOOT_CONF}"
  if grep -qE '^[[:space:]]*dtparam=audio=on' "$BOOT_CONF"; then
    log "dtparam=audio=on already present."
  else
    ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
    log "Backing up ${BOOT_CONF} -> ${BOOT_CONF}.bak.${ts}"
    $SUDO cp -a "$BOOT_CONF" "${BOOT_CONF}.bak.${ts}"
    if grep -qE '^[[:space:]]*#?[[:space:]]*dtparam=audio=' "$BOOT_CONF"; then
      log "Enabling existing (commented/off) dtparam=audio line."
      $SUDO sed -i -E 's/^[[:space:]]*#?[[:space:]]*dtparam=audio=.*/dtparam=audio=on/' "$BOOT_CONF"
    else
      log "Appending dtparam=audio=on."
      printf 'dtparam=audio=on\n' | $SUDO tee -a "$BOOT_CONF" >/dev/null
    fi
    reboot_needed=1
  fi
fi

# --- 2. Record the selection (without trying to switch yet) -------------------
mkdir -p "$AURABRIDGE_CONF_DIR"
cat > "$AURABRIDGE_OUTPUT_CONF" <<EOF
# AuraBridge output selection — written by scripts/setup-onboard-audio.sh
# One of: onboard | usb | auto
AURABRIDGE_OUTPUT=onboard
EOF
log "Recorded output selection 'onboard' in ${AURABRIDGE_OUTPUT_CONF}"

# --- 3. Best-effort: unmute onboard ALSA mixer controls ----------------------
# The onboard card is the one whose name/id mentions 'Headphones'/'bcm2835'.
if have aplay && have amixer; then
  onboard_card="$(aplay -l 2>/dev/null \
    | sed -nE 's/^card ([0-9]+):.*([Hh]eadphone|bcm2835|[Bb]uilt-in).*/\1/p' \
    | head -n1 || true)"
  if [[ -n "$onboard_card" ]]; then
    log "Onboard ALSA card index: ${onboard_card} — unmuting its controls (best-effort)."
    while IFS= read -r ctrl; do
      [[ -z "$ctrl" ]] && continue
      amixer -c "$onboard_card" sset "$ctrl" unmute >/dev/null 2>&1 || true
    done < <(amixer -c "$onboard_card" scontrols 2>/dev/null \
              | sed -nE "s/^Simple mixer control '([^']+)'.*/\1/p")
  else
    log "No onboard ALSA card detected yet (likely needs the reboot above)."
  fi
fi

# --- 4. Switch PipeWire to the onboard sink now (if reachable) ----------------
echo
if [[ "$reboot_needed" -eq 1 ]]; then
  warn "Boot config changed: a REBOOT is required before the onboard jack appears."
  warn "Reboot, then run:  ./scripts/select-output.sh onboard"
else
  if have pactl; then
    sink="$(detect_sink_by_kind onboard)"
    if [[ -n "$sink" ]]; then
      log "Onboard sink: ${sink} — setting as default."
      pactl set-default-sink "$sink" 2>/dev/null || warn "Could not set default sink; try: pactl set-default-sink ${sink}"
      [[ -x "$SCRIPT_DIR/safe-volume.sh" ]] && { "$SCRIPT_DIR/safe-volume.sh" || warn "safe-volume.sh reported an issue."; }
    else
      warn "Onboard sink not visible yet. Check 'wpctl status' / ensure PipeWire is running,"
      warn "then run: ./scripts/select-output.sh onboard"
    fi
  else
    warn "pactl not available — run ./scripts/setup-pipewire.sh, then ./scripts/select-output.sh onboard"
  fi
fi

echo
log "Done. Validate with: ./scripts/check-output.sh   (and ./scripts/status.sh)"
log "When your USB dongle arrives:  ./scripts/select-output.sh usb   (or 'auto')"
