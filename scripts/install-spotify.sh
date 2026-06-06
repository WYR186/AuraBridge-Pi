#!/usr/bin/env bash
set -euo pipefail

# install-spotify.sh — Phase 3: install librespot (Spotify Connect) and run it
# as a USER systemd service routing through pipewire-pulse.
#
# Rules (from PROJECT_OVERVIEW_2_2.md):
#   - Route through PulseAudio-compatible output / pipewire-pulse. NOT direct ALSA.
#   - Device name: "Aura Studio 3 Spotify".
#   - Enable/start only after config exists. Run safe-volume.sh before testing.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SPOTIFY_NAME="${SPOTIFY_NAME:-Aura Studio 3 Spotify}"
LIBRESPOT_FEATURES="${LIBRESPOT_FEATURES:-pulseaudio-backend,with-avahi,native-tls}"
LOCAL_BIN="$HOME/.local/bin"
USER_UNIT_DIR="$HOME/.config/systemd/user"
FEATURE_MARKER="${XDG_CONFIG_HOME:-$HOME/.config}/aurabridge/librespot-build-features"

# SSH-launched non-login shells on Raspberry Pi OS often omit user-local bins.
# Prefer rustup/cargo and any existing user-installed librespot before apt's
# older /usr/bin/cargo.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

log()  { printf '[spotify] %s\n' "$*"; }
warn() { printf '[spotify][WARN] %s\n' "$*" >&2; }
die()  { printf '[spotify][ERROR] %s\n' "$*" >&2; exit 1; }

if [[ "$(id -u)" -eq 0 ]]; then
  die "Do not run this as root. librespot runs as your login USER service so it
shares the pipewire-pulse session. Re-run as the normal user."
fi
command -v apt-get >/dev/null 2>&1 || die "apt-get not found (need Raspberry Pi OS / Debian)."

# --- Verify pipewire-pulse ---------------------------------------------------
if command -v pactl >/dev/null 2>&1 && pactl info >/dev/null 2>&1; then
  log "pipewire-pulse reachable (pactl info OK)."
else
  warn "Could not confirm pipewire-pulse via pactl. Run ./scripts/setup-pipewire.sh first."
fi

# --- Acquire librespot -------------------------------------------------------
LIBRESPOT_SRC=""
if command -v librespot >/dev/null 2>&1 && [[ -f "$FEATURE_MARKER" ]] && grep -qx "$LIBRESPOT_FEATURES" "$FEATURE_MARKER"; then
  LIBRESPOT_SRC="$(command -v librespot)"
  log "Found existing AuraBridge-built librespot at ${LIBRESPOT_SRC} with features: ${LIBRESPOT_FEATURES}."
else
  if command -v librespot >/dev/null 2>&1; then
    warn "Existing librespot is not marked with the required AuraBridge features."
    warn "Rebuilding so Spotify Connect zeroconf discovery is available."
  else
    log "librespot not found — building via cargo."
  fi
  log "Installing build dependencies..."
  sudo apt-get update
  sudo apt-get install -y build-essential pkg-config libpulse-dev libssl-dev libavahi-client-dev
  if ! command -v cargo >/dev/null 2>&1; then
    log "Installing cargo (Rust) from apt..."
    sudo apt-get install -y cargo
  fi
  command -v cargo >/dev/null 2>&1 || die "cargo unavailable. Install Rust (e.g. 'sudo apt-get install cargo' or rustup) and re-run."

  log "Building librespot with features: ${LIBRESPOT_FEATURES}"
  log "This can take a long time on a Pi."
  if ! cargo install librespot --locked --force --no-default-features --features "$LIBRESPOT_FEATURES"; then
    die "cargo build of librespot failed. Your Rust toolchain may be too old.
Install a newer toolchain (e.g. via rustup) and re-run, or provide a librespot binary on PATH."
  fi
  LIBRESPOT_SRC="$HOME/.cargo/bin/librespot"
  mkdir -p "$(dirname "$FEATURE_MARKER")"
  printf '%s\n' "$LIBRESPOT_FEATURES" > "$FEATURE_MARKER"
fi
[[ -x "$LIBRESPOT_SRC" ]] || die "librespot binary not found/executable at: ${LIBRESPOT_SRC}"

# --- Expose at a stable, user-relative path the unit references --------------
mkdir -p "$LOCAL_BIN"
if [[ "$LIBRESPOT_SRC" != "$LOCAL_BIN/librespot" ]]; then
  ln -sf "$LIBRESPOT_SRC" "$LOCAL_BIN/librespot"
  log "Linked ${LOCAL_BIN}/librespot -> ${LIBRESPOT_SRC}"
fi

# --- Install the user systemd unit -------------------------------------------
mkdir -p "$USER_UNIT_DIR"
if [[ -f "$REPO_ROOT/systemd/librespot.service" ]]; then
  install -m 0644 "$REPO_ROOT/systemd/librespot.service" "$USER_UNIT_DIR/librespot.service"
else
  die "systemd/librespot.service missing from the repo."
fi
# Honor a custom device name if provided (default already matches the unit).
if [[ "$SPOTIFY_NAME" != "Aura Studio 3 Spotify" ]]; then
  sed -i "s/Aura Studio 3 Spotify/${SPOTIFY_NAME//\//\\/}/g" "$USER_UNIT_DIR/librespot.service"
  log "Set Spotify device name to '${SPOTIFY_NAME}'."
fi
log "Installed user unit: ${USER_UNIT_DIR}/librespot.service"

# --- Allow the user service to run without an active login (headless) --------
log "Enabling user lingering (so the service runs at boot without login)..."
sudo loginctl enable-linger "$USER" 2>/dev/null || warn "Could not enable linger (continuing)."

systemctl --user daemon-reload

# --- Safe volume BEFORE starting ---------------------------------------------
if [[ -x "$SCRIPT_DIR/safe-volume.sh" ]]; then
  log "Applying safe initial volume before starting librespot..."
  "$SCRIPT_DIR/safe-volume.sh" || warn "safe-volume.sh reported an issue (continuing)."
fi

# --- Enable and start (config/unit now exists) -------------------------------
log "Enabling librespot (user service)..."
if ! systemctl --user enable librespot.service; then
  warn "librespot failed to start. Status and recent logs:"
  systemctl --user status librespot.service --no-pager 2>/dev/null || true
  journalctl --user -u librespot.service -n 50 --no-pager 2>/dev/null || true
  die "librespot could not be enabled. See logs above and docs/spotify.md."
fi

log "Restarting librespot so updated binary/unit options take effect..."
if ! systemctl --user restart librespot.service; then
  warn "librespot failed to restart. Status and recent logs:"
  systemctl --user status librespot.service --no-pager 2>/dev/null || true
  journalctl --user -u librespot.service -n 50 --no-pager 2>/dev/null || true
  die "librespot did not restart. See logs above and docs/spotify.md."
fi

sleep 1
echo
log "librespot status:"
systemctl --user status librespot.service --no-pager 2>/dev/null | head -n 12 || true
echo
log "Recent librespot logs:"
journalctl --user -u librespot.service -n 20 --no-pager 2>/dev/null || true

echo
log "Spotify Connect install complete."
log "In the Spotify app (same account + network), pick '${SPOTIFY_NAME}'."
log "Keep the Aura Studio 3 physical volume LOW for the first test."
