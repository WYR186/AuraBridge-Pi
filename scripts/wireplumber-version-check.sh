#!/usr/bin/env bash
set -euo pipefail

# wireplumber-version-check.sh — Phase 1: detect PipeWire & WirePlumber versions
# and the likely config model. Makes NO changes. No WirePlumber policy is written
# in Phase 0-3. See docs/wireplumber-versioning.md.

log()  { printf '[wp-version] %s\n' "$*"; }
warn() { printf '[wp-version][WARN] %s\n' "$*" >&2; }

# Extract the first x.y or x.y.z token from a tool's --version output.
extract_version() {
  grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true
}

echo "=== PipeWire / WirePlumber version check ==="
echo

PW_VER=""
WP_VER=""

if command -v pipewire >/dev/null 2>&1; then
  PW_VER="$(pipewire --version 2>/dev/null | extract_version)"
  log "PipeWire version: ${PW_VER:-unknown}"
else
  warn "pipewire not found."
fi

if command -v wireplumber >/dev/null 2>&1; then
  WP_VER="$(wireplumber --version 2>/dev/null | extract_version)"
  log "WirePlumber version: ${WP_VER:-unknown}"
else
  warn "wireplumber not found."
fi

echo
echo "--- Likely configuration model ---"
if [[ -n "$WP_VER" ]]; then
  WP_MAJOR="${WP_VER%%.*}"
  WP_REST="${WP_VER#*.}"
  WP_MINOR="${WP_REST%%.*}"
  if [[ "$WP_MAJOR" == "0" && "$WP_MINOR" == "4" ]]; then
    echo "WirePlumber ${WP_VER} -> 0.4.x: Lua-style configuration (.lua). Use 0.4-era docs."
  elif [[ "$WP_MAJOR" == "0" && "$WP_MINOR" -ge 5 ]] || [[ "$WP_MAJOR" -ge 1 ]]; then
    echo "WirePlumber ${WP_VER} -> 0.5.x+ : SPA-JSON / JSON-style configuration (.conf). Use matching docs."
  else
    echo "WirePlumber ${WP_VER}: unrecognized series — verify the config model manually."
  fi
else
  warn "Could not determine WirePlumber version; cannot infer config model."
fi

echo
echo "WARNING: Do not blindly copy latest WirePlumber documentation."
echo "         Use version-matched documentation only."
echo "         (A 0.5.x config does not work on 0.4.x, and vice versa.)"

echo
echo "--- Likely config directories (existing only) ---"
CONFIG_DIRS=(
  "/usr/share/wireplumber"
  "/etc/wireplumber"
  "/etc/wireplumber/wireplumber.conf.d"
  "${HOME}/.config/wireplumber"
)
found_any=0
for d in "${CONFIG_DIRS[@]}"; do
  if [[ -d "$d" ]]; then
    echo "  present: $d"
    found_any=1
  fi
done
[[ "$found_any" -eq 0 ]] && echo "  (none of the common config directories exist yet)"

echo
log "No changes were made. (Phase 0-3 writes no WirePlumber policy.)"
