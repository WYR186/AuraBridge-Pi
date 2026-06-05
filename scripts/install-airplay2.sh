#!/usr/bin/env bash
set -euo pipefail

# install-airplay2.sh — Phase 2: build & install NQPTP and Shairport Sync with
# AirPlay 2 support and the NATIVE PipeWire backend (--with-pw), bypassing
# pipewire-pulse to cut IPC overhead and improve PTP timing precision (Directive 3).
#
# Key rules (from PROJECT_OVERVIEW_2_2.md + Directive 3):
#   - Use the native PipeWire backend (--with-pw), NOT the PulseAudio backend.
#     Shairport Sync connects to PipeWire directly, not through pipewire-pulse.
#   - './configure --help' is the source of truth for the exact PipeWire flag.
#   - Never route directly to ALSA hw:/plughw: devices; WirePlumber routes the
#     AirPlay stream to the AuraBridge output (Safe Sink / selected sink).
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

# --- Verify PipeWire is present (native backend target) ----------------------
log "Verifying PipeWire is available (the native --with-pw backend connects to it)..."
command -v pipewire >/dev/null 2>&1 || warn "pipewire not found — run ./scripts/setup-pipewire.sh first."
if command -v wpctl >/dev/null 2>&1; then
  if wpctl status >/dev/null 2>&1; then
    log "PipeWire session reachable (wpctl)."
  else
    warn "wpctl could not reach a PipeWire session yet (it must be running for output)."
  fi
else
  warn "wpctl not found — install wireplumber/pipewire (setup-pipewire.sh does this)."
fi
# pipewire-pulse is NOT required for AirPlay anymore, but other tools (pactl /
# safe-volume.sh) still use it; we neither require nor remove it here.

# --- Build dependencies ------------------------------------------------------
log "Installing build dependencies for NQPTP and Shairport Sync (AirPlay 2 + native PipeWire)..."
$SUDO apt-get update
# libpipewire-0.3-dev replaces libpulse-dev: the native --with-pw backend needs
# the PipeWire client headers, and we no longer build the PulseAudio backend.
$SUDO apt-get install -y \
  build-essential git autoconf automake libtool \
  libpopt-dev libconfig-dev libasound2-dev \
  libavahi-client-dev libssl-dev libsoxr-dev \
  libplist-dev libsodium-dev libavutil-dev libavcodec-dev libavformat-dev \
  uuid-dev libgcrypt20-dev xxd libpipewire-0.3-dev libdbus-1-dev

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
log "Inspecting ./configure --help for PipeWire and AirPlay options..."
CONFIG_HELP="$(./configure --help 2>/dev/null || true)"
echo "----- ./configure --help | grep -iE 'pipewire|with-pw' -----"
printf '%s\n' "$CONFIG_HELP" | grep -iE 'pipewire|with-pw' || echo "(no 'pipewire' lines found)"
echo "----- ./configure --help | grep -i airplay -----"
printf '%s\n' "$CONFIG_HELP" | grep -i airplay || echo "(no 'airplay' lines found)"
echo "-----------------------------------------------"

# Determine the native PipeWire backend flag from configure --help (source of truth).
PW_FLAG=""
if printf '%s\n' "$CONFIG_HELP" | grep -q -- '--with-pw'; then
  PW_FLAG="--with-pw"
else
  PW_FLAG="$(printf '%s\n' "$CONFIG_HELP" | grep -oiE -- '--with-[a-z0-9-]*(pipewire|pw)[a-z0-9-]*' | head -n1 || true)"
fi
[[ -n "$PW_FLAG" ]] || die "Could not find a native PipeWire backend flag (--with-pw) in ./configure --help.
This Shairport Sync may be too old for the native PipeWire backend, or libpipewire-0.3-dev
was missing at ./configure time. Install libpipewire-0.3-dev and use a current shairport-sync,
then re-run. (We do NOT silently fall back to the PulseAudio backend — that defeats Directive 3.)"
log "Using native PipeWire backend flag: ${PW_FLAG}"

# Only add --with-systemd-startup if this version supports it.
SYSTEMD_FLAG=""
if printf '%s\n' "$CONFIG_HELP" | grep -q -- '--with-systemd-startup'; then
  SYSTEMD_FLAG="--with-systemd-startup"
else
  warn "--with-systemd-startup not supported by this Shairport Sync; will not pass it."
fi

log "Configuring Shairport Sync (AirPlay 2 + native PipeWire backend, no direct ALSA)..."
# shellcheck disable=SC2086  # SYSTEMD_FLAG is intentionally word-split (may be empty)
./configure --sysconfdir=/etc \
  "$PW_FLAG" \
  --with-soxr \
  --with-avahi \
  --with-ssl=openssl \
  --with-airplay-2 \
  $SYSTEMD_FLAG

log "Building Shairport Sync..."
make
$SUDO make install

# --- Configure device name + native PipeWire output --------------------------
SPS_CONF="/etc/shairport-sync.conf"
log "Configuring ${SPS_CONF} for native PipeWire output as '${AIRPLAY_NAME}'..."
if [[ -f "$SPS_CONF" ]]; then
  $SUDO cp -a "$SPS_CONF" "${SPS_CONF}.bak.$(date +%Y%m%d%H%M%S)" || warn "Could not back up existing conf."
fi
# If this build shipped a sample conf, surface its 'pw' section so the exact
# option names for THIS shairport-sync version are visible (sample = source of truth).
SAMPLE_CONF=""
for s in "$PWD/scripts/shairport-sync.conf.sample" "$PWD/shairport-sync.conf.sample" /etc/shairport-sync.conf.sample; do
  [[ -f "$s" ]] && { SAMPLE_CONF="$s"; break; }
done
if [[ -n "$SAMPLE_CONF" ]]; then
  echo "----- '${SAMPLE_CONF}' pw backend section (reference) -----"
  awk '/^[[:space:]]*pw[[:space:]]*=/{f=1} f{print} f&&/};/{exit}' "$SAMPLE_CONF" 2>/dev/null | sed 's/^/    /' || true
  echo "-----------------------------------------------------------"
fi
# Native PipeWire backend: select it with general.output_backend = "pw" and give
# the node a stable name so WirePlumber's anti-hijack policy (setup-bluetooth.sh)
# can identify and prioritise the AirPlay stream. We deliberately do NOT pin a
# sink_target here — WirePlumber routes it to the AuraBridge output (Safe Sink /
# selected sink). No ALSA hw:/plughw: device.
$SUDO tee "$SPS_CONF" >/dev/null <<EOF
// Managed by AuraBridge install-airplay2.sh (Phase 2, Directive 3).
// Output backend is NATIVE PipeWire (--with-pw) -> PipeWire (no pipewire-pulse).
// Do NOT add an alsa { output_device = "hw:..."; } block here.
general = {
  name = "${AIRPLAY_NAME}";
  output_backend = "pw";
};
pw = {
  nodename = "${AIRPLAY_NAME}";
  // sink_target intentionally unset -> WirePlumber decides the route.
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

# --- Acceptance: confirm it connects as a NATIVE PipeWire client -------------
# (Directive 3 acceptance: pw-cli ls Node / wpctl status must show Shairport Sync
# as a native PipeWire client, NOT through pipewire-pulse.)
echo
log "Checking that Shairport Sync appears as a native PipeWire node..."
SPS_NODE=""
if command -v pw-cli >/dev/null 2>&1; then
  SPS_NODE="$(pw-cli ls Node 2>/dev/null | grep -iE 'shairport|aura studio 3 airplay' | head -n1 || true)"
fi
if [[ -z "$SPS_NODE" ]] && command -v wpctl >/dev/null 2>&1; then
  SPS_NODE="$(wpctl status 2>/dev/null | grep -iE 'shairport|aura studio 3 airplay' | head -n1 || true)"
fi
if [[ -n "$SPS_NODE" ]]; then
  log "Native PipeWire node present:"
  printf '    %s\n' "$SPS_NODE"
else
  warn "No Shairport Sync PipeWire node visible yet. It usually appears only while a"
  warn "stream is connecting/playing. Start an AirPlay stream, then run:"
  warn "    pw-cli ls Node | grep -i shairport     # or: wpctl status"
fi

echo
log "AirPlay 2 install complete (native PipeWire backend, no pipewire-pulse)."
log "Look for '${AIRPLAY_NAME}' on an iPhone/Mac on the same network."
log "Keep the Aura Studio 3 physical volume LOW for the first test."
log "If the stream connects but there is no sound, the system shairport-sync service"
log "may not be reaching your user PipeWire session — see docs/airplay2.md (the native"
log "pw backend needs access to the user PipeWire socket / XDG_RUNTIME_DIR)."
