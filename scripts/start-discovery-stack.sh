#!/usr/bin/env bash
set -euo pipefail

# start-discovery-stack.sh - make AirPlay and DLNA visible at the same time.
#
# This script deliberately keeps discovery separate from playback arbitration:
#   - AirPlay publishes over mDNS/Bonjour via Avahi + shairport-sync.
#   - DLNA publishes over SSDP via gmrender.
# The source arbiter handles "newest source wins" only after clients connect.
#
# Default mode starts the already-installed services and verifies the local
# discovery signals. --check-only changes nothing and only reports.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIRPLAY_NAME="${AIRPLAY_NAME:-Aura Studio 3 AirPlay}"
DLNA_NAME="${DLNA_NAME:-Aura Studio 3 DLNA}"
DISCOVERY_IFACE="${AURABRIDGE_DISCOVERY_IFACE:-${WIFI_IFACE:-wlan0}}"
DLNA_HTTP_PORT="${DLNA_HTTP_PORT:-49494}"
CHECK_ONLY=0

log()  { printf '[discovery] %s\n' "$*"; }
warn() { printf '[discovery][WARN] %s\n' "$*" >&2; }
fail() { printf '[discovery][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

case "${1:-}" in
  ""|--start)
    CHECK_ONLY=0
    ;;
  --check-only)
    CHECK_ONLY=1
    ;;
  -h|--help)
    cat <<EOF
Usage: ./scripts/start-discovery-stack.sh [--start|--check-only]

  --start       Start AirPlay system services and gmrender, then verify both.
  --check-only  Read-only check: verify AirPlay mDNS and DLNA SSDP/HTTP.

Prereqs for DLNA: ./scripts/install-dlna.sh must have installed the user unit,
and scripts/check-safe-sink-gate.sh must pass for the active Safe Sink gain.
EOF
    exit 0
    ;;
  *)
    fail "Unknown argument '$1'. Use --start, --check-only, or --help."
    ;;
esac

[[ "$(id -u)" -eq 0 ]] && fail "Do not run as root. gmrender is a USER service in the normal user's PipeWire session."
have systemctl || fail "systemctl not found."

if [[ "$CHECK_ONLY" == "0" ]]; then
  log "Starting AirPlay discovery services (Avahi, NQPTP, Shairport Sync)."
  sudo systemctl start avahi-daemon.service nqptp.service shairport-sync.service

  log "Checking DLNA Safe Sink gate before starting gmrender."
  if ! "$SCRIPT_DIR/check-safe-sink-gate.sh" >/dev/null; then
    fail "DLNA Safe Sink gate failed. Re-run ./scripts/setup-safe-sink.sh --apply and ./scripts/test-safe-sink.sh on the Pi before starting DLNA."
  fi

  if ! systemctl --user cat gmrender.service >/dev/null 2>&1; then
    fail "gmrender.service is not installed for this user. Run: ./scripts/install-dlna.sh --start"
  fi

  log "Starting DLNA renderer for this session."
  systemctl --user start gmrender.service
fi

airplay_ok=0
dlna_ok=0

printf '\n===== Interface =====\n'
if have ip; then
  ip -o -4 addr show dev "$DISCOVERY_IFACE" scope global 2>/dev/null | sed 's/^/  /' || true
else
  warn "ip not found; cannot show ${DISCOVERY_IFACE} address."
fi
if have iw; then
  ps="$(iw dev "$DISCOVERY_IFACE" get power_save 2>/dev/null || true)"
  if printf '%s' "$ps" | grep -qi 'on'; then
    warn "Wi-Fi power save is ON for ${DISCOVERY_IFACE}; multicast discovery can disappear under load. Run ./scripts/setup-wifi-powersave.sh."
  elif [[ -n "$ps" ]]; then
    printf '  %s\n' "$ps"
  fi
fi

printf '\n===== AirPlay mDNS =====\n'
if systemctl is-active --quiet avahi-daemon.service nqptp.service shairport-sync.service; then
  log "AirPlay services are active."
else
  warn "One or more AirPlay services are not active: avahi-daemon, nqptp, shairport-sync."
fi

if have avahi-browse; then
  ap_records="$(avahi-browse -rt _raop._tcp 2>/dev/null || true)"
  if printf '%s\n' "$ap_records" | grep -q "$AIRPLAY_NAME"; then
    printf '%s\n' "$ap_records" | grep "$AIRPLAY_NAME" | sed 's/^/  /'
    airplay_ok=1
  else
    warn "Did not find '${AIRPLAY_NAME}' in local _raop._tcp records."
  fi
else
  warn "avahi-browse not found; falling back to service/port checks."
  if systemctl is-active --quiet shairport-sync.service && have ss && ss -ltn 2>/dev/null | grep -q ':7000'; then
    airplay_ok=1
  fi
fi

printf '\n===== DLNA SSDP =====\n'
if "$SCRIPT_DIR/check-dlna-discovery.sh"; then
  dlna_ok=1
fi

printf '\n===== Simultaneous Discovery Summary =====\n'
printf '  AirPlay mDNS visible : %s\n' "$([[ "$airplay_ok" -eq 1 ]] && echo yes || echo NO)"
printf '  DLNA SSDP visible    : %s\n' "$([[ "$dlna_ok" -eq 1 ]] && echo yes || echo NO)"
printf '  AirPlay name         : %s\n' "$AIRPLAY_NAME"
printf '  DLNA name            : %s\n' "$DLNA_NAME"
printf '  DLNA HTTP port       : %s\n' "$DLNA_HTTP_PORT"

if [[ "$airplay_ok" -eq 1 && "$dlna_ok" -eq 1 ]]; then
  log "PASS: AirPlay and DLNA are both locally discoverable. If a phone still misses one, check router client isolation and multicast/IGMP settings."
  exit 0
fi

fail "AirPlay and DLNA are not both discoverable yet. See the sections above."
