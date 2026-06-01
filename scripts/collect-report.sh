#!/usr/bin/env bash
set -euo pipefail

# collect-report.sh — gather diagnostics into reports/aurabridge-report-<ts>/.
# Read-only. Missing commands/services are recorded, not treated as fatal.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
REPORT_BASE="$REPO_ROOT/reports"
REPORT_DIR="$REPORT_BASE/aurabridge-report-$TS"
ARCHIVE="$REPORT_DIR.tar.gz"

mkdir -p "$REPORT_DIR"

log() { printf '[collect-report] %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

capture() {
  local name="$1"
  shift
  {
    printf '$'
    printf ' %q' "$@"
    printf '\n\n'
    "$@" 2>&1 || printf '\n(command exited non-zero)\n'
  } > "$REPORT_DIR/$name"
}

capture_shell() {
  local name="$1"
  local cmd="$2"
  {
    printf '$ %s\n\n' "$cmd"
    sh -c "$cmd" 2>&1 || printf '\n(command exited non-zero)\n'
  } > "$REPORT_DIR/$name"
}

log "Writing report directory: $REPORT_DIR"

capture uname-a.txt uname -a
if [[ -r /etc/os-release ]]; then
  cp /etc/os-release "$REPORT_DIR/os-release.txt"
else
  printf '/etc/os-release not readable\n' > "$REPORT_DIR/os-release.txt"
fi

if have lsusb; then capture lsusb.txt lsusb; else printf 'lsusb not found\n' > "$REPORT_DIR/lsusb.txt"; fi
if have aplay; then capture aplay-l.txt aplay -l; else printf 'aplay not found\n' > "$REPORT_DIR/aplay-l.txt"; fi
if have aplay; then capture aplay-L.txt aplay -L; else printf 'aplay not found\n' > "$REPORT_DIR/aplay-L.txt"; fi
if have pipewire; then capture pipewire-version.txt pipewire --version; else printf 'pipewire not found\n' > "$REPORT_DIR/pipewire-version.txt"; fi
if have wireplumber; then capture wireplumber-version.txt wireplumber --version; else printf 'wireplumber not found\n' > "$REPORT_DIR/wireplumber-version.txt"; fi
if have wpctl; then capture wpctl-status.txt wpctl status; else printf 'wpctl not found\n' > "$REPORT_DIR/wpctl-status.txt"; fi
if have pactl; then capture pactl-info.txt pactl info; else printf 'pactl not found\n' > "$REPORT_DIR/pactl-info.txt"; fi
if have pactl; then capture pactl-sinks-short.txt pactl list sinks short; else printf 'pactl not found\n' > "$REPORT_DIR/pactl-sinks-short.txt"; fi

system_units=(shairport-sync.service nqptp.service bluetooth.service)
user_units=(librespot.service pipewire.service pipewire-pulse.service wireplumber.service)

for unit in "${system_units[@]}"; do
  if have systemctl; then
    capture "systemctl-status-$unit.txt" systemctl status "$unit" --no-pager
  else
    printf 'systemctl not found\n' > "$REPORT_DIR/systemctl-status-$unit.txt"
  fi
done

for unit in "${user_units[@]}"; do
  if have systemctl; then
    capture "systemctl-user-status-$unit.txt" systemctl --user status "$unit" --no-pager
  else
    printf 'systemctl not found\n' > "$REPORT_DIR/systemctl-user-status-$unit.txt"
  fi
done

if have journalctl; then
  capture journal-errors.txt journalctl -p err -n 100 --no-pager
  for unit in "${system_units[@]}"; do
    capture "journal-$unit.txt" journalctl -u "$unit" -n 120 --no-pager
  done
  for unit in "${user_units[@]}"; do
    capture "journal-user-$unit.txt" journalctl --user -u "$unit" -n 120 --no-pager
  done
else
  printf 'journalctl not found\n' > "$REPORT_DIR/journal-errors.txt"
fi

if have dmesg; then
  capture_shell dmesg-usb.txt 'dmesg 2>/dev/null | grep -i usb | tail -n 120'
else
  printf 'dmesg not found\n' > "$REPORT_DIR/dmesg-usb.txt"
fi

if [[ -x "$SCRIPT_DIR/status.sh" ]]; then
  capture aurabridge-status.txt "$SCRIPT_DIR/status.sh"
fi
if [[ -x "$SCRIPT_DIR/logs.sh" ]]; then
  capture aurabridge-logs.txt "$SCRIPT_DIR/logs.sh"
fi

{
  echo "AuraBridge report: $TS"
  echo "Repo: $REPO_ROOT"
  if have git && git -C "$REPO_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    echo "Git commit: $(git -C "$REPO_ROOT" rev-parse HEAD)"
    echo "Git status:"
    git -C "$REPO_ROOT" status --short
  fi
  echo
  echo "Safety note: this report does not validate DLNA or Safe Sink."
} > "$REPORT_DIR/README.txt"

if have tar; then
  tar -czf "$ARCHIVE" -C "$REPORT_BASE" "$(basename "$REPORT_DIR")"
  log "Archive created: $ARCHIVE"
else
  log "tar not found; report directory left unarchived: $REPORT_DIR"
fi

log "Done."
