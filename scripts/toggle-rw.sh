#!/usr/bin/env bash
set -euo pipefail

# toggle-rw.sh — temporarily switch the OverlayFS root between READ-ONLY and
# READ-WRITE for system updates, WITHOUT tearing down the persistence image set
# up by scripts/setup-readonly.sh. Only the root overlay is toggled; the ext4
# state image, its mount, and the symlinks are left untouched.
#
# Every change here is applied by raspi-config to the boot config and only takes
# effect AFTER A REBOOT. This script never reboots for you.
#
# Usage:
#   toggle-rw.sh status   (default)   show whether the root is RO/RW right now
#   toggle-rw.sh rw                   disable overlay -> WRITABLE root next boot
#   toggle-rw.sh ro                   enable  overlay -> READ-ONLY root next boot
#   toggle-rw.sh --help
#
# Typical system-update flow:
#   ./scripts/toggle-rw.sh rw && sudo reboot      # boot writable
#   sudo apt-get update && sudo apt-get full-upgrade
#   ./scripts/toggle-rw.sh ro && sudo reboot      # re-freeze read-only

log()  { printf '[toggle-rw] %s\n' "$*"; }
warn() { printf '[toggle-rw][WARN] %s\n' "$*" >&2; }
die()  { printf '[toggle-rw][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

ACTION="status"
case "${1:-}" in
  ""|status)     ACTION="status" ;;
  rw|--rw|off)   ACTION="rw" ;;
  ro|--ro|on)    ACTION="ro" ;;
  -h|--help)
    grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *) die "Unknown argument '$1'. Use: status | rw | ro | --help" ;;
esac

SUDO=""
[[ "$(id -u)" -ne 0 ]] && SUDO="sudo"

have raspi-config || die "raspi-config not found (need Raspberry Pi OS)."

overlay_active_now() {
  local v; v="$($SUDO raspi-config nonint get_overlay_now 2>/dev/null || echo 1)"
  [[ "$v" == "0" ]]
}

root_mount_state() {
  local opts; opts="$(findmnt -no OPTIONS / 2>/dev/null || echo "")"
  case ",${opts}," in
    *,ro,*) echo "read-only" ;;
    *)      echo "read-write" ;;
  esac
}

print_status() {
  echo "=== OverlayFS / root read-write status ==="
  if overlay_active_now; then
    echo "running root : READ-ONLY (OverlayFS active; changes are discarded on reboot)"
  else
    echo "running root : not overlaid (changes persist normally)"
  fi
  echo "mount options: / is currently $(root_mount_state)"
  echo
  echo "To update the system:  ./scripts/toggle-rw.sh rw && sudo reboot"
  echo "To re-freeze:          ./scripts/toggle-rw.sh ro && sudo reboot"
}

case "$ACTION" in
  status)
    print_status ;;
  rw)
    if ! overlay_active_now; then
      log "OverlayFS is not active right now; nothing to disable."
    fi
    log "Disabling OverlayFS (root will be WRITABLE after reboot)..."
    $SUDO raspi-config nonint disable_overlayfs
    log "Done. The persistence image/symlinks are untouched."
    warn "*** Reboot required: sudo reboot ***  (then run your apt updates)"
    ;;
  ro)
    if overlay_active_now; then
      log "OverlayFS already active on the running system; re-asserting config."
    fi
    log "Enabling OverlayFS (root will be READ-ONLY after reboot)..."
    $SUDO raspi-config nonint enable_overlayfs
    log "Done."
    warn "*** Reboot required: sudo reboot ***"
    ;;
esac
