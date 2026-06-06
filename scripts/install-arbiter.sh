#!/usr/bin/env bash
set -euo pipefail

# install-arbiter.sh — Phase 7: install the AuraBridge source arbiter as a USER
# systemd service so wireless sources do barge-in (newest source wins the
# speaker) instead of mixing on top of each other.
#
# The arbiter only mutes the displaced source by default; protocol-level Stop is
# opt-in because it can make AirPlay/DLNA sender UIs look disconnected. It NEVER
# raises volume, so it does not affect the DLNA/Safe-Sink gate. See
# docs/source-arbiter.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
USER_UNIT_DIR="$HOME/.config/systemd/user"
UNIT="aurabridge-arbiter.service"
ENABLE_NOW=0

log()  { printf '[arbiter] %s\n' "$*"; }
warn() { printf '[arbiter][WARN] %s\n' "$*" >&2; }
die()  { printf '[arbiter][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

case "${1:-}" in
  ""|--install-only) ENABLE_NOW=0 ;;
  --enable) ENABLE_NOW=1 ;;
  -h|--help)
    cat <<EOF
Usage: ./scripts/install-arbiter.sh [--install-only|--enable]

  --install-only   Install the user unit but do not enable/start it (default).
  --enable         Install, enable, and start the user unit.

The arbiter is mute-only by default. To opt into protocol-level Stop, edit the
user unit environment to AURABRIDGE_ARBITER_PROTOCOL_STOP=1 and re-test.
EOF
    exit 0 ;;
  *) die "Unknown argument '$1'. Use --install-only, --enable, or --help." ;;
esac

[[ "$(id -u)" -eq 0 ]] && die "Do not run as root. The arbiter is a USER service so it shares your pipewire-pulse session. Re-run as the normal user."

have pactl || warn "pactl not found — install pipewire-pulse (setup-pipewire.sh). The arbiter needs it to see and mute sources."
have curl  || warn "curl not found — DLNA protocol-level Stop will be unavailable (the arbiter will still mute DLNA). Install: sudo apt-get install -y curl"
have dbus-send || warn "dbus-send not found — AirPlay protocol-level Stop will be unavailable (the arbiter will still mute AirPlay). Install: sudo apt-get install -y dbus"

[[ -f "$REPO_ROOT/systemd/$UNIT" ]] || die "systemd/$UNIT missing from the repo."
[[ -x "$REPO_ROOT/scripts/source-arbiter.sh" ]] || chmod +x "$REPO_ROOT/scripts/source-arbiter.sh" 2>/dev/null || true

mkdir -p "$USER_UNIT_DIR"
install -m 0644 "$REPO_ROOT/systemd/$UNIT" "$USER_UNIT_DIR/$UNIT"
log "Installed user unit: $USER_UNIT_DIR/$UNIT"

systemctl --user daemon-reload 2>/dev/null || warn "Could not run 'systemctl --user daemon-reload'."

# Keep it running across logout/reboot like the other user services.
if have loginctl; then
  loginctl enable-linger "$USER" >/dev/null 2>&1 || warn "Could not enable linger (arbiter may not run when logged out)."
fi

if [[ "$ENABLE_NOW" == "1" ]] && systemctl --user enable --now "$UNIT" 2>/dev/null; then
  log "Arbiter enabled and started."
elif [[ "$ENABLE_NOW" == "1" ]]; then
  warn "Could not enable/start the arbiter via 'systemctl --user'. Start it manually:"
  warn "  systemctl --user enable --now $UNIT"
else
  log "Arbiter installed but left disabled/stopped by default."
fi

cat <<EOF

[arbiter] Source arbiter installed (policy: barge-in — newest wireless source wins).
[arbiter] All protocols stay discoverable at the same time; only PLAYBACK is arbitrated.
[arbiter] Default mode is mute-only; protocol-level Stop is opt-in.

  Status:        systemctl --user status $UNIT
  Live log:      journalctl --user -u $UNIT -f
  Start now:     systemctl --user start $UNIT
  Stop now:      systemctl --user stop $UNIT
  Disable:       systemctl --user disable --now $UNIT
  Unmute all:    ./scripts/source-arbiter.sh --reset

[arbiter] To opt into protocol Stop later, set AURABRIDGE_ARBITER_PROTOCOL_STOP=1
[arbiter] in the user unit and re-test AirPlay/DLNA sender behaviour carefully.
EOF
