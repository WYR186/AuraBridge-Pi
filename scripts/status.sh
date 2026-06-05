#!/usr/bin/env bash
set -euo pipefail

# status.sh — Phase 1: one-screen health summary for AuraBridge Pi.
# Never fails just because an optional service is missing. Read-only.

HINTS='fiio|ka11|usb audio|usb-audio|\bdac\b|headphone'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/output-target.sh
. "$SCRIPT_DIR/lib/output-target.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SS_MARKER="$REPO_ROOT/logs/safe-sink-verified.txt"

have() { command -v "$1" >/dev/null 2>&1; }

safe_sink_verified() { [[ -f "$SS_MARKER" ]] && grep -q '^SAFE_SINK_VERIFIED=yes' "$SS_MARKER"; }

# Report a unit's active state, or "not installed" if no fragment exists.
report_service() {
  local label="$1" scope="$2" unit="$3"
  if [[ "$scope" == "user" ]]; then
    if systemctl --user cat "$unit" >/dev/null 2>&1; then
      printf '  %-26s %s\n' "$label" "$(systemctl --user is-active "$unit" 2>/dev/null || echo unknown)"
    else
      printf '  %-26s %s\n' "$label" "not installed"
    fi
  else
    if systemctl cat "$unit" >/dev/null 2>&1; then
      printf '  %-26s %s\n' "$label" "$(systemctl is-active "$unit" 2>/dev/null || echo unknown)"
    else
      printf '  %-26s %s\n' "$label" "not installed"
    fi
  fi
}

echo "============================================"
echo " AuraBridge Pi Status"
echo "============================================"

echo
echo "[ Host ]"
printf '  %-26s %s\n' "Hostname:" "$(hostname 2>/dev/null || echo unknown)"
ip_addr="$(hostname -I 2>/dev/null | tr -s ' ' || true)"
[[ -z "${ip_addr// }" ]] && ip_addr="$(ip -4 route get 1.1.1.1 2>/dev/null | sed -nE 's/.* src ([0-9.]+).*/\1/p' || true)"
printf '  %-26s %s\n' "IP address:" "${ip_addr:-unknown}"

echo
echo "[ Audio stack ]"
if have pipewire;    then printf '  %-26s %s\n' "PipeWire version:"    "$(pipewire --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"; else printf '  %-26s %s\n' "PipeWire version:" "not installed"; fi
if have wireplumber; then printf '  %-26s %s\n' "WirePlumber version:" "$(wireplumber --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)"; else printf '  %-26s %s\n' "WirePlumber version:" "not installed"; fi
report_service "PipeWire (user):"      user pipewire.service
report_service "pipewire-pulse (user):" user pipewire-pulse.service
report_service "WirePlumber (user):"   user wireplumber.service

echo
echo "[ Default sink ]"
if have pactl; then
  printf '  %-26s %s\n' "Default sink:" "$(pactl get-default-sink 2>/dev/null || echo unknown)"
else
  printf '  %-26s %s\n' "Default sink:" "(pactl unavailable)"
fi
if have wpctl; then
  printf '  %-26s %s\n' "Default sink volume:" "$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo unknown)"
else
  printf '  %-26s %s\n' "Default sink volume:" "(wpctl unavailable)"
fi

echo
echo "[ Output selection ]"
printf '  %-26s %s\n' "Configured:" "$(output_configured_target)"
printf '  %-26s %s\n' "Effective:" "$(output_effective_target) — $(describe_output_target)"
ob_sink="$(detect_sink_by_kind onboard 2>/dev/null || true)"; usb_sink="$(detect_sink_by_kind usb 2>/dev/null || true)"
printf '  %-26s %s\n' "Onboard sink (bcm2835):" "${ob_sink:-(none)}"
printf '  %-26s %s\n' "USB dongle/DAC sink:" "${usb_sink:-(none)}"
printf '  %-26s %s\n' "(switch output:)" "./scripts/select-output.sh onboard|usb|auto"

echo
echo "[ KA11 / USB DAC detection ]"
ka11_usb="no"; ka11_sink="no"
have lsusb && lsusb 2>/dev/null | grep -iE "$HINTS" >/dev/null 2>&1 && ka11_usb="yes"
have pactl && pactl list sinks short 2>/dev/null | grep -iE "$HINTS" >/dev/null 2>&1 && ka11_sink="yes"
printf '  %-26s %s\n' "Seen on USB (lsusb):" "$ka11_usb"
printf '  %-26s %s\n' "Seen as PipeWire sink:" "$ka11_sink"
printf '  %-26s %s\n' "(full validation:)" "./scripts/check-output.sh"

echo
echo "[ Phase 2/3 services ]"
report_service "AirPlay (shairport-sync):" system shairport-sync.service
report_service "NQPTP:"                    system nqptp.service
report_service "Spotify (librespot, user):" user librespot.service

echo
echo "[ Phase 4 — Bluetooth (MVP Plus) ]"
report_service "bluetooth.service:" system bluetooth.service
if have bluetoothctl; then
  bt_show="$(bluetoothctl show 2>/dev/null || true)"
  printf '  %-26s %s\n' "BT alias:"        "$(printf '%s\n' "$bt_show" | sed -nE 's/.*Alias: (.*)$/\1/p' | head -n1)"
  printf '  %-26s %s\n' "BT discoverable:" "$(printf '%s\n' "$bt_show" | sed -nE 's/.*Discoverable: (yes|no).*/\1/p' | head -n1)"
  printf '  %-26s %s\n' "BT pairable:"     "$(printf '%s\n' "$bt_show" | sed -nE 's/.*Pairable: (yes|no).*/\1/p' | head -n1)"
else
  printf '  %-26s %s\n' "bluetoothctl:" "not installed (run setup-bluetooth.sh)"
fi

echo
echo "[ Phase 5 — Safe Sink (real-time safety) ]"
if have pactl && pactl list sinks short 2>/dev/null | grep -q 'aurabridge_safe_sink'; then
  printf '  %-26s %s\n' "Safe Sink node:" "present (aurabridge_safe_sink)"
else
  printf '  %-26s %s\n' "Safe Sink node:" "not present"
fi
if safe_sink_verified; then
  printf '  %-26s %s\n' "Safe Sink verified:" "YES"
else
  printf '  %-26s %s\n' "Safe Sink verified:" "NO (DLNA stays blocked)"
fi

echo
echo "[ Phase 6 — DLNA (gated; off by default) ]"
report_service "DLNA (gmrender, user):" user gmrender.service
if safe_sink_verified; then
  printf '  %-26s %s\n' "DLNA gate:" "unlockable (Safe Sink verified) — manual start only"
else
  printf '  %-26s %s\n' "DLNA gate:" "BLOCKED (Safe Sink not verified)"
fi

echo
echo "[ Recent errors (best-effort) ]"
if journalctl -p err -n 12 --no-pager >/dev/null 2>&1; then
  journalctl -p err -n 12 --no-pager 2>/dev/null || true
else
  echo "  (system journal not readable without privileges; try: sudo journalctl -p err -n 12)"
fi

echo
echo "Done. For logs: ./scripts/logs.sh"
