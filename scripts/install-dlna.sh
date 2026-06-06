#!/usr/bin/env bash
set -euo pipefail

# install-dlna.sh — Phase 6: install a DLNA / UPnP renderer (gmediarender /
# gmrender-resurrect) ONLY IF the real-time audio safety layer (the AuraBridge
# Safe Sink) has been VERIFIED. Otherwise it refuses to do anything.
#
# Hard gate: this script requires logs/safe-sink-verified.txt to contain
# SAFE_SINK_VERIFIED=yes (written only by test-safe-sink.sh after a human
# confirms the 100%-volume hard cap). The volume guard does NOT count. DLNA can
# push unsafe volume commands, so it must never run without a verified Safe Sink.
#
# Even when verified, the renderer is installed DISABLED (not enabled, no
# autostart). Start it manually, and stop it quickly when done.
#
# See docs/dlna.md, docs/safe-sink.md, docs/volume-safety.md.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MARKER="$REPO_ROOT/logs/safe-sink-verified.txt"
USER_UNIT_DIR="$HOME/.config/systemd/user"
DLNA_NAME="${DLNA_NAME:-Aura Studio 3 DLNA}"
SAFE_SINK_NODE="aurabridge_safe_sink"
# Stable identity for the renderer: a UUID persisted under ~/.config/aurabridge so
# control points (BubbleUPnP / Hi-Fi Cast / ...) keep recognising the SAME device
# across reboots instead of re-discovering a "new" one each time. gmrender.service
# loads this file via EnvironmentFile and passes it as --uuid.
UUID_DIR="$HOME/.config/aurabridge"
UUID_FILE="$UUID_DIR/dlna-uuid"

log()  { printf '[dlna] %s\n' "$*"; }
warn() { printf '[dlna][WARN] %s\n' "$*" >&2; }
die()  { printf '[dlna][ERROR] %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- THE GATE: refuse unless the Safe Sink is verified -----------------------
if [[ ! -f "$MARKER" ]] || ! grep -q '^SAFE_SINK_VERIFIED=yes' "$MARKER"; then
  echo "DLNA is blocked until real-time audio safety is verified."
  echo
  warn "No verified Safe Sink found (${MARKER})."
  warn "Run, on the Pi, in order:"
  warn "  ./scripts/setup-safe-sink.sh --apply"
  warn "  ./scripts/test-safe-sink.sh        # must report VERIFIED"
  warn "The volume guard (polling) does NOT make DLNA safe and does NOT satisfy"
  warn "this gate. See docs/dlna.md and docs/volume-safety.md."
  exit 1
fi
log "Safe Sink verification found:"
grep -E '^(SAFE_SINK_VERIFIED|timestamp|dangerous_at_100pct|gain)=' "$MARKER" | sed 's/^/    /' || true

# --- From here: verified. Install, but keep DLNA OFF by default --------------
if [[ "$(id -u)" -eq 0 ]]; then
  die "Do not run as root. The DLNA renderer runs as your USER service so it
shares the pipewire-pulse session (and the verified Safe Sink). Re-run as the normal user."
fi
have apt-get || die "apt-get not found (need Raspberry Pi OS / Debian)."

# --- Acquire the renderer (gmediarender = gmrender-resurrect) ----------------
if have gmediarender; then
  log "gmediarender already installed ($(command -v gmediarender))."
else
  log "Installing gmediarender (gmrender-resurrect) via apt..."
  sudo apt-get update
  if ! sudo apt-get install -y gmediarender; then
    die "Could not install 'gmediarender'. Alternative: install Rygel and adapt
systemd/gmrender.service. Refusing to guess a renderer."
  fi
fi
GMR_BIN="$(command -v gmediarender || echo /usr/bin/gmediarender)"
[[ -x "$GMR_BIN" ]] || die "gmediarender binary not found/executable at ${GMR_BIN}."

# --- GStreamer codec coverage ------------------------------------------------
# gmediarender decodes through GStreamer. The base package pulls a minimal plugin
# set, which is NOT enough for what Xiaomi / Samsung phones actually push (AAC /
# M4A / FLAC, sometimes OGG/ALAC). Without these the device is DISCOVERED but the
# track fails to play. Install the broader plugin set (idempotent).
log "Ensuring GStreamer codec plugins are present (MP3/AAC/M4A/FLAC/WAV/OGG)..."
if ! sudo apt-get install -y \
     gstreamer1.0-plugins-good \
     gstreamer1.0-plugins-bad \
     gstreamer1.0-plugins-ugly \
     gstreamer1.0-libav; then
  warn "Could not install the full GStreamer plugin set. Some codecs (e.g. AAC/M4A,"
  warn "FLAC) may fail to play. Re-run with working apt sources to fix coverage."
fi

# --- Stable renderer identity (persistent UUID) ------------------------------
mkdir -p "$UUID_DIR"
if [[ -s "$UUID_FILE" ]] && grep -q '^AURABRIDGE_DLNA_UUID=' "$UUID_FILE"; then
  log "Reusing existing DLNA UUID from ${UUID_FILE}."
else
  if have uuidgen; then
    NEW_UUID="$(uuidgen)"
  elif [[ -r /proc/sys/kernel/random/uuid ]]; then
    NEW_UUID="$(cat /proc/sys/kernel/random/uuid)"
  else
    die "Cannot generate a UUID (no uuidgen and no /proc/sys/kernel/random/uuid).
Install 'uuid-runtime' (sudo apt-get install -y uuid-runtime) and re-run."
  fi
  printf 'AURABRIDGE_DLNA_UUID=%s\n' "$NEW_UUID" > "$UUID_FILE"
  chmod 0600 "$UUID_FILE"
  log "Generated stable DLNA UUID -> ${UUID_FILE} (${NEW_UUID})."
fi

# --- Install the USER unit (DISABLED: no enable, no autostart) ---------------
mkdir -p "$USER_UNIT_DIR"
[[ -f "$REPO_ROOT/systemd/gmrender.service" ]] || die "systemd/gmrender.service missing from the repo."
install -m 0644 "$REPO_ROOT/systemd/gmrender.service" "$USER_UNIT_DIR/gmrender.service"
# Honor a custom renderer name if provided (default already matches the unit).
if [[ "$DLNA_NAME" != "Aura Studio 3 DLNA" ]]; then
  sed -i "s/Aura Studio 3 DLNA/${DLNA_NAME//\//\\/}/g" "$USER_UNIT_DIR/gmrender.service"
  log "Set DLNA renderer name to '${DLNA_NAME}'."
fi
systemctl --user daemon-reload 2>/dev/null || warn "Could not run 'systemctl --user daemon-reload'."
log "Installed user unit: ${USER_UNIT_DIR}/gmrender.service (NOT enabled)."

# --- Safe volume BEFORE any test ---------------------------------------------
if [[ -x "$SCRIPT_DIR/safe-volume.sh" ]]; then
  log "Applying safe initial volume before any DLNA test..."
  "$SCRIPT_DIR/safe-volume.sh" || warn "safe-volume.sh reported an issue (continuing)."
fi

# --- Tell the user exactly how to start/stop (manually) ----------------------
cat <<EOF

[dlna] DLNA renderer installed but DISABLED by default (this is intentional).
[dlna] It routes through pipewire-pulse to the verified Safe Sink
[dlna] ('${SAFE_SINK_NODE}'), never directly to ALSA hardware.

  Start manually (foreground service):   systemctl --user start gmrender.service
  Check status:                          systemctl --user status gmrender.service
  Verify phones can discover it:         ./scripts/check-dlna-discovery.sh
  Quick STOP:                            systemctl --user stop gmrender.service

[dlna] The unit has a start-time gate: it refuses to start unless the Safe Sink
[dlna] is still verified. It is NOT enabled, so it will NOT start at boot.
[dlna] Keep the Aura Studio 3 PHYSICAL volume LOW while testing DLNA.
[dlna] DLNA is NOT made safe by the volume guard — only by the verified Safe Sink.
EOF
