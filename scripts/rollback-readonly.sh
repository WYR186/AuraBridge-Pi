#!/usr/bin/env bash
set -euo pipefail

# rollback-readonly.sh — FULL teardown of the read-only/OverlayFS + persistence
# setup created by scripts/setup-readonly.sh. Because disabling OverlayFS only
# takes effect after a reboot, teardown is TWO phases around one reboot:
#
#   Phase 1 (root still read-only):     ./scripts/rollback-readonly.sh --disable-overlay
#       Runs raspi-config nonint disable_overlayfs, then you REBOOT.
#
#   Phase 2 (after reboot, root writable):  ./scripts/rollback-readonly.sh --restore
#       Removes the symlinks, copies the state back from ${PERSIST_MNT} to the
#       original locations, drops the /etc/fstab entry, unmounts, and deletes the
#       ext4 image. After this the Pi is back to a plain read-write root.
#
#   --status   (default)   report what remains and which phase to run next.
#   --help
#
# Env (must match what setup-readonly.sh used):
#   PERSIST_MNT=/mnt/persist     BOOT_DIR=<auto>     TARGET_USER=<auto>
#
# All steps are idempotent: re-running a completed phase is a safe no-op.

log()  { printf '[rollback-ro] %s\n' "$*"; }
warn() { printf '[rollback-ro][WARN] %s\n' "$*" >&2; }
die()  { printf '[rollback-ro][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

MODE="status"
case "${1:-}" in
  ""|--status)       MODE="status" ;;
  --disable-overlay) MODE="disable" ;;
  --restore)         MODE="restore" ;;
  -h|--help)
    grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *) die "Unknown argument '$1'. Use: --status | --disable-overlay | --restore | --help" ;;
esac

SUDO=""
[[ "$(id -u)" -ne 0 ]] && SUDO="sudo"

# --- Resolve the same locations setup-readonly.sh used -----------------------
if [[ -z "${BOOT_DIR:-}" ]]; then
  BOOT_DIR=""
  for d in /boot/firmware /boot; do
    if [[ -d "$d" ]] && mountpoint -q "$d" 2>/dev/null; then BOOT_DIR="$d"; break; fi
  done
  if [[ -z "$BOOT_DIR" ]]; then
    [[ -d /boot/firmware ]] && BOOT_DIR="/boot/firmware" || BOOT_DIR="/boot"
  fi
fi
PERSIST_MNT="${PERSIST_MNT:-/mnt/persist}"
IMAGE="${BOOT_DIR}/aurabridge_state.ext4"

TARGET_USER="${TARGET_USER:-${SUDO_USER:-}}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
  TARGET_USER="$(id -un 2>/dev/null || echo root)"
fi
if [[ "$TARGET_USER" == "root" ]]; then
  for h in /home/*; do
    [[ -d "$h" ]] || continue
    TARGET_USER="$(basename "$h")"; break
  done
fi
TARGET_HOME="$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6 || true)"
[[ -n "$TARGET_HOME" ]] || TARGET_HOME="/home/$TARGET_USER"

BT_SRC="/var/lib/bluetooth"
WP_SRC="${TARGET_HOME}/.local/state/wireplumber"

overlay_active_now() {
  if have raspi-config; then
    local v; v="$($SUDO raspi-config nonint get_overlay_now 2>/dev/null || echo 1)"
    [[ "$v" == "0" ]] && return 0
  fi
  findmnt -no FSTYPE / 2>/dev/null | grep -q overlay
}

ts_now() { date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown; }

print_status() {
  echo "=== rollback-readonly status ==="
  echo "boot partition : ${BOOT_DIR}"
  echo "state image    : ${IMAGE} $( [[ -f "$IMAGE" ]] && echo "(present)" || echo "(absent)" )"
  echo "persist mount  : ${PERSIST_MNT} $( mountpoint -q "$PERSIST_MNT" 2>/dev/null && echo "(mounted)" || echo "(not mounted)" )"
  echo "bluetooth link : $( [[ -L "$BT_SRC" ]] && echo "${BT_SRC} -> $(readlink "$BT_SRC")" || echo "${BT_SRC} (not a symlink)" )"
  echo "wireplumber lk : $( [[ -L "$WP_SRC" ]] && echo "${WP_SRC} -> $(readlink "$WP_SRC")" || echo "${WP_SRC} (not a symlink)" )"
  echo "fstab entry    : $( grep -qsE "[[:space:]]${PERSIST_MNT}[[:space:]]" /etc/fstab && echo present || echo absent )"
  if overlay_active_now; then
    echo "overlayfs      : ACTIVE now (root read-only)"
    echo
    echo "Next: ./scripts/rollback-readonly.sh --disable-overlay   (then reboot)"
  else
    echo "overlayfs      : not active (root writable)"
    echo
    echo "Next: ./scripts/rollback-readonly.sh --restore"
  fi
}

# restore_one <persist-subdir> <original-link-path> <owner> <mode>
restore_one() {
  local name="$1" link="$2" owner="$3" mode="$4" ts="$5"
  local src="${PERSIST_MNT}/${name}"

  if [[ -L "$link" ]]; then
    $SUDO rm -f "$link"
    log "${name}: removed symlink ${link}"
  elif [[ -e "$link" ]]; then
    warn "${name}: ${link} exists and is NOT our symlink — backing it up to ${link}.pre-rollback.${ts}"
    $SUDO mv "$link" "${link}.pre-rollback.${ts}"
  fi

  if [[ -d "$src" ]]; then
    log "${name}: copying state back ${src} -> ${link}"
    $SUDO mkdir -p "$(dirname "$link")"
    $SUDO cp -a "$src" "$link"
    $SUDO chown -R "$owner" "$link" 2>/dev/null || true
    $SUDO chmod "$mode" "$link" 2>/dev/null || true
  else
    warn "${name}: no persisted data at ${src}; nothing to copy back."
  fi
}

case "$MODE" in
  status)
    print_status ;;

  disable)
    have raspi-config || die "raspi-config not found; cannot disable OverlayFS."
    if ! overlay_active_now; then
      log "OverlayFS is not active on the running system; nothing to disable."
    fi
    log "Disabling OverlayFS (raspi-config nonint disable_overlayfs)..."
    $SUDO raspi-config nonint disable_overlayfs
    log "Done."
    warn "*** Reboot now: sudo reboot ***"
    warn "After reboot, finish teardown with: ./scripts/rollback-readonly.sh --restore"
    ;;

  restore)
    if overlay_active_now; then
      die "Root is still read-only (OverlayFS active). Run --disable-overlay and reboot first,
then re-run --restore on the writable root."
    fi
    ts="$(ts_now)"
    log "Restoring state from ${PERSIST_MNT} back to the live filesystem..."
    # Stop the daemon that holds /var/lib/bluetooth before swapping its dir back.
    if have systemctl; then $SUDO systemctl stop bluetooth.service 2>/dev/null || true; fi

    restore_one bluetooth   "$BT_SRC" "root:root"                    700 "$ts"
    restore_one wireplumber "$WP_SRC" "${TARGET_USER}:${TARGET_USER}" 755 "$ts"

    # Drop the /etc/fstab entry (back it up first).
    if grep -qsE "[[:space:]]${PERSIST_MNT}[[:space:]]" /etc/fstab; then
      $SUDO cp -a /etc/fstab "/etc/fstab.bak.${ts}"
      local_tmp="$(mktemp)"
      grep -vE "[[:space:]]${PERSIST_MNT}[[:space:]]" /etc/fstab > "$local_tmp" || true
      $SUDO cp "$local_tmp" /etc/fstab
      rm -f "$local_tmp"
      log "Removed ${PERSIST_MNT} entry from /etc/fstab (backup: /etc/fstab.bak.${ts})."
    else
      log "No ${PERSIST_MNT} entry in /etc/fstab."
    fi

    # Unmount and delete the image.
    if mountpoint -q "$PERSIST_MNT" 2>/dev/null; then
      $SUDO umount "$PERSIST_MNT" 2>/dev/null \
        || warn "Could not unmount ${PERSIST_MNT} (in use?). Unmount manually, then delete ${IMAGE}."
    fi
    if ! mountpoint -q "$PERSIST_MNT" 2>/dev/null && [[ -f "$IMAGE" ]]; then
      $SUDO rm -f "$IMAGE"
      log "Deleted ${IMAGE}."
    elif [[ -f "$IMAGE" ]]; then
      warn "Left ${IMAGE} in place because ${PERSIST_MNT} is still mounted."
    fi

    echo
    log "Teardown complete. Root is a plain read-write filesystem again."
    log "Bluetooth + WirePlumber state are back in their original locations."
    ;;
esac
