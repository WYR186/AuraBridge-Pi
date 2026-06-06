#!/usr/bin/env bash
set -euo pipefail

# setup-wifi-powersave.sh — persistently DISABLE Wi-Fi power save so the Pi keeps
# answering multicast (mDNS for AirPlay, SSDP for DLNA) reliably, including while
# an audio stream is running. RPi Wi-Fi defaults power_save ON, which is the
# single most common reason an AirPlay/DLNA device "disappears" from other phones
# (see shairport-sync TROUBLESHOOTING + issue #725). See
# docs/airplay-takeover-and-discovery.md.
#
# Chooses the right persistence mechanism automatically:
#   - NetworkManager managing Wi-Fi  -> /etc/NetworkManager/conf.d drop-in
#     (wifi.powersave = 2  ==  disable). This is the proper NM way; a systemd
#     hack would be undone by NM on every (re)connect.
#   - Otherwise                      -> enable systemd unit
#     aurabridge-wifi-powersave@<iface>.service.
# Either way it also applies the setting immediately for the current session.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NM_CONF="/etc/NetworkManager/conf.d/aurabridge-wifi-powersave.conf"
UNIT_SRC="$REPO_ROOT/systemd/aurabridge-wifi-powersave@.service"
UNIT_DST="/etc/systemd/system/aurabridge-wifi-powersave@.service"

log()  { printf '[wifi-ps] %s\n' "$*"; }
warn() { printf '[wifi-ps][WARN] %s\n' "$*" >&2; }
die()  { printf '[wifi-ps][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[[ "$(id -u)" -eq 0 ]] && SUDO="" || SUDO="sudo"

# --- detect the Wi-Fi interface (allow override: WIFI_IFACE=...) -------------
detect_wifi_iface() {
  [[ -n "${WIFI_IFACE:-}" ]] && { printf '%s' "$WIFI_IFACE"; return; }
  local i
  if have iw; then
    i="$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}')"
    [[ -n "$i" ]] && { printf '%s' "$i"; return; }
  fi
  for i in /sys/class/net/wl*; do
    [[ -e "$i" ]] && { printf '%s' "$(basename "$i")"; return; }
  done
  printf 'wlan0'
}
IFACE="$(detect_wifi_iface)"
log "Wi-Fi interface: ${IFACE}"

# --- apply immediately (best effort) -----------------------------------------
if have iw; then
  if $SUDO iw dev "$IFACE" set power_save off 2>/dev/null; then
    log "Applied now: power_save off on ${IFACE}."
  else
    warn "Could not set power_save off now (will still persist below)."
  fi
  log "Current: $(iw dev "$IFACE" get power_save 2>/dev/null || echo 'unknown')"
else
  warn "'iw' not found. Install: sudo apt-get install -y iw"
fi

# --- persist via the manager that actually owns Wi-Fi ------------------------
nm_active() { have systemctl && systemctl is-active NetworkManager >/dev/null 2>&1; }

if nm_active; then
  log "NetworkManager is active -> writing ${NM_CONF} (wifi.powersave = 2 = disable)."
  $SUDO install -d /etc/NetworkManager/conf.d
  printf '[connection]\nwifi.powersave = 2\n' | $SUDO tee "$NM_CONF" >/dev/null
  if have nmcli; then
    $SUDO nmcli connection reload >/dev/null 2>&1 || true
    # Re-apply to the live connection so a reconnect is not required.
    active_con="$(nmcli -t -f NAME connection show --active 2>/dev/null | head -n1 || true)"
    if [[ -n "$active_con" ]]; then
      $SUDO nmcli connection modify "$active_con" wifi.powersave 2 >/dev/null 2>&1 || true
    fi
  fi
  log "Persisted via NetworkManager. (Reconnect or reboot to be fully certain.)"
else
  log "NetworkManager not active -> using systemd unit for ${IFACE}."
  [[ -f "$UNIT_SRC" ]] || die "Missing $UNIT_SRC"
  $SUDO install -m 0644 "$UNIT_SRC" "$UNIT_DST"
  $SUDO systemctl daemon-reload 2>/dev/null || warn "daemon-reload failed."
  if $SUDO systemctl enable --now "aurabridge-wifi-powersave@${IFACE}.service" 2>/dev/null; then
    log "Enabled aurabridge-wifi-powersave@${IFACE}.service (runs at boot)."
  else
    warn "Could not enable the unit. Enable manually:"
    warn "  sudo systemctl enable --now aurabridge-wifi-powersave@${IFACE}.service"
  fi
fi

cat <<EOF

[wifi-ps] Done. Verify (should print 'Power save: off'):
  iw dev ${IFACE} get power_save

[wifi-ps] This keeps AirPlay (mDNS) and DLNA (SSDP) discoverable even while the Pi
[wifi-ps] is streaming. For best multicast reliability, prefer wired Ethernet for
[wifi-ps] the Pi and disable AP/client isolation + IGMP snooping on the router.
EOF
