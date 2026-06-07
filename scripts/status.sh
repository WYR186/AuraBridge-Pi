#!/usr/bin/env bash
set -euo pipefail

# status.sh — Phase 1: one-screen health summary for AuraBridge Pi.
# Never fails just because an optional service is missing. Read-only.

HINTS='fiio|ka11|usb audio|usb-audio|\bdac\b|headphone'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/output-target.sh
. "$SCRIPT_DIR/lib/output-target.sh"
# shellcheck source=lib/arbiter-lib.sh
if [[ -r "$SCRIPT_DIR/lib/arbiter-lib.sh" ]]; then
  . "$SCRIPT_DIR/lib/arbiter-lib.sh"
fi
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SS_MARKER="$REPO_ROOT/logs/safe-sink-verified.txt"

have() { command -v "$1" >/dev/null 2>&1; }

safe_sink_marker_gain() {
  [[ -r "$SS_MARKER" ]] || return 0
  sed -nE 's/^gain=([0-9]+([.][0-9]+)?).*/\1/p' "$SS_MARKER" 2>/dev/null | tail -n1
}

safe_sink_current_gain() {
  local conf="${HOME}/.config/pipewire/pipewire.conf.d/99-aurabridge-safe-sink.conf"
  [[ -r "$conf" ]] || return 0
  sed -nE 's/.*"mult"[[:space:]]*=[[:space:]]*([0-9]+([.][0-9]+)?).*/\1/p' "$conf" 2>/dev/null | head -n1
}

safe_sink_gain_matches_marker() {
  local marker_gain current_gain
  marker_gain="$(safe_sink_marker_gain)"
  current_gain="$(safe_sink_current_gain)"
  [[ -z "$marker_gain" || -z "$current_gain" || "$marker_gain" == "$current_gain" ]]
}

safe_sink_verified() {
  [[ -f "$SS_MARKER" ]] && grep -q '^SAFE_SINK_VERIFIED=yes' "$SS_MARKER" && safe_sink_gain_matches_marker
}

sink_name_by_id() {
  local id="$1"
  [[ -n "$id" ]] || return 0
  pactl list sinks short 2>/dev/null | awk -v id="$id" '$1 == id {print $2; exit}'
}

safe_sink_downstream() {
  have pactl || return 0
  pactl list sink-inputs 2>/dev/null | awk '
    /^Sink Input #/ { in_input = 1; sink = ""; safe = 0; next }
    in_input && /^[[:space:]]*Sink:/ { sink = $2; next }
    in_input && /node.name = "aurabridge_safe_sink.output"/ { safe = 1; next }
    in_input && /^$/ {
      if (safe && sink != "") { print sink; exit }
      in_input = 0; sink = ""; safe = 0
    }
    END {
      if (safe && sink != "") print sink
    }
  '
}

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
echo "[ Source arbiter (barge-in) ]"
report_service "Arbiter (user):" user aurabridge-arbiter.service
if have pactl; then
  if declare -F arb_managed_inputs >/dev/null 2>&1; then
    managed="$(arb_managed_inputs 2>/dev/null || true)"
  else
    managed=""
  fi
  if [[ -z "$managed" ]]; then
    total=0; playing=0
  else
    total="$(printf '%s\n' "$managed" | grep -c '|')"
    playing="$(printf '%s\n' "$managed" | grep -c '|no|')"
  fi
  printf '  %-26s %s\n' "Wireless streams (total):" "$total"
  printf '  %-26s %s\n' "Currently playing:" "$playing"
fi
printf '  %-26s %s\n' "(policy:)" "newest source wins; all protocols stay discoverable"
report_service "bluetooth.service:" system bluetooth.service
if have bluetoothctl; then
  if have timeout; then
    bt_show="$(timeout 4 bluetoothctl show 2>/dev/null || true)"
  else
    bt_show="$(bluetoothctl show 2>/dev/null || true)"
  fi
  printf '  %-26s %s\n' "BT alias:"        "$(printf '%s\n' "$bt_show" | sed -nE 's/.*Alias: (.*)$/\1/p' | head -n1)"
  printf '  %-26s %s\n' "BT discoverable:" "$(printf '%s\n' "$bt_show" | sed -nE 's/.*Discoverable: (yes|no).*/\1/p' | head -n1)"
  printf '  %-26s %s\n' "BT pairable:"     "$(printf '%s\n' "$bt_show" | sed -nE 's/.*Pairable: (yes|no).*/\1/p' | head -n1)"
else
  printf '  %-26s %s\n' "bluetoothctl:" "not installed (run setup-bluetooth.sh)"
fi

echo
echo "[ Phase 5 — Safe Sink (real-time safety) ]"
ss_current_gain="$(safe_sink_current_gain || true)"
ss_marker_gain="$(safe_sink_marker_gain || true)"
if have pactl && pactl list sinks short 2>/dev/null | grep -q 'aurabridge_safe_sink'; then
  printf '  %-26s %s\n' "Safe Sink node:" "present (aurabridge_safe_sink)"
  ss_sink_id="$(safe_sink_downstream || true)"
  ss_sink_name="$(sink_name_by_id "$ss_sink_id" || true)"
  if [[ -n "$ss_sink_name" ]]; then
    expected_sink="$(detect_output_sink 2>/dev/null || true)"
    printf '  %-26s %s\n' "Safe Sink downstream:" "$ss_sink_name"
    if [[ -n "$expected_sink" && "$ss_sink_name" != "$expected_sink" ]]; then
      printf '  %-26s %s\n' "Safe Sink warning:" "expected ${expected_sink}"
    fi
  else
    printf '  %-26s %s\n' "Safe Sink downstream:" "unknown/inactive"
  fi
else
  printf '  %-26s %s\n' "Safe Sink node:" "not present"
fi
printf '  %-26s %s\n' "Safe Sink gain:" "${ss_current_gain:-unknown}"
if [[ -n "$ss_marker_gain" ]]; then
  printf '  %-26s %s\n' "Verified marker gain:" "$ss_marker_gain"
fi
if safe_sink_verified; then
  printf '  %-26s %s\n' "Safe Sink verified:" "YES"
else
  if [[ -n "$ss_marker_gain" && -n "$ss_current_gain" && "$ss_marker_gain" != "$ss_current_gain" ]]; then
    printf '  %-26s %s\n' "Safe Sink verified:" "NO (gain mismatch; DLNA stays blocked)"
  else
    printf '  %-26s %s\n' "Safe Sink verified:" "NO (DLNA stays blocked)"
  fi
fi

echo
echo "[ Phase 6 — DLNA (gated; off by default) ]"
report_service "DLNA (gmrender, user):" user gmrender.service
if have ss && ss -lun 2>/dev/null | grep -q ':1900'; then
  printf '  %-26s %s\n' "DLNA SSDP:" "listening on UDP 1900"
else
  printf '  %-26s %s\n' "DLNA SSDP:" "not listening"
fi
if safe_sink_verified; then
  printf '  %-26s %s\n' "DLNA gate:" "unlockable (Safe Sink verified) — start/enable explicit only"
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
