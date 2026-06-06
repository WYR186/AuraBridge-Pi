#!/usr/bin/env bash
set -euo pipefail

# enable-airplay-takeover.sh — make a newly-connecting AirPlay device INTERRUPT
# (take over) the current session instead of getting a "busy" signal, i.e. the
# HomePod-style "last device wins" behaviour at the CONNECTION level.
#
# Mechanism (verified against shairport-sync docs): shairport-sync, while playing,
# returns "busy" to other senders for sessioncontrol.session_timeout seconds
# (default 120). Setting sessioncontrol.allow_session_interruption = "yes" lets a
# new sender barge in. (CLI equivalent: shairport-sync --timeout=0.)
#
# This edits the EXISTING /etc/shairport-sync.conf in place (the installer only
# affects fresh installs) and restarts shairport-sync. Idempotent.
#
# NOTE: takeover only works if the device is also still DISCOVERABLE while busy.
# If a second phone cannot even SEE the device while one is streaming, fix that
# first: ./scripts/setup-wifi-powersave.sh and ./scripts/diagnose-discovery.sh.

SPS_CONF="${SPS_CONF:-/etc/shairport-sync.conf}"

log()  { printf '[takeover] %s\n' "$*"; }
warn() { printf '[takeover][WARN] %s\n' "$*" >&2; }
die()  { printf '[takeover][ERROR] %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] && SUDO="" || SUDO="sudo"

[[ -f "$SPS_CONF" ]] || die "$SPS_CONF not found. Run ./scripts/install-airplay2.sh first."

if $SUDO cp -a "$SPS_CONF" "${SPS_CONF}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null; then
  log "Backed up $SPS_CONF"
else
  warn "Could not back up $SPS_CONF (continuing)."
fi

if grep -qE '^[[:space:]]*allow_session_interruption' "$SPS_CONF"; then
  # Set any existing (possibly commented) key to "yes".
  $SUDO sed -i -E 's|^[[:space:]]*//?[[:space:]]*allow_session_interruption[[:space:]]*=.*|  allow_session_interruption = "yes";|' "$SPS_CONF"
  log "Updated existing allow_session_interruption -> \"yes\"."
elif grep -qE '^[[:space:]]*sessioncontrol[[:space:]]*=' "$SPS_CONF"; then
  # There is a sessioncontrol group but no key: insert the key after its '{'.
  $SUDO sed -i -E '/^[[:space:]]*sessioncontrol[[:space:]]*=/,/{/ s|{|{\n  allow_session_interruption = "yes";|' "$SPS_CONF"
  log "Added allow_session_interruption to existing sessioncontrol group."
else
  # No sessioncontrol group at all: append one.
  printf '\nsessioncontrol = {\n  allow_session_interruption = "yes";\n};\n' | $SUDO tee -a "$SPS_CONF" >/dev/null
  log "Appended a sessioncontrol group with allow_session_interruption = \"yes\"."
fi

echo "----- effective sessioncontrol in $SPS_CONF -----"
grep -nE 'sessioncontrol|allow_session_interruption' "$SPS_CONF" | sed 's/^/    /' || true
echo "--------------------------------------------------"

log "Restarting shairport-sync..."
if $SUDO systemctl restart shairport-sync 2>/dev/null; then
  sleep 1
  if [[ "$($SUDO systemctl is-active shairport-sync 2>/dev/null || echo unknown)" == "active" ]]; then
    log "shairport-sync is active."
  else
    warn "shairport-sync is not active after restart. Recent logs:"
    journalctl -u shairport-sync -n 30 --no-pager 2>/dev/null || true
    die "shairport-sync did not come back. Restore the backup conf if needed."
  fi
else
  warn "Could not restart shairport-sync via systemctl. Restart it manually."
fi

cat <<EOF

[takeover] Done. A second AirPlay device can now INTERRUPT/take over an active
[takeover] session (instead of seeing it busy). Test:
[takeover]   1. Stream from iPhone A.
[takeover]   2. On iPhone B, open the AirPlay picker and select "Aura Studio 3 AirPlay".
[takeover]   3. B should take over; A stops.
[takeover]
[takeover] If iPhone B cannot even SEE the device while A is streaming, that is the
[takeover] discovery layer, not this. Run:
[takeover]   ./scripts/setup-wifi-powersave.sh
[takeover]   ./scripts/diagnose-discovery.sh   # while A is streaming
EOF
