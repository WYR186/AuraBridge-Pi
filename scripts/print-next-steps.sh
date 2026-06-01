#!/usr/bin/env bash
set -euo pipefail

# print-next-steps.sh — suggest the next safe bring-up command from current state.
# Read-only. It does not install, start, enable, or modify services.

HINTS='fiio|ka11|usb audio|usb-audio|\bdac\b|headphone|usb dac'

have() { command -v "$1" >/dev/null 2>&1; }
active_system() { have systemctl && systemctl is-active --quiet "$1" 2>/dev/null; }
active_user() { have systemctl && systemctl --user is-active --quiet "$1" 2>/dev/null; }

ka11_usb=no
ka11_sink=no
pipewire_ready=no
airplay_ready=no
spotify_ready=no

if have lsusb && lsusb 2>/dev/null | grep -iE "$HINTS" >/dev/null 2>&1; then
  ka11_usb=yes
fi
if have pactl && pactl list sinks short 2>/dev/null | grep -iE "$HINTS" >/dev/null 2>&1; then
  ka11_sink=yes
elif have wpctl && wpctl status 2>/dev/null | grep -iE "$HINTS" >/dev/null 2>&1; then
  ka11_sink=yes
fi
if active_user pipewire.service && active_user pipewire-pulse.service && active_user wireplumber.service; then
  pipewire_ready=yes
elif have pactl && pactl info >/dev/null 2>&1; then
  pipewire_ready=yes
fi
if active_system shairport-sync.service && active_system nqptp.service; then
  airplay_ready=yes
fi
if active_user librespot.service; then
  spotify_ready=yes
fi

echo "AuraBridge next-step helper"
echo
printf '  KA11 on USB:        %s\n' "$ka11_usb"
printf '  KA11 PipeWire sink: %s\n' "$ka11_sink"
printf '  PipeWire ready:     %s\n' "$pipewire_ready"
printf '  AirPlay services:   %s\n' "$airplay_ready"
printf '  Spotify service:    %s\n' "$spotify_ready"
echo

if [[ "$pipewire_ready" != "yes" ]]; then
  cat <<'EOF'
Next command:
  ./scripts/setup-pipewire.sh

Why:
  PipeWire / WirePlumber / pipewire-pulse are not confirmed reachable.
EOF
  exit 0
fi

if [[ "$ka11_usb" != "yes" || "$ka11_sink" != "yes" ]]; then
  cat <<'EOF'
Next command:
  ./scripts/check-ka11.sh

Why:
  KA11 is missing from USB and/or PipeWire detection. Fix hardware before
  installing playback services. Keep Aura Studio 3 physical volume low.
EOF
  exit 0
fi

if [[ "$airplay_ready" != "yes" ]]; then
  cat <<'EOF'
Next command:
  ./scripts/safe-volume.sh
  ./scripts/install-airplay2.sh

Why:
  KA11 and PipeWire are present, but AirPlay services are not active yet.
EOF
  exit 0
fi

if [[ "$spotify_ready" != "yes" ]]; then
  cat <<'EOF'
Next command:
  ./scripts/safe-volume.sh
  ./scripts/install-spotify.sh

Why:
  AirPlay is installed, but Spotify Connect is not active yet.
EOF
  exit 0
fi

cat <<'EOF'
All Phase 0-3 basics look present.

Validation checklist:
  1. Keep Aura Studio 3 physical volume LOW.
  2. Run ./scripts/status.sh.
  3. Confirm AirPlay target "Aura Studio 3 AirPlay" is visible and plays quietly.
  4. Confirm Spotify target "Aura Studio 3 Spotify" is visible and plays quietly.
  5. Reboot, then run ./scripts/status.sh again.
  6. Run ./scripts/collect-report.sh and archive the first-good report.

Do not run DLNA, apply Safe Sink, or modify WirePlumber policy during first
bring-up.
EOF
