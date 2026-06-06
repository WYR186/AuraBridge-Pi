#!/usr/bin/env bash
set -uo pipefail

# diagnose-discovery.sh — read-only "why can't a SECOND phone see the device while
# the first one is streaming?" check. Run it ON THE PI, ideally WHILE one iPhone
# is actively AirPlaying, and (best) while a second device is searching.
#
# It distinguishes the two layers (see docs/airplay-takeover-and-discovery.md):
#   - DISCOVERY layer: AirPlay (mDNS) and DLNA (SSDP) both vanish for other phones
#     => network/multicast, most often Wi-Fi power save. Both buses are
#     independent, so if BOTH disappear together it is NOT a per-protocol bug.
#   - TAKEOVER layer: device is visible but a 2nd AirPlay sender gets "busy"
#     => shairport-sync sessioncontrol.allow_session_interruption.
#
# Changes nothing. Exit 0 always (it is a report).

have()    { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n===== %s =====\n' "$*"; }

# --- Wi-Fi interface ---------------------------------------------------------
WIFI_IFACE="${WIFI_IFACE:-}"
if [[ -z "$WIFI_IFACE" ]] && have iw; then
  WIFI_IFACE="$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}')"
fi
[[ -z "$WIFI_IFACE" ]] && WIFI_IFACE="wlan0"

section "Interfaces / addresses"
if have ip; then
  ip -o -4 addr show scope global 2>/dev/null | awk '{print "  "$2"  "$4}'
else
  hostname -I 2>/dev/null | sed 's/^/  /'
fi
on_eth="no"; ip -o -4 addr show scope global 2>/dev/null | grep -qE '\b(eth|end|enp)' && on_eth="yes"
echo "  Wi-Fi iface: ${WIFI_IFACE}    On Ethernet too: ${on_eth}"

# --- Wi-Fi power save (the #1 culprit) ---------------------------------------
section "Wi-Fi power save  (want: OFF)"
if have iw; then
  ps="$(iw dev "$WIFI_IFACE" get power_save 2>/dev/null | sed 's/^/  /')"
  echo "${ps:-  (could not read; is ${WIFI_IFACE} the Wi-Fi iface?)}"
  if printf '%s' "$ps" | grep -qi 'on'; then
    echo "  >> POWER SAVE IS ON — this alone can make mDNS/SSDP drop and the device"
    echo "     'disappear' for other phones. Fix: ./scripts/setup-wifi-powersave.sh"
  fi
  iw dev "$WIFI_IFACE" link 2>/dev/null | sed -n 's/^/  /p' | grep -iE 'signal|bitrate|SSID' || true
else
  echo "  (iw not installed: sudo apt-get install -y iw)"
fi

# --- Is an AirPlay session active right now? ---------------------------------
section "Active AirPlay session"
sps_running="no"; pgrep -x shairport-sync >/dev/null 2>&1 && sps_running="yes"
echo "  shairport-sync running: ${sps_running}"
if have ss; then
  est="$(ss -tnp 2>/dev/null | grep -E 'ESTAB' | grep -E ':(7000|5000|3689|319|320)\b' || true)"
  if [[ -n "$est" ]]; then
    echo "  Established AirPlay/PTP connections (a phone is connected):"
    printf '%s\n' "$est" | sed 's/^/    /'
  else
    echo "  No established AirPlay connection seen right now."
    echo "  >> For a real result, RE-RUN THIS while one iPhone is actively streaming."
  fi
fi

# --- Does shairport still ADVERTISE while busy? (mDNS) ------------------------
section "AirPlay mDNS advertisement (now)"
if have avahi-browse; then
  ap="$(avahi-browse -atr --terminate 2>/dev/null | grep -iE '_airplay\._tcp|_raop\._tcp' || true)"
  if [[ -n "$ap" ]]; then
    echo "  Pi still advertises AirPlay over mDNS:"
    printf '%s\n' "$ap" | sed 's/^/    /' | head -n 12
    echo "  >> If the Pi advertises here but a 2nd phone still can't see it, the loss"
    echo "     is on the air (multicast dropped under load) — not shairport."
  else
    echo "  No _airplay/_raop mDNS records visible locally right now."
    echo "  >> If this is empty WHILE streaming, shairport/avahi stopped advertising."
  fi
else
  echo "  (avahi-utils not installed: sudo apt-get install -y avahi-utils)"
fi

# --- DLNA / SSDP discoverability --------------------------------------------
section "DLNA / SSDP (now)"
if have ss; then
  if ss -lunp 2>/dev/null | grep -qE ':1900\b'; then
    echo "  SSDP listener present on UDP 1900 (gmediarender is up)."
  else
    echo "  No UDP 1900 listener — DLNA renderer not running (or not bound here)."
  fi
fi
if have ip; then
  if ip maddr show 2>/dev/null | grep -qE '239\.255\.255\.250'; then
    echo "  Joined SSDP multicast group 239.255.255.250 (good)."
  else
    echo "  Not joined 239.255.255.250 (only matters when DLNA is running)."
  fi
  if ip maddr show 2>/dev/null | grep -qE '224\.0\.0\.251'; then
    echo "  Joined mDNS multicast group 224.0.0.251 (good)."
  else
    echo "  Not joined 224.0.0.251 — mDNS/AirPlay discovery would fail."
  fi
fi

# --- Takeover layer: is barge-in allowed in shairport-sync.conf? -------------
section "AirPlay takeover (sessioncontrol)"
SPS_CONF="/etc/shairport-sync.conf"
if [[ -r "$SPS_CONF" ]]; then
  if grep -qE '^[[:space:]]*allow_session_interruption[[:space:]]*=[[:space:]]*"yes"' "$SPS_CONF"; then
    echo "  allow_session_interruption = \"yes\"  -> a 2nd device CAN take over. Good."
  else
    echo "  allow_session_interruption is NOT \"yes\" -> a 2nd device gets BUSY and"
    echo "  cannot take over (HomePod-style barge-in disabled). Enable it with:"
    echo "      ./scripts/enable-airplay-takeover.sh"
  fi
else
  echo "  ($SPS_CONF not readable; run as a user who can read it, or with sudo)"
fi

# --- Verdict / next steps ----------------------------------------------------
section "What to conclude"
cat <<'EOF'
  Compare two runs: once with NO phone streaming, once WHILE a phone streams.

  * Device visible when idle, GONE for other phones while streaming, and BOTH
    AirPlay and DLNA vanish together  -> DISCOVERY layer (network/multicast).
    Fix: ./scripts/setup-wifi-powersave.sh ; prefer Ethernet for the Pi ;
    on the router disable AP/client isolation and IGMP snooping.

  * Device stays visible while streaming but a 2nd iPhone selecting it does
    nothing / says busy  -> TAKEOVER layer.
    Fix: ./scripts/enable-airplay-takeover.sh

  HomePod-style "newest device wins" needs BOTH fixed.
EOF
exit 0
