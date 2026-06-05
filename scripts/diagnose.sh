#!/bin/bash
#
# AuraBridge Pi 2.2 — Comprehensive Status Diagnostic
#
# Usage: ./scripts/diagnose.sh [--brief|--full|--json]
#
# Shows: System info, network, PipeWire/audio, services, sinks, recent errors
# Color-coded for quick visual scanning
#

set -o pipefail

# ============================================================================
# CONFIG & COLORS
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

# Status symbols
OK="✅"
FAIL="❌"
WARN="⚠️"
INFO="ℹ️"
PENDING="⏳"

# Mode
MODE="${1:-normal}"  # normal | brief | full | json

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

status_ok() {
  echo -e "${GREEN}${OK} $1${NC}"
}

status_fail() {
  echo -e "${RED}${FAIL} $1${NC}"
}

status_warn() {
  echo -e "${YELLOW}${WARN} $1${NC}"
}

status_info() {
  echo -e "${CYAN}${INFO} $1${NC}"
}

status_pending() {
  echo -e "${YELLOW}${PENDING} $1${NC}"
}

section() {
  echo ""
  echo -e "${BOLD}${BLUE}═══ $1 ═══${NC}"
}

subsection() {
  echo -e "${CYAN}► $1${NC}"
}

kv() {
  printf "  %-35s %s\n" "$1:" "$2"
}

divider() {
  echo "─────────────────────────────────────────────────────────────"
}

# Check if systemd service is running
is_service_active() {
  systemctl is-active --quiet "$1" 2>/dev/null
}

is_user_service_active() {
  systemctl --user is-active --quiet "$1" 2>/dev/null
}

# Get service status (human-readable)
get_service_status() {
  local status
  status=$(systemctl is-active "$1" 2>/dev/null)
  case "$status" in
    active) echo -e "${GREEN}active${NC}" ;;
    inactive) echo -e "${RED}inactive${NC}" ;;
    failed) echo -e "${RED}failed${NC}" ;;
    *) echo -e "${YELLOW}${status}${NC}" ;;
  esac
}

get_user_service_status() {
  local status
  status=$(systemctl --user is-active "$1" 2>/dev/null)
  case "$status" in
    active) echo -e "${GREEN}active${NC}" ;;
    inactive) echo -e "${RED}inactive${NC}" ;;
    failed) echo -e "${RED}failed${NC}" ;;
    *) echo -e "${YELLOW}${status}${NC}" ;;
  esac
}

# ============================================================================
# MAIN DIAGNOSTICS
# ============================================================================

diagnose_system_info() {
  section "System Information"

  kv "Hostname" "$(hostname)"
  local model
  model=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0' || echo 'Raspberry Pi 4')
  kv "Model" "$model"
  kv "OS" "$(grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')"
  kv "Kernel" "$(uname -r)"
  kv "Architecture" "$(uname -m)"
  kv "Uptime" "$(uptime -p 2>/dev/null || uptime)"
}

diagnose_network() {
  section "Network & Connectivity"

  local ip_addr
  ip_addr=$(hostname -I | awk '{print $1}')

  if [ -n "$ip_addr" ]; then
    status_ok "Network connected"
    kv "IP Address" "$ip_addr"
  else
    status_fail "No network address"
  fi

  if ping -c 1 -W 1 8.8.8.8 &>/dev/null; then
    status_ok "Internet reachable"
  else
    status_warn "Internet unreachable (but may not affect local playback)"
  fi

  if systemctl is-active --quiet avahi-daemon; then
    status_ok "mDNS (Avahi) running"
  else
    status_warn "mDNS (Avahi) not running — device discovery may fail"
  fi
}

diagnose_pipewire() {
  section "PipeWire & Audio Engine"

  subsection "Core Services"
  echo "  PipeWire:        $(get_user_service_status pipewire.service)"
  echo "  WirePlumber:     $(get_user_service_status wireplumber.service)"
  echo "  PipeWire-Pulse:  $(get_user_service_status pipewire-pulse.service)"

  subsection "Version & Connection"
  if is_user_service_active pipewire.service; then
    status_ok "PipeWire session reachable"

    local pw_version
    pw_version=$(pw-cli info 2>/dev/null | grep "object.serial" | head -1 || echo "unknown")
    kv "PipeWire version" "$(pw-dump 2>/dev/null | grep -o '"version":"[^"]*' | head -1 | cut -d'"' -f4 || echo 'check wpctl status')"
  else
    status_fail "PipeWire not running"
  fi
}

diagnose_output_config() {
  section "Output Configuration (Dual-Output Layer)"

  local output_conf="$HOME/.config/aurabridge/output.conf"

  subsection "Configured Output"
  if [ -f "$output_conf" ]; then
    local configured
    configured=$(grep "^AURABRIDGE_OUTPUT=" "$output_conf" | cut -d= -f2)
    if [ -n "$configured" ]; then
      status_ok "Configuration found"
      kv "Mode" "$configured"
    else
      status_warn "Config file exists but empty"
    fi
  else
    status_warn "No config file (using auto-detect)"
  fi

  subsection "Effective Output"
  local default_sink
  default_sink=$(pactl list short sinks 2>/dev/null | grep -v "^#" | head -1 | awk '{$1=$6=$7=""; print $0}' | xargs)

  if [ -n "$default_sink" ]; then
    if echo "$default_sink" | grep -qi "bcm2835\|headphones"; then
      status_ok "Onboard audio (3.5mm) is active"
    elif echo "$default_sink" | grep -qi "fiio\|ka11\|usb"; then
      status_ok "USB DAC is active"
    else
      status_info "Sink: $default_sink"
    fi
  else
    status_warn "Cannot determine active sink"
  fi
}

get_dac_name() {
  local device_id="$1"

  # Known USB DAC IDs and names
  case "$device_id" in
    "2a45:0126") echo "Meizu HiFi DAC Headphone Amplifier PRO" ;;
    "2a45:0120") echo "Meizu HiFi DAC" ;;
    "2204:0003") echo "FiiO KA11" ;;
    "2204:0004") echo "FiiO KA13" ;;
    "2204:0005") echo "FiiO BTR7" ;;
    "0d8c:*") echo "C-Media USB Audio Device" ;;
    "1852:7022") echo "XMOS USB Audio" ;;
    "046d:*") echo "Logitech USB Audio" ;;
    *) echo "Unknown USB Audio Device ($device_id)" ;;
  esac
}

diagnose_usb_devices() {
  section "USB Audio Devices (小尾巴 / USB DAC Detection)"

  subsection "Connected USB Devices"
  if command -v lsusb &>/dev/null; then
    local usb_devices
    usb_devices=$(lsusb 2>/dev/null)

    if [ -z "$usb_devices" ]; then
      status_warn "No USB devices detected"
      return
    fi

    # Look for known audio DACs
    local fiio_found=0
    local meizu_found=0
    local other_audio_found=0

    # Check for FiiO (小尾巴) — 2204:
    if echo "$usb_devices" | grep -qi "2204:\|fiio\|ka11\|ka13\|btr"; then
      status_ok "FiiO DAC detected! (小尾巴 present)"
      fiio_found=1
      echo "$usb_devices" | grep -iE "2204:|fiio" | while read -r line; do
        local device_id
        device_id=$(echo "$line" | grep -oE "[0-9a-f]+:[0-9a-f]+" | tail -1)
        local dac_name
        dac_name=$(get_dac_name "$device_id")
        echo "  $line"
        echo "    → Type: $dac_name"
      done
    fi

    # Check for Meizu
    if echo "$usb_devices" | grep -qi "2a45:\|meizu"; then
      if [ "$fiio_found" -eq 0 ]; then
        status_info "Meizu HiFi DAC detected:"
        fiio_found=1
      else
        status_info "Also detected: Meizu HiFi DAC"
      fi
      meizu_found=1
      echo "$usb_devices" | grep -iE "2a45:|meizu" | while read -r line; do
        local device_id
        device_id=$(echo "$line" | grep -oE "[0-9a-f]+:[0-9a-f]+" | tail -1)
        local dac_name
        dac_name=$(get_dac_name "$device_id")
        echo "  $line"
        echo "    → Type: $dac_name"
      done
    fi

    # Check for other USB audio devices
    if echo "$usb_devices" | grep -qi "audio\|dac\|sound" && [ "$fiio_found" -eq 0 ]; then
      status_info "Generic USB audio device(s) detected:"
      echo "$usb_devices" | grep -i "audio\|dac\|sound" | while read -r line; do
        echo "  $line"
      done
      other_audio_found=1
    fi

    # Summary
    if [ "$fiio_found" -eq 0 ] && [ "$other_audio_found" -eq 0 ]; then
      status_warn "No USB audio DAC detected (only onboard audio available)"
      echo "  Use ./scripts/select-output.sh usb to switch when you connect one"
    fi
  else
    status_warn "lsusb not installed"
  fi
}

diagnose_alsa() {
  section "ALSA Audio Devices"

  subsection "Playback Cards"
  if command -v aplay &>/dev/null; then
    local num_cards
    num_cards=$(aplay -l 2>/dev/null | grep "^card" | wc -l)

    if [ "$num_cards" -gt 0 ]; then
      status_ok "$num_cards audio card(s) detected"
      aplay -l 2>/dev/null | grep "^card" | sed 's/^/  /'
    else
      status_fail "No audio cards detected"
    fi
  else
    status_warn "aplay not installed"
  fi
}

diagnose_sinks() {
  section "PipeWire Sinks (Audio Outputs)"

  if is_user_service_active pipewire.service; then
    subsection "Available Sinks"
    local sinks
    sinks=$(pactl list short sinks 2>/dev/null)

    if [ -n "$sinks" ]; then
      echo "$sinks" | while read -r line; do
        local sink_id sink_name sink_state
        sink_id=$(echo "$line" | awk '{print $1}')
        sink_name=$(echo "$line" | awk '{print $2}')
        sink_state=$(echo "$line" | awk '{print $6}')

        if [ "$sink_state" = "RUNNING" ]; then
          status_ok "Sink $sink_id: $sink_name ($sink_state)"
        else
          status_info "Sink $sink_id: $sink_name ($sink_state)"
        fi
      done
    else
      status_fail "No sinks detected"
    fi

    subsection "Default Sink Volume"
    local vol
    vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null)
    if [ -n "$vol" ]; then
      echo "  $vol"
    else
      status_warn "Cannot read volume"
    fi
  else
    status_fail "PipeWire not running — cannot list sinks"
  fi
}

diagnose_services() {
  section "AuraBridge Services"

  subsection "Spotify (Phase 3)"
  echo "  librespot:  $(get_user_service_status librespot.service)"

  if is_user_service_active librespot.service; then
    local spotify_pid
    spotify_pid=$(systemctl --user show -p MainPID --value librespot.service 2>/dev/null)
    if [ -n "$spotify_pid" ] && [ "$spotify_pid" != "0" ]; then
      status_ok "Running (PID $spotify_pid)"

      local uptime_sec
      uptime_sec=$(awk -v pid="$spotify_pid" 'BEGIN{getline < "/proc/uptime"; ut=$1} NR==FNR{if($1==pid) {print int($22)}} NR>FNR{exit}' RS=' ' /proc/uptime /proc/"$spotify_pid"/stat 2>/dev/null)

      # Check for recent errors in log
      local recent_errors
      recent_errors=$(journalctl --user -u librespot.service -n 5 --no-pager 2>/dev/null | grep -i "error" | wc -l)
      if [ "$recent_errors" -gt 0 ]; then
        status_warn "$recent_errors error(s) in recent logs"
      fi
    fi
  else
    status_fail "Not running"
  fi

  subsection "AirPlay 2 (Phase 2)"
  echo "  shairport-sync: $(get_service_status shairport-sync)"

  if is_service_active shairport-sync; then
    status_ok "Running"
  else
    status_warn "Not running (audio backend issue)"
    # Show why it failed
    local last_error
    last_error=$(journalctl -u shairport-sync -n 3 --no-pager 2>/dev/null | grep -i "error\|fatal" | head -1)
    if [ -n "$last_error" ]; then
      echo "  Last error: ${last_error:0:80}..."
    fi
  fi

  subsection "System Services"
  echo "  avahi-daemon: $(get_service_status avahi-daemon)"
}

diagnose_disk_memory() {
  section "System Resources"

  subsection "Memory"
  local mem_info
  mem_info=$(free -h | grep "^Mem:" | awk '{printf "Total: %s | Used: %s | Available: %s", $2, $3, $7}')
  echo "  $mem_info"

  subsection "Disk Space"
  local root_disk
  root_disk=$(df -h / | tail -1 | awk '{printf "Used: %s / %s (%s)", $3, $2, $5}')
  echo "  Root: $root_disk"

  local home_disk
  home_disk=$(df -h "$HOME" 2>/dev/null | tail -1 | awk '{printf "Used: %s / %s (%s)", $3, $2, $5}')
  if [ -n "$home_disk" ]; then
    echo "  Home: $home_disk"
  fi
}

diagnose_recent_errors() {
  section "Recent Errors & Warnings (Last 24h)"

  subsection "Spotify (librespot)"
  local spotify_errors
  spotify_errors=$(journalctl --user -u librespot.service --since "24 hours ago" --no-pager 2>/dev/null | grep -i "error\|warn\|fail" | tail -3)
  if [ -n "$spotify_errors" ]; then
    echo "$spotify_errors" | sed 's/^/  /'
  else
    status_ok "No errors"
  fi

  subsection "AirPlay (shairport-sync)"
  local airplay_errors
  airplay_errors=$(journalctl -u shairport-sync --since "24 hours ago" --no-pager 2>/dev/null | grep -i "error\|warn\|fail" | tail -3)
  if [ -n "$airplay_errors" ]; then
    echo "$airplay_errors" | sed 's/^/  /'
  else
    status_ok "No errors"
  fi

  subsection "PipeWire"
  local pw_errors
  pw_errors=$(journalctl --user -u pipewire.service --since "24 hours ago" --no-pager 2>/dev/null | grep -i "error\|warn\|critical" | tail -3)
  if [ -n "$pw_errors" ]; then
    echo "$pw_errors" | sed 's/^/  /'
  else
    status_ok "No critical errors"
  fi
}

diagnose_summary() {
  section "Quick Summary"

  local score=0
  local total=8

  # Scoring system (adjusted for actual requirements)
  is_user_service_active pipewire.service && ((score++)) || true
  is_user_service_active wireplumber.service && ((score++)) || true
  is_user_service_active pipewire-pulse.service && ((score++)) || true
  is_user_service_active librespot.service && ((score++)) || true
  [ -f "$HOME/.config/aurabridge/output.conf" ] && ((score++)) || true
  is_service_active avahi-daemon && ((score++)) || true
  command -v pactl &>/dev/null && ((score++)) || true
  [ "$(hostname -I | wc -w)" -gt 0 ] && ((score++)) || true

  if [ "$score" -eq "$total" ]; then
    status_ok "All systems nominal ($score/$total) — Ready for playback!"
  elif [ "$score" -ge 6 ]; then
    status_info "Most systems operational ($score/$total) — Functional, minor issues"
  elif [ "$score" -ge 4 ]; then
    status_warn "Partial functionality ($score/$total) — Some services missing"
  else
    status_fail "Critical issues ($score/$total) — Check above for details"
  fi

  echo ""
  echo "═════════════════════════════════════════════════════════════"

  # Recommendations
  if ! is_user_service_active librespot.service; then
    echo "⚠️  Spotify not running. Try:"
    echo "    systemctl --user restart librespot.service"
  fi

  if is_service_active shairport-sync; then
    echo "ℹ️  AirPlay 2 not yet functional (audio backend needs config)"
  fi

  if [ -f "$HOME/.config/aurabridge/output.conf" ]; then
    local output
    output=$(grep "^AURABRIDGE_OUTPUT=" "$HOME/.config/aurabridge/output.conf" | cut -d= -f2)
    echo "ℹ️  Current output mode: $output"
    echo "    To switch: ./scripts/select-output.sh [onboard|usb|auto]"
  fi
}

# ============================================================================
# OUTPUT MODES
# ============================================================================

case "$MODE" in
  brief)
    diagnose_system_info
    diagnose_network
    diagnose_services
    diagnose_summary
    ;;

  full)
    diagnose_system_info
    diagnose_network
    diagnose_usb_devices
    diagnose_pipewire
    diagnose_output_config
    diagnose_alsa
    diagnose_sinks
    diagnose_services
    diagnose_disk_memory
    diagnose_recent_errors
    diagnose_summary
    ;;

  json)
    # TODO: Implement JSON output for parsing
    echo '{"status":"not-implemented","message":"JSON mode coming soon"}'
    ;;

  *)
    # Default: normal mode (balanced)
    diagnose_system_info
    diagnose_network
    diagnose_usb_devices
    diagnose_output_config
    diagnose_sinks
    diagnose_services
    diagnose_summary
    ;;
esac

exit 0
