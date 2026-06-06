#!/usr/bin/env bash
set -euo pipefail

# volume-guard-loop.sh — RECOVERY / AUDIT / DIAGNOSTICS ONLY.
#
# This is NOT real-time speaker protection. It polls the default sink volume and
# clamps it back down AFTER the fact. Because it polls, a client that sets a high
# volume can still be loud for the interval between checks. Do NOT treat this as
# a limiter, hard cap, or speaker protection, and do NOT use it to justify
# enabling DLNA. See docs/volume-safety.md.
#
# Modes:
#   (default)      loop forever, checking every GUARD_INTERVAL seconds
#   --once         perform a single check and exit (used by the systemd timer)
#
# Env vars:
#   SAFE_VOLUME     value to clamp back to        (default 0.01)
#   MAX_VOLUME      threshold that triggers clamp (default 1.30)
#   GUARD_INTERVAL  seconds between checks         (default 5)

SAFE_VOLUME="${SAFE_VOLUME:-0.01}"
MAX_VOLUME="${MAX_VOLUME:-1.30}"
GUARD_INTERVAL="${GUARD_INTERVAL:-5}"

ONCE=0
if [[ "${1:-}" == "--once" || "${GUARD_ONCE:-0}" == "1" ]]; then
  ONCE=1
fi

log()  { printf '[volume-guard] %s\n' "$*"; }
warn() { printf '[volume-guard][WARN] %s\n' "$*" >&2; }

banner() {
  echo "[volume-guard] This is recovery and diagnostics only. This is not real-time speaker protection."
  echo "[volume-guard] This does not make DLNA safe."
}

if ! command -v wpctl >/dev/null 2>&1; then
  warn "wpctl not found — cannot read or clamp volume. Install PipeWire/WirePlumber."
  exit 1
fi

# Read the default sink volume as a decimal (e.g. 0.01). Empty on failure.
read_volume() {
  # 'wpctl get-volume @DEFAULT_AUDIO_SINK@' -> "Volume: 0.01" or "Volume: 0.01 [MUTED]"
  wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null \
    | awk '/[Vv]olume:/ { print $2; exit }'
}

# Float ">" comparison via awk (no bc dependency required).
gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a+0 > b+0) }'; }

check_once() {
  local vol
  vol="$(read_volume)"
  if [[ -z "$vol" ]]; then
    warn "Could not read default sink volume (no PipeWire session?). Skipping."
    return 0
  fi
  if gt "$vol" "$MAX_VOLUME"; then
    warn "Default sink volume ${vol} exceeds MAX ${MAX_VOLUME} — clamping to ${SAFE_VOLUME} (recovery)."
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$SAFE_VOLUME" || warn "Clamp failed."
  else
    log "Default sink volume ${vol} is within limit (<= ${MAX_VOLUME}). No action."
  fi
  return 0
}

banner

if [[ "$ONCE" -eq 1 ]]; then
  check_once
  exit 0
fi

log "Starting recovery loop: clamp to ${SAFE_VOLUME} if > ${MAX_VOLUME}, every ${GUARD_INTERVAL}s."
log "Press Ctrl-C to stop."
while true; do
  check_once
  sleep "$GUARD_INTERVAL"
done
