#!/usr/bin/env bash
set -euo pipefail

# setup-readonly.sh — Phase 7 (resilience): make the root filesystem READ-ONLY via
# Raspberry Pi OS OverlayFS so the Pi survives sudden power loss without rootfs
# corruption, while PRESERVING the small amount of state that must persist:
#   - BlueZ pairing data              /var/lib/bluetooth
#   - WirePlumber stream/route state  ~<user>/.local/state/wireplumber
#
# Why a loop-mounted ext4 image (NOT symlinks straight onto the boot FAT32):
#   The boot partition (/boot/firmware) is VFAT. VFAT cannot store the colon-named
#   MAC-address directories BlueZ uses (e.g. AA:BB:CC:..), and it drops POSIX
#   ownership/permissions that BlueZ and WirePlumber rely on. So instead we keep
#   ONE journaled ext4 image FILE on the boot partition, loop-mount it read-write
#   at a fixed mountpoint, move the two state dirs into it, and symlink the
#   originals back. ext4's journal keeps that small RW area power-loss safe while
#   the rest of the root is frozen read-only.
#
#     /boot/firmware/aurabridge_state.ext4   (FAT32 just holds this one file)
#       └─ loop-mounted at /mnt/persist  (ext4, RW, journaled)
#            ├─ bluetooth/    <-  /var/lib/bluetooth                    (symlink)
#            └─ wireplumber/  <-  /home/<user>/.local/state/wireplumber (symlink)
#
# Everything here is IDEMPOTENT and reversible:
#   - re-running re-asserts state and never double-moves data;
#   - scripts/toggle-rw.sh temporarily lifts the overlay for system updates;
#   - scripts/rollback-readonly.sh tears the whole thing back down.
#
# IMPORTANT: enabling OverlayFS only takes effect AFTER A REBOOT. This script does
# NOT reboot for you. It also does NOT make the boot partition read-only
# (enable_bootro is intentionally SKIPPED) because the ext4 state image lives
# there and must stay writable.
#
# Modes:
#   (default)       prepare persistence (image + mount + migrate) AND enable
#                   OverlayFS. Prompts before the overlay step (ASSUME_YES=1 skips).
#   --prepare-only  do everything EXCEPT enabling OverlayFS (stage the state image).
#   --status        report current state; change nothing.
#   --help
#
# Env:
#   PERSIST_MNT=/mnt/persist     mountpoint for the state image
#   STATE_IMAGE_MB=50            size of the ext4 image (MB)
#   BOOT_DIR=<auto>              boot partition holding the image (auto-detected)
#   TARGET_USER=<auto>           owner of the WirePlumber state (auto-detected)
#   ASSUME_YES=1                 skip the confirm before enabling OverlayFS

log()  { printf '[readonly] %s\n' "$*"; }
warn() { printf '[readonly][WARN] %s\n' "$*" >&2; }
die()  { printf '[readonly][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

MODE="setup"
case "${1:-}" in
  ""|setup)        MODE="setup" ;;
  --prepare-only)  MODE="prepare" ;;
  --status)        MODE="status" ;;
  -h|--help)
    grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *) die "Unknown argument '$1'. Use: (no arg) | --prepare-only | --status | --help" ;;
esac

SUDO=""
[[ "$(id -u)" -ne 0 ]] && SUDO="sudo"

# --- Resolve the boot partition (FAT32) that will hold the image -------------
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
STATE_IMAGE_MB="${STATE_IMAGE_MB:-50}"
IMAGE="${BOOT_DIR}/aurabridge_state.ext4"

# --- Resolve the normal (non-root) user whose WirePlumber state we persist ----
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

# --- Helpers -----------------------------------------------------------------
# 0 (true) if the RUNNING root is already a read-only overlay.
overlay_active_now() {
  if have raspi-config; then
    local v; v="$($SUDO raspi-config nonint get_overlay_now 2>/dev/null || echo 1)"
    [[ "$v" == "0" ]] && return 0
  fi
  findmnt -no FSTYPE / 2>/dev/null | grep -q overlay
}

is_persisted() {
  # 0 (true) if $1 is already a symlink into the persist mount.
  local link="$1" name="$2"
  [[ -L "$link" && "$(readlink "$link" 2>/dev/null)" == "${PERSIST_MNT}/${name}" ]]
}

ts_now() { date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown; }

# --- STATUS ------------------------------------------------------------------
print_status() {
  echo "=== AuraBridge read-only-root status ==="
  echo "boot partition : ${BOOT_DIR}"
  echo "state image    : ${IMAGE} $( [[ -f "$IMAGE" ]] && echo "(present)" || echo "(absent)" )"
  if mountpoint -q "$PERSIST_MNT" 2>/dev/null; then
    echo "persist mount  : ${PERSIST_MNT} (mounted)"
  else
    echo "persist mount  : ${PERSIST_MNT} (NOT mounted)"
  fi
  echo "target user    : ${TARGET_USER} (${TARGET_HOME})"
  if is_persisted "$BT_SRC" bluetooth; then
    echo "bluetooth state: ${BT_SRC} -> ${PERSIST_MNT}/bluetooth (symlinked)"
  else
    echo "bluetooth state: ${BT_SRC} (NOT yet persisted)"
  fi
  if is_persisted "$WP_SRC" wireplumber; then
    echo "wireplumber st.: ${WP_SRC} -> ${PERSIST_MNT}/wireplumber (symlinked)"
  else
    echo "wireplumber st.: ${WP_SRC} (NOT yet persisted)"
  fi
  if overlay_active_now; then
    echo "overlayfs      : ACTIVE now (root is read-only)"
  else
    echo "overlayfs      : not active on the running system"
  fi
  echo "fstab entry    : $(grep -qsE "[[:space:]]${PERSIST_MNT}[[:space:]]" /etc/fstab && echo present || echo absent)"
}

# --- Create the ext4 image + fstab entry + mount -----------------------------
ensure_image_mounted() {
  [[ -d "$BOOT_DIR" ]] || die "Boot partition '${BOOT_DIR}' not found. Set BOOT_DIR=... and re-run."
  have mkfs.ext4 || die "mkfs.ext4 not found. Install e2fsprogs: sudo apt-get install -y e2fsprogs"

  if [[ -f "$IMAGE" ]]; then
    log "ext4 state image already exists: ${IMAGE}"
  else
    log "Creating ${STATE_IMAGE_MB}MB ext4 state image: ${IMAGE}"
    $SUDO dd if=/dev/zero of="$IMAGE" bs=1M count="$STATE_IMAGE_MB" status=none
    $SUDO mkfs.ext4 -F -q -L AURASTATE -m 0 "$IMAGE"
  fi

  $SUDO mkdir -p "$PERSIST_MNT"

  # nofail: a missing/damaged image must NOT drop the Pi into an emergency shell.
  local fstab_line="${IMAGE}  ${PERSIST_MNT}  ext4  loop,defaults,nofail  0  0"
  if grep -qsE "[[:space:]]${PERSIST_MNT}[[:space:]]" /etc/fstab; then
    log "/etc/fstab already has an entry for ${PERSIST_MNT} (leaving as-is)."
  else
    local ts; ts="$(ts_now)"
    $SUDO cp -a /etc/fstab "/etc/fstab.bak.${ts}"
    printf '%s\n' "$fstab_line" | $SUDO tee -a /etc/fstab >/dev/null
    log "Added /etc/fstab entry (backed up to /etc/fstab.bak.${ts}):"
    log "  ${fstab_line}"
  fi

  if mountpoint -q "$PERSIST_MNT" 2>/dev/null; then
    log "${PERSIST_MNT} already mounted."
  else
    log "Mounting ${PERSIST_MNT}..."
    $SUDO mount "$PERSIST_MNT" 2>/dev/null || $SUDO mount -a
    mountpoint -q "$PERSIST_MNT" 2>/dev/null \
      || die "Failed to mount ${PERSIST_MNT}. Check /etc/fstab and ${IMAGE}."
  fi
}

# --- Move one state dir into the persist mount and symlink it back ------------
# migrate_one <persist-subdir> <original-path> <owner> <mode>
migrate_one() {
  local name="$1" src="$2" owner="$3" mode="$4"
  local dst="${PERSIST_MNT}/${name}"

  if is_persisted "$src" "$name"; then
    log "${name}: already symlinked -> ${dst} (ok)."
    [[ -d "$dst" ]] || { $SUDO mkdir -p "$dst"; $SUDO chown -R "$owner" "$dst" 2>/dev/null || true; $SUDO chmod "$mode" "$dst" 2>/dev/null || true; }
    return
  fi
  if [[ -L "$src" ]]; then
    warn "${name}: ${src} is a symlink to '$(readlink "$src" 2>/dev/null)' (not ours). Skipping; resolve manually."
    return
  fi

  if [[ -e "$dst" ]]; then
    if [[ -d "$src" ]]; then
      warn "${name}: both ${src} (real dir) and ${dst} (persist) exist."
      warn "  Not overwriting persisted data. Merge manually, then re-run. Skipping ${name}."
      return
    fi
    log "${name}: persisted copy already at ${dst}; (re)creating symlink."
  else
    if [[ -d "$src" ]]; then
      log "${name}: moving ${src} -> ${dst}"
      $SUDO mv "$src" "$dst"
    else
      log "${name}: ${src} absent; creating empty persisted dir ${dst}"
      $SUDO mkdir -p "$dst"
    fi
    $SUDO chown -R "$owner" "$dst" 2>/dev/null || true
    $SUDO chmod "$mode" "$dst" 2>/dev/null || true
  fi

  $SUDO mkdir -p "$(dirname "$src")"
  $SUDO ln -s "$dst" "$src"
  $SUDO chown -h "$owner" "$src" 2>/dev/null || true
  log "${name}: symlinked ${src} -> ${dst}"
}

migrate_state() {
  # Bluetooth: stop the daemon first so it is not writing while we move its dir.
  if have systemctl; then
    log "Stopping bluetooth.service before migrating its state (best-effort)..."
    $SUDO systemctl stop bluetooth.service 2>/dev/null || true
  fi
  migrate_one bluetooth "$BT_SRC" "root:root" 700

  # WirePlumber: keep the user's ownership all the way down to the symlink.
  $SUDO mkdir -p "${TARGET_HOME}/.local/state"
  $SUDO chown "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.local" "${TARGET_HOME}/.local/state" 2>/dev/null || true
  migrate_one wireplumber "$WP_SRC" "${TARGET_USER}:${TARGET_USER}" 755
}

# --- Enable OverlayFS (effective after reboot) -------------------------------
enable_overlay() {
  have raspi-config || die "raspi-config not found; cannot enable OverlayFS automatically."
  if overlay_active_now; then
    log "OverlayFS is already ACTIVE on the running system. Nothing to enable."
    return
  fi
  if [[ "${ASSUME_YES:-0}" != "1" && -t 0 ]]; then
    echo
    warn "About to enable a READ-ONLY overlay root via 'raspi-config nonint enable_overlayfs'."
    warn "It takes effect on the NEXT REBOOT. After that the root filesystem is frozen;"
    warn "use ./scripts/toggle-rw.sh to make it writable for updates."
    local yn; read -r -p "Enable OverlayFS now? [y/N]: " yn || yn=""
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
      warn "Skipped enabling OverlayFS. Persistence is set up; run again (or --prepare-only) later."
      return
    fi
  fi
  log "Enabling OverlayFS (raspi-config nonint enable_overlayfs)..."
  $SUDO raspi-config nonint enable_overlayfs
  log "OverlayFS enabled. NOTE: enable_bootro is intentionally NOT run (boot stays writable)."
  log "*** A REBOOT is required to activate the read-only root. ***"
}

# --- Main --------------------------------------------------------------------
if [[ "$MODE" == "status" ]]; then
  print_status
  exit 0
fi

# Both setup and prepare need a writable root to move dirs and edit /etc/fstab.
if overlay_active_now; then
  if is_persisted "$BT_SRC" bluetooth && is_persisted "$WP_SRC" wireplumber; then
    log "Root is read-only (OverlayFS active) and state is already persisted. Nothing to do."
    print_status
    exit 0
  fi
  die "Root is read-only (OverlayFS active) but state is not fully persisted.
Lift the overlay first:  ./scripts/toggle-rw.sh rw  &&  sudo reboot
then re-run this script, then re-enable with:  ./scripts/toggle-rw.sh ro && sudo reboot"
fi

log "Boot partition: ${BOOT_DIR}   image: ${IMAGE}   mount: ${PERSIST_MNT}"
log "Persisting WirePlumber state for user: ${TARGET_USER} (${TARGET_HOME})"
echo
ensure_image_mounted
migrate_state
echo
print_status
echo

if [[ "$MODE" == "prepare" ]]; then
  log "Persistence prepared (--prepare-only). OverlayFS was NOT enabled."
  log "Enable it later with:  ./scripts/setup-readonly.sh   (or raspi-config)."
else
  enable_overlay
fi

echo
log "Done. Bluetooth pairing and WirePlumber state now live on the journaled"
log "ext4 image and survive power loss. Reboot to apply any OverlayFS change."
log "Roll a temporary writable root for updates:  ./scripts/toggle-rw.sh rw"
log "Full teardown:                               ./scripts/rollback-readonly.sh --status"
