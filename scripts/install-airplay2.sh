#!/usr/bin/env bash
set -euo pipefail

# install-airplay2.sh — Phase 2: build & install NQPTP and Shairport Sync with
# AirPlay 2 support and the PulseAudio backend (through pipewire-pulse).
#
# Key rules (from PROJECT_OVERVIEW_2_2.md):
#   - Use the PulseAudio backend, NOT the native PipeWire backend, for the MVP.
#   - './configure --help' is the source of truth for the exact PulseAudio flag.
#   - Never route directly to ALSA hw:/plughw: devices.
#   - Device name: "Aura Studio 3 AirPlay".

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${AURABRIDGE_BUILD_DIR:-$HOME/aurabridge-build}"
AIRPLAY_NAME="${AIRPLAY_NAME:-Aura Studio 3 AirPlay}"
NQPTP_REPO="${NQPTP_REPO:-https://github.com/mikebrady/nqptp.git}"
SPS_REPO="${SPS_REPO:-https://github.com/mikebrady/shairport-sync.git}"

log()  { printf '[airplay2] %s\n' "$*"; }
warn() { printf '[airplay2][WARN] %s\n' "$*" >&2; }
die()  { printf '[airplay2][ERROR] %s\n' "$*" >&2; exit 1; }

if [[ "$(id -u)" -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi
command -v apt-get >/dev/null 2>&1 || die "apt-get not found (need Raspberry Pi OS / Debian)."
command -v git     >/dev/null 2>&1 || die "git not found — run ./scripts/setup-base.sh first."

# --- Verify PipeWire + pipewire-pulse are present ----------------------------
log "Verifying PipeWire and pipewire-pulse are available..."
command -v pipewire >/dev/null 2>&1 || warn "pipewire not found — run ./scripts/setup-pipewire.sh first."
if command -v pactl >/dev/null 2>&1; then
  if pactl info 2>/dev/null | grep -qi 'PulseAudio (on PipeWire'; then
    log "pipewire-pulse confirmed (pactl info reports PipeWire)."
  else
    warn "pactl reachable but did not confirm pipewire-pulse. Ensure pipewire-pulse is running."
  fi
else
  warn "pactl not found — install pulseaudio-utils (setup-pipewire.sh does this)."
fi

# --- Build dependencies ------------------------------------------------------
log "Installing build dependencies for NQPTP and Shairport Sync (AirPlay 2 + PulseAudio)..."
$SUDO apt-get update
$SUDO apt-get install -y \
  build-essential git autoconf automake libtool \
  libpopt-dev libconfig-dev libasound2-dev \
  libavahi-client-dev libssl-dev libsoxr-dev \
  libplist-dev libsodium-dev libavutil-dev libavcodec-dev libavformat-dev \
  uuid-dev libgcrypt20-dev xxd libpulse-dev libdbus-1-dev

mkdir -p "$BUILD_DIR"

# --- Helper: clone or update a git repo --------------------------------------
clone_or_update() {
  local repo="$1" dir="$2"
  if [[ -d "$dir/.git" ]]; then
    log "Updating $(basename "$dir") (git pull)..."
    git -C "$dir" pull --ff-only || warn "git pull failed for $dir (continuing with existing checkout)."
  else
    log "Cloning $(basename "$dir")..."
    git clone "$repo" "$dir"
  fi
}

# ===== NQPTP =================================================================
clone_or_update "$NQPTP_REPO" "$BUILD_DIR/nqptp"
log "Building NQPTP..."
(
  cd "$BUILD_DIR/nqptp"
  autoreconf -fi
  ./configure --with-systemd-startup
  make
  $SUDO make install
)
log "Enabling and starting nqptp..."
$SUDO systemctl enable --now nqptp 2>/dev/null || warn "Could not enable/start nqptp via systemd."

# ===== Shairport Sync ========================================================
clone_or_update "$SPS_REPO" "$BUILD_DIR/shairport-sync"
cd "$BUILD_DIR/shairport-sync"
autoreconf -fi

# Per the spec, inspect configure options before choosing flags.
log "Inspecting ./configure --help for PulseAudio and AirPlay options..."
CONFIG_HELP="$(./configure --help 2>/dev/null || true)"
echo "----- ./configure --help | grep -i pulse -----"
printf '%s\n' "$CONFIG_HELP" | grep -i pulse || echo "(no 'pulse' lines found)"
echo "----- ./configure --help | grep -i airplay -----"
printf '%s\n' "$CONFIG_HELP" | grep -i airplay || echo "(no 'airplay' lines found)"
echo "-----------------------------------------------"

# Determine the PulseAudio backend flag from configure --help (source of truth).
PA_FLAG=""
if printf '%s\n' "$CONFIG_HELP" | grep -q -- '--with-pa'; then
  PA_FLAG="--with-pa"
else
  PA_FLAG="$(printf '%s\n' "$CONFIG_HELP" | grep -oiE -- '--with-[a-z0-9-]*(pulse|pa)[a-z0-9-]*' | head -n1 || true)"
fi
[[ -n "$PA_FLAG" ]] || die "Could not find a PulseAudio backend flag in ./configure --help.
Refusing to silently fall back to the native PipeWire backend (not the MVP default).
Inspect the output above and set the correct flag, then re-run."
log "Using PulseAudio backend flag: ${PA_FLAG}"

# Only add --with-systemd-startup if this version supports it.
SYSTEMD_FLAG=""
if printf '%s\n' "$CONFIG_HELP" | grep -q -- '--with-systemd-startup'; then
  SYSTEMD_FLAG="--with-systemd-startup"
else
  warn "--with-systemd-startup not supported by this Shairport Sync; will not pass it."
fi

log "Configuring Shairport Sync (AirPlay 2 + PulseAudio backend, no direct ALSA)..."
# shellcheck disable=SC2086  # SYSTEMD_FLAG is intentionally word-split (may be empty)
./configure --sysconfdir=/etc \
  "$PA_FLAG" \
  --with-soxr \
  --with-avahi \
  --with-ssl=openssl \
  --with-airplay-2 \
  $SYSTEMD_FLAG

log "Building Shairport Sync..."
make
$SUDO make install

# --- Configure device name ---------------------------------------------------
SPS_CONF="/etc/shairport-sync.conf"
log "Setting AirPlay device name to '${AIRPLAY_NAME}' in ${SPS_CONF}..."
if [[ -f "$SPS_CONF" ]]; then
  $SUDO cp -a "$SPS_CONF" "${SPS_CONF}.bak.$(date +%Y%m%d%H%M%S)" || warn "Could not back up existing conf."
fi
# Write a minimal config that only sets the name. The PulseAudio backend was
# selected at compile time and connects to the pipewire-pulse default sink, so
# no ALSA output device is specified here (no direct hw:/plughw:).
$SUDO tee "$SPS_CONF" >/dev/null <<EOF
// Managed by AuraBridge install-airplay2.sh (Phase 2).
// Output backend is PulseAudio (compiled in) -> pipewire-pulse -> PipeWire.
// Do NOT add an alsa { output_device = "hw:..."; } block here.
general = {
  name = "${AIRPLAY_NAME}";
};
EOF

# --- Safe volume BEFORE enabling/testing -------------------------------------
if [[ -x "$SCRIPT_DIR/safe-volume.sh" ]]; then
  log "Applying safe initial volume before starting AirPlay..."
  "$SCRIPT_DIR/safe-volume.sh" || warn "safe-volume.sh reported an issue (continuing)."
else
  warn "safe-volume.sh not found — set a safe volume manually before testing."
fi

# --- Enable and start shairport-sync -----------------------------------------
log "Enabling and starting shairport-sync..."
if ! $SUDO systemctl enable --now shairport-sync 2>/dev/null; then
  warn "shairport-sync failed to enable/start. Showing status and recent logs:"
  $SUDO systemctl status shairport-sync --no-pager 2>/dev/null || true
  journalctl -u shairport-sync -n 50 --no-pager 2>/dev/null || true
  die "shairport-sync did not start. See logs above and docs/airplay2.md (PulseAudio session note)."
fi

# Verify it is actually active; if not, surface logs.
sleep 1
if [[ "$($SUDO systemctl is-active shairport-sync 2>/dev/null || echo unknown)" != "active" ]]; then
  warn "shairport-sync is not active. Recent logs:"
  $SUDO systemctl status shairport-sync --no-pager 2>/dev/null || true
  journalctl -u shairport-sync -n 50 --no-pager 2>/dev/null || true
fi

echo
log "AirPlay 2 install complete."
log "Look for '${AIRPLAY_NAME}' on an iPhone/Mac on the same network."
log "Keep the Aura Studio 3 physical volume LOW for the first test."
log "If the stream connects but there is no sound, the system shairport-sync"
log "service may not reach your user pipewire-pulse session — see docs/airplay2.md."
