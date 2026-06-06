#!/usr/bin/env bash
set -euo pipefail

# check-dlna-discovery.sh — read-only self-check for "why can't my phone see the
# DLNA speaker?". DLNA/UPnP discovery uses SSDP over MULTICAST UDP 1900
# (239.255.255.250) plus an HTTP/SOAP control port. This is NOT mDNS/Avahi, so
# the AirPlay discovery stack does not help here. The single most common failure
# is a network one (phone and Pi on different subnets, or the AP blocking
# client-to-client / multicast traffic), not the renderer itself.
#
# This script changes nothing. It reports what it can see and prints the usual
# culprits. Exit code: 0 on PASS/WARN, non-zero only if the renderer is clearly
# not running / not listening (a hard FAIL the phone cannot work around).
#
# See docs/dlna.md ("Discovery / 发现排查").

SSDP_MCAST="239.255.255.250"
SSDP_PORT="1900"
HTTP_PORT="${DLNA_HTTP_PORT:-49494}"   # must match gmrender.service --port
FRIENDLY="${DLNA_NAME:-Aura Studio 3 DLNA}"

have()    { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n===== %s =====\n' "$*"; }

renderer_ok=0
ssdp_ok=0
http_ok=0

# ---------------------------------------------------------------------------
section "Pi network address(es)"
# ---------------------------------------------------------------------------
ips=""
if have ip; then
  ips="$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $2" "$4}')"
elif have hostname; then
  ips="$(hostname -I 2>/dev/null)"
fi
if [[ -n "$ips" ]]; then
  echo "$ips"
  if printf '%s\n' "$ips" | grep -q '192\.168\.50\.'; then
    echo ">> On the 192.168.50.x subnet. The phone MUST be on this same subnet."
  else
    echo ">> NOTE: not on 192.168.50.x here. Whatever subnet this is, the phone has"
    echo "   to share it (same Wi-Fi/LAN, no guest network, no VLAN split)."
  fi
else
  echo "(could not determine IP — install iproute2 / net-tools)"
fi

# ---------------------------------------------------------------------------
section "DLNA renderer process (gmediarender)"
# ---------------------------------------------------------------------------
if have systemctl && systemctl --user is-active gmrender.service >/dev/null 2>&1; then
  echo "gmrender.service is ACTIVE (user service)."
  renderer_ok=1
elif pgrep -x gmediarender >/dev/null 2>&1; then
  echo "gmediarender process is running (not via the user unit)."
  renderer_ok=1
else
  echo "gmediarender is NOT running."
  echo "  Start it: systemctl --user start gmrender.service"
  echo "  (It is gated behind a verified Safe Sink — see docs/safe-sink.md.)"
fi

# ---------------------------------------------------------------------------
section "Listening sockets (SSDP UDP ${SSDP_PORT} + HTTP/SOAP ${HTTP_PORT})"
# ---------------------------------------------------------------------------
if have ss; then
  echo "--- UDP ---"
  ss -lunp 2>/dev/null | grep -E ":(${SSDP_PORT})\b" && ssdp_ok=1 \
    || echo "(no listener on UDP ${SSDP_PORT} — SSDP discovery will not work)"
  echo "--- TCP ---"
  ss -ltnp 2>/dev/null | grep -E ":(${HTTP_PORT})\b" && http_ok=1 \
    || echo "(no listener on TCP ${HTTP_PORT} — is --port ${HTTP_PORT} set in gmrender.service?)"
elif have netstat; then
  netstat -lnp 2>/dev/null | grep -E ":(${SSDP_PORT}|${HTTP_PORT})\b" || echo "(no SSDP/HTTP listeners found)"
  netstat -lnp 2>/dev/null | grep -qE ":${SSDP_PORT}\b"  && ssdp_ok=1 || true
  netstat -lnp 2>/dev/null | grep -qE ":${HTTP_PORT}\b" && http_ok=1 || true
else
  echo "(neither 'ss' nor 'netstat' available — install iproute2 or net-tools)"
fi

# ---------------------------------------------------------------------------
section "SSDP multicast group membership (${SSDP_MCAST})"
# ---------------------------------------------------------------------------
if have ip; then
  if ip maddr show 2>/dev/null | grep -q "$SSDP_MCAST"; then
    echo "Host has JOINED the SSDP multicast group ${SSDP_MCAST}. Good."
    ip maddr show 2>/dev/null | grep -B2 "$SSDP_MCAST" | grep -E '^[0-9]+:' || true
  else
    echo "Host has NOT joined ${SSDP_MCAST} yet."
    echo "  This usually appears only once the renderer is running and bound."
  fi
else
  echo "(ip not available — cannot check multicast membership)"
fi

# ---------------------------------------------------------------------------
section "Local firewall (should NOT block SSDP/HTTP)"
# ---------------------------------------------------------------------------
fw_seen=0
if have ufw && sudo -n ufw status >/dev/null 2>&1; then
  fw_seen=1; echo "ufw active — ensure UDP ${SSDP_PORT} and TCP ${HTTP_PORT} are allowed on the LAN."
fi
if have nft && sudo -n nft list ruleset >/dev/null 2>&1; then
  fw_seen=1; echo "nftables ruleset present — ensure it does not drop multicast/UDP ${SSDP_PORT}."
fi
[[ "$fw_seen" -eq 0 ]] && echo "No active host firewall detected (default AuraBridge state). OK."

# ---------------------------------------------------------------------------
section "SUMMARY"
# ---------------------------------------------------------------------------
echo "Renderer running        : $([[ $renderer_ok -eq 1 ]] && echo yes || echo NO)"
echo "SSDP UDP ${SSDP_PORT} listening : $([[ $ssdp_ok -eq 1 ]] && echo yes || echo no)"
echo "HTTP ${HTTP_PORT} listening    : $([[ $http_ok -eq 1 ]] && echo yes || echo no)"
echo "Advertised as           : \"${FRIENDLY}\""
echo
echo "If the renderer is up but a phone still can't see it, the cause is almost"
echo "always the NETWORK, not the Pi:"
echo "  1. Phone and Pi on the SAME subnet/Wi-Fi (not a guest network, not a"
echo "     separate 2.4/5 GHz SSID isolated from each other)."
echo "  2. Router 'AP isolation' / 'client isolation' OFF — it blocks phone↔Pi."
echo "  3. 'IGMP snooping' / multicast filtering on the AP must allow ${SSDP_MCAST}."
echo "  4. If the Pi is on Ethernet and the phone on Wi-Fi, confirm they bridge."
echo "  5. Reliable client apps: BubbleUPnP, Hi-Fi Cast, VLC. Native 投屏 /"
echo "     Smart View menus may not list a generic DLNA renderer (see docs/dlna.md)."

if [[ "$renderer_ok" -eq 1 ]]; then
  echo
  echo "RESULT: renderer is running. If discovery still fails, work through 1–5 above."
  exit 0
fi
echo
echo "RESULT: FAIL — the DLNA renderer is not running, so nothing can discover it."
exit 1
