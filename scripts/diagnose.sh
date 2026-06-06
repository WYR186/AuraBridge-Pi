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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/output-target.sh
. "$SCRIPT_DIR/lib/output-target.sh"

SAFE_SINK_NODE="aurabridge_safe_sink"
SAFE_SINK_MARKER="$PROJECT_ROOT/logs/safe-sink-verified.txt"
DLNA_UNIT="gmrender.service"
DLNA_DEFAULT_NAME="Aura Studio 3 DLNA"

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
case "${1:-normal}" in
  --brief) MODE="brief" ;;
  --full) MODE="full" ;;
  --json) MODE="json" ;;
  brief|full|json|normal) MODE="${1:-normal}" ;;
  *) MODE="normal" ;;
esac

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

indent() {
  while IFS= read -r line; do
    printf "  %s\n" "$line"
  done
}

have() {
  command -v "$1" >/dev/null 2>&1
}

with_timeout() {
  local seconds="$1"
  shift
  if have timeout; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

# Check if systemd service is running
is_service_active() {
  [ "$(systemctl is-active "$1" 2>/dev/null || true)" = "active" ]
}

is_user_service_active() {
  [ "$(systemctl --user is-active "$1" 2>/dev/null || true)" = "active" ]
}

is_service_installed() {
  systemctl cat "$1" >/dev/null 2>&1
}

is_user_service_installed() {
  systemctl --user cat "$1" >/dev/null 2>&1
}

# Get service status (human-readable)
get_service_status() {
  local status
  if ! is_service_installed "$1"; then
    echo -e "${YELLOW}not installed${NC}"
    return
  fi
  status=$(systemctl is-active "$1" 2>/dev/null)
  [ -n "$status" ] || status="unknown"
  case "$status" in
    active) echo -e "${GREEN}active${NC}" ;;
    inactive) echo -e "${RED}inactive${NC}" ;;
    failed) echo -e "${RED}failed${NC}" ;;
    *) echo -e "${YELLOW}${status}${NC}" ;;
  esac
}

get_user_service_status() {
  local status
  if ! is_user_service_installed "$1"; then
    echo -e "${YELLOW}not installed${NC}"
    return
  fi
  status=$(systemctl --user is-active "$1" 2>/dev/null)
  [ -n "$status" ] || status="unknown"
  case "$status" in
    active) echo -e "${GREEN}active${NC}" ;;
    inactive) echo -e "${RED}inactive${NC}" ;;
    failed) echo -e "${RED}failed${NC}" ;;
    *) echo -e "${YELLOW}${status}${NC}" ;;
  esac
}

safe_sink_verified() {
  [ -f "$SAFE_SINK_MARKER" ] && grep -q '^SAFE_SINK_VERIFIED=yes' "$SAFE_SINK_MARKER" 2>/dev/null
}

pactl_sinks_short() {
  have pactl || return 1
  pactl list sinks short 2>/dev/null || pactl list short sinks 2>/dev/null
}

safe_sink_present() {
  pactl_sinks_short | grep -q "$SAFE_SINK_NODE"
}

default_sink_name() {
  have pactl && pactl get-default-sink 2>/dev/null
}

dlna_friendly_name() {
  local name
  name=$(systemctl --user cat "$DLNA_UNIT" 2>/dev/null \
    | sed -nE 's/.*--friendly-name "([^"]+)".*/\1/p' \
    | tail -n1)
  printf '%s\n' "${name:-$DLNA_DEFAULT_NAME}"
}

android_cast_state() {
  if is_user_service_active "$DLNA_UNIT"; then
    if safe_sink_verified && safe_sink_present; then
      echo "running"
    else
      echo "running-with-safety-warning"
    fi
  elif ! is_user_service_installed "$DLNA_UNIT"; then
    echo "not-installed"
  elif ! safe_sink_verified; then
    echo "blocked"
  else
    echo "stopped"
  fi
}

android_cast_summary() {
  case "$(android_cast_state)" in
    running) echo "running and discoverable as $(dlna_friendly_name)" ;;
    running-with-safety-warning) echo "running, but Safe Sink verification is missing" ;;
    blocked) echo "blocked until Safe Sink is verified" ;;
    stopped) echo "installed and safe-gated, but stopped (manual start)" ;;
    not-installed) echo "not installed" ;;
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
  local os_name
  os_name=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"')
  kv "OS" "${os_name:-unknown}"
  kv "Kernel" "$(uname -r)"
  kv "Architecture" "$(uname -m)"
  kv "Uptime" "$(uptime -p 2>/dev/null || uptime)"
}

diagnose_network() {
  section "Network & Connectivity"

  local ip_addr
  ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')

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

  if is_service_active avahi-daemon.service; then
    status_ok "mDNS (Avahi) running"
  else
    status_warn "mDNS (Avahi) not running — device discovery may fail"
  fi

  local route
  route=$(ip route show default 2>/dev/null | head -n1)
  if [ -n "$route" ]; then
    kv "Default route" "$route"
  else
    status_warn "No default route"
  fi

  local dns
  if have resolvectl; then
    dns=$(resolvectl dns 2>/dev/null | awk '{$1=$2=""; sub(/^  */, ""); print}' | head -n1)
  else
    dns=$(awk '/^nameserver / {print $2}' /etc/resolv.conf 2>/dev/null | head -n2 | xargs)
  fi
  [ -n "$dns" ] && kv "DNS" "$dns"
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

    if have pipewire; then
      kv "PipeWire version" "$(pipewire --version 2>/dev/null | awk '{print $NF}' | head -n1)"
    fi
    if have wireplumber; then
      kv "WirePlumber version" "$(wireplumber --version 2>/dev/null | awk '{print $NF}' | head -n1)"
    fi
    if have pactl; then
      local pulse_server
      pulse_server=$(pactl info 2>/dev/null | awk -F': ' '/^Server Name:/ {print $2; exit}')
      [ -n "$pulse_server" ] && kv "Pulse compatibility" "$pulse_server"
    fi
  else
    status_fail "PipeWire not running"
  fi
}

diagnose_output_config() {
  section "Output Configuration (Dual-Output Layer)"

  local output_conf="$AURABRIDGE_OUTPUT_CONF"

  subsection "Configured Output"
  if [ -f "$output_conf" ]; then
    local configured
    configured=$(output_configured_target)
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
  local effective target_sink default_sink
  effective=$(output_effective_target)
  target_sink=$(detect_output_sink)
  default_sink=$(default_sink_name)

  kv "Effective target" "$effective — $(describe_output_target)"
  if [ -n "$target_sink" ]; then
    status_ok "Selected physical sink detected"
    kv "Target sink" "$target_sink"
  else
    status_warn "Selected physical sink not detected"
  fi

  if [ -n "$default_sink" ]; then
    kv "Default sink" "$default_sink"
    if [ "$default_sink" = "$SAFE_SINK_NODE" ]; then
      status_ok "Default clients route through the Safe Sink"
    elif echo "$default_sink" | grep -qi "bcm2835\|headphones\|platform"; then
      status_info "Default clients currently route to onboard audio"
    elif echo "$default_sink" | grep -qi "fiio\|ka11\|meizu\|usb"; then
      status_info "Default clients currently route to USB DAC"
    else
      status_info "Default sink: $default_sink"
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
    "2972:0047") echo "FiiO KA11" ;;
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
  if have lsusb; then
    local usb_devices
    usb_devices=$(lsusb 2>/dev/null)

    if [ -z "$usb_devices" ]; then
      status_warn "No USB devices detected"
      return
    fi

    # Look for known audio DACs
    local fiio_found=0
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
  if have aplay; then
    local num_cards
    num_cards=$(aplay -l 2>/dev/null | grep -c "^card")

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
    if ! have pactl; then
      status_warn "pactl not available"
      return
    fi
    sinks=$(pactl_sinks_short)

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
    if have wpctl; then
      vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    fi
    if [ -z "$vol" ]; then
      vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null)
    fi
    if [ -n "$vol" ]; then
      echo "  $vol"
    else
      status_warn "Cannot read volume"
    fi

    subsection "Active Streams"
    local streams
    streams=$(pactl list sink-inputs short 2>/dev/null | head -n5)
    if [ -n "$streams" ]; then
      echo "$streams" | indent
    else
      status_info "No active playback streams"
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
    if [[ "$spotify_pid" =~ ^[0-9]+$ ]] && [ "$spotify_pid" != "0" ]; then
      status_ok "Running (PID $spotify_pid)"

      local started
      started=$(systemctl --user show -p ActiveEnterTimestamp --value librespot.service 2>/dev/null)
      [ -n "$started" ] && kv "Started" "$started"

      # Check for recent errors in log
      local recent_errors
      recent_errors=$(journalctl --user -u librespot.service -n 5 --no-pager 2>/dev/null | grep -ci "error")
      if [ "$recent_errors" -gt 0 ]; then
        status_warn "$recent_errors error(s) in recent logs"
      fi
    else
      status_ok "Running"
    fi
  else
    status_fail "Not running"
  fi

  subsection "AirPlay 2 (Phase 2)"
  echo "  shairport-sync: $(get_service_status shairport-sync.service)"
  echo "  nqptp:          $(get_service_status nqptp.service)"

  if is_service_active shairport-sync.service; then
    status_ok "Running"
    if is_service_active nqptp.service; then
      status_ok "NQPTP timing service running"
    else
      status_warn "NQPTP not running — AirPlay 2 timing/discovery may fail"
    fi
  else
    status_warn "Not running (audio backend issue)"
    # Show why it failed
    local last_error
    last_error=$(journalctl -u shairport-sync.service -n 3 --no-pager 2>/dev/null | grep -i "error\|fatal" | head -1)
    if [ -n "$last_error" ]; then
      echo "  Last error: ${last_error:0:80}..."
    fi
  fi

  subsection "Bluetooth (Phase 4 / optional)"
  echo "  bluetooth:      $(get_service_status bluetooth.service)"
  if have bluetoothctl; then
    local bt_show
    bt_show=$(with_timeout 2 bluetoothctl show 2>/dev/null || true)
    local bt_alias bt_powered bt_discoverable bt_pairable
    bt_alias=$(printf '%s\n' "$bt_show" | awk -F': ' '/Alias:/ {print $2; exit}')
    bt_powered=$(printf '%s\n' "$bt_show" | awk -F': ' '/Powered:/ {print $2; exit}')
    bt_discoverable=$(printf '%s\n' "$bt_show" | awk -F': ' '/Discoverable:/ {print $2; exit}')
    bt_pairable=$(printf '%s\n' "$bt_show" | awk -F': ' '/Pairable:/ {print $2; exit}')
    [ -n "$bt_alias" ] && kv "BT alias" "$bt_alias"
    [ -n "$bt_powered" ] && kv "BT powered" "$bt_powered"
    [ -n "$bt_discoverable" ] && kv "BT discoverable" "$bt_discoverable"
    [ -n "$bt_pairable" ] && kv "BT pairable" "$bt_pairable"
  else
    status_info "bluetoothctl not installed or not on PATH"
  fi

  subsection "System Services"
  echo "  avahi-daemon: $(get_service_status avahi-daemon)"
}

diagnose_android_casting() {
  section "Android Wireless Casting (DLNA / UPnP)"

  subsection "Receiver"
  echo "  gmrender:       $(get_user_service_status "$DLNA_UNIT")"
  if have gmediarender; then
    kv "Renderer binary" "$(command -v gmediarender)"
  else
    status_warn "gmediarender not installed"
  fi
  kv "Advertised name" "$(dlna_friendly_name)"

  case "$(android_cast_state)" in
    running)
      status_ok "Android DLNA/UPnP casting is running"
      ;;
    running-with-safety-warning)
      status_warn "DLNA is running, but Safe Sink verification is missing"
      ;;
    blocked)
      status_warn "DLNA installed but blocked by the Safe Sink safety gate"
      echo "  To unlock safely: ./scripts/setup-safe-sink.sh --apply && ./scripts/test-safe-sink.sh"
      ;;
    stopped)
      status_pending "DLNA installed and safe-gated, but stopped by design"
      echo "  Start manually when testing: systemctl --user start $DLNA_UNIT"
      ;;
    not-installed)
      status_pending "DLNA renderer not installed"
      echo "  Install after Safe Sink verification: ./scripts/install-dlna.sh"
      ;;
  esac

  subsection "Safety Gate"
  if safe_sink_verified; then
    status_ok "Safe Sink verified"
  else
    status_warn "Safe Sink not verified — DLNA should remain unavailable"
  fi

  if safe_sink_present; then
    status_ok "Safe Sink node present ($SAFE_SINK_NODE)"
  else
    status_warn "Safe Sink node not present"
  fi

  local default_sink
  default_sink=$(default_sink_name)
  if [ "$default_sink" = "$SAFE_SINK_NODE" ]; then
    status_ok "Default sink is the Safe Sink"
  elif [ -n "$default_sink" ]; then
    status_info "Default sink: $default_sink"
  else
    status_warn "Cannot read default sink"
  fi

  subsection "Discovery"
  status_info "This checks DLNA/UPnP media casting, not Chromecast or Miracast screen mirroring"

  local ssdp_route ssdp_dev
  ssdp_route=$(ip route get 239.255.255.250 2>/dev/null | head -n1)
  ssdp_dev=$(printf '%s\n' "$ssdp_route" | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')
  if [ -n "$ssdp_dev" ]; then
    status_ok "SSDP multicast route available via $ssdp_dev"
  else
    status_warn "Cannot determine SSDP multicast route"
  fi

  if have ss; then
    local ssdp_listener
    ssdp_listener=$(ss -H -lunp 2>/dev/null | grep -E '(:|\*)1900[[:space:]]' | head -n1)
    if [ -n "$ssdp_listener" ]; then
      status_ok "UDP/1900 listener present"
      echo "$ssdp_listener" | indent
    elif is_user_service_active "$DLNA_UNIT"; then
      status_warn "DLNA service active but no UDP/1900 listener found"
    else
      status_info "No UDP/1900 listener (expected while DLNA is stopped/blocked)"
    fi
  else
    status_info "ss not available; cannot inspect UDP listeners"
  fi
}

diagnose_audio_safety() {
  section "Audio Safety & Guardrails"

  subsection "Safe Sink (real-time fixed-gain cap)"
  if safe_sink_present; then
    status_ok "Safe Sink node present ($SAFE_SINK_NODE)"
  else
    status_warn "Safe Sink node not present"
  fi

  if safe_sink_verified; then
    status_ok "Safe Sink verification marker found"
    grep -E '^(SAFE_SINK_VERIFIED|dangerous_at_100pct|gain|timestamp)=' "$SAFE_SINK_MARKER" 2>/dev/null | indent
  else
    status_warn "Safe Sink is not verified"
  fi

  local default_sink
  default_sink=$(default_sink_name)
  if [ "$default_sink" = "$SAFE_SINK_NODE" ]; then
    status_ok "Default sink is protected by the Safe Sink"
  elif [ -n "$default_sink" ]; then
    status_info "Default sink bypasses Safe Sink: $default_sink"
  else
    status_warn "Cannot read default sink"
  fi

  subsection "Volume Guard (recovery/audit only)"
  echo "  aurabridge-volume-guard.timer:   $(get_user_service_status aurabridge-volume-guard.timer)"
  echo "  aurabridge-volume-guard.service: $(get_user_service_status aurabridge-volume-guard.service)"
}

diagnose_system_health() {
  section "System Health Checks"

  subsection "Thermal / Power"
  if have vcgencmd; then
    local temp throttled
    temp=$(vcgencmd measure_temp 2>/dev/null | cut -d= -f2)
    throttled=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
    [ -n "$temp" ] && kv "Temperature" "$temp"
    if [ "$throttled" = "0x0" ]; then
      status_ok "No throttling or undervoltage flags"
    elif [ -n "$throttled" ]; then
      status_warn "Throttling/undervoltage flags: $throttled"
    fi
  elif [ -r /sys/class/thermal/thermal_zone0/temp ]; then
    local temp_c
    temp_c=$(awk '{printf "%.1f°C", $1 / 1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    [ -n "$temp_c" ] && kv "Temperature" "$temp_c"
    status_info "vcgencmd not available; throttling flags unavailable"
  else
    status_info "Thermal sensors unavailable"
  fi

  subsection "Storage / Memory"
  local root_pct root_disk mem_avail_pct
  root_pct=$(df -P / 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5}')
  root_disk=$(df -h / 2>/dev/null | awk 'NR==2 {printf "Used: %s / %s (%s)", $3, $2, $5}')
  [ -n "$root_disk" ] && kv "Root filesystem" "$root_disk"
  if [ -n "$root_pct" ]; then
    if [ "$root_pct" -ge 90 ]; then
      status_fail "Root filesystem is critically full"
    elif [ "$root_pct" -ge 80 ]; then
      status_warn "Root filesystem is getting full"
    else
      status_ok "Root filesystem has space"
    fi
  fi

  mem_avail_pct=$(free 2>/dev/null | awk '/^Mem:/ {printf "%d", ($7 / $2) * 100}')
  if [ -n "$mem_avail_pct" ]; then
    if [ "$mem_avail_pct" -lt 10 ]; then
      status_warn "Low available memory (${mem_avail_pct}%)"
    else
      status_ok "Memory available (${mem_avail_pct}%)"
    fi
  fi

  subsection "Systemd / Clock"
  local system_failed user_failed system_failed_lines user_failed_lines
  system_failed=$(systemctl --failed --no-legend 2>/dev/null | awk 'END {print NR + 0}')
  user_failed=$(systemctl --user --failed --no-legend 2>/dev/null | awk 'END {print NR + 0}')
  if [ "${system_failed:-0}" -eq 0 ] && [ "${user_failed:-0}" -eq 0 ]; then
    status_ok "No failed systemd units"
  else
    status_warn "Failed units: system=$system_failed user=$user_failed"
    system_failed_lines=$(systemctl --failed --no-legend 2>/dev/null | head -n5)
    user_failed_lines=$(systemctl --user --failed --no-legend 2>/dev/null | head -n5)
    if [ -n "$system_failed_lines" ]; then
      echo "  System failed units:"
      echo "$system_failed_lines" | indent
    fi
    if [ -n "$user_failed_lines" ]; then
      echo "  User failed units:"
      echo "$user_failed_lines" | indent
    fi
  fi

  if have timedatectl; then
    local ntp_sync
    ntp_sync=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [ "$ntp_sync" = "yes" ]; then
      status_ok "Clock synchronized"
    elif [ -n "$ntp_sync" ]; then
      status_warn "Clock not synchronized"
    fi
  fi

  local root_opts
  root_opts=$(findmnt -no OPTIONS / 2>/dev/null)
  if echo "$root_opts" | grep -qw "rw"; then
    kv "Root mount" "read-write"
  elif echo "$root_opts" | grep -qw "ro"; then
    kv "Root mount" "read-only"
  fi

  if [ -f /var/run/reboot-required ]; then
    status_warn "Reboot required by package updates"
  fi
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
    echo "$spotify_errors" | indent
  else
    status_ok "No errors"
  fi

  subsection "AirPlay (shairport-sync)"
  local airplay_errors
  airplay_errors=$(journalctl -u shairport-sync --since "24 hours ago" --no-pager 2>/dev/null | grep -i "error\|warn\|fail" | tail -3)
  if [ -n "$airplay_errors" ]; then
    echo "$airplay_errors" | indent
  else
    status_ok "No errors"
  fi

  subsection "Android DLNA (gmrender)"
  local dlna_errors
  dlna_errors=$(journalctl --user -u "$DLNA_UNIT" --since "24 hours ago" --no-pager 2>/dev/null | grep -i "error\|warn\|fail" | tail -3)
  if [ -n "$dlna_errors" ]; then
    echo "$dlna_errors" | indent
  else
    status_ok "No errors"
  fi

  subsection "PipeWire"
  local pw_errors
  pw_errors=$(journalctl --user -u pipewire.service --since "24 hours ago" --no-pager 2>/dev/null | grep -i "error\|warn\|critical" | tail -3)
  if [ -n "$pw_errors" ]; then
    echo "$pw_errors" | indent
  else
    status_ok "No critical errors"
  fi
}

diagnose_summary() {
  section "Quick Summary"

  local score=0
  local total=11

  # Core health score. Optional receivers are summarized separately below.
  is_user_service_active pipewire.service && ((score++)) || true
  is_user_service_active wireplumber.service && ((score++)) || true
  is_user_service_active pipewire-pulse.service && ((score++)) || true
  is_user_service_active librespot.service && ((score++)) || true
  [ -n "$(detect_output_sink)" ] && ((score++)) || true
  [ -n "$(default_sink_name)" ] && ((score++)) || true
  [ -f "$AURABRIDGE_OUTPUT_CONF" ] && ((score++)) || true
  is_service_active avahi-daemon && ((score++)) || true
  have pactl && ((score++)) || true
  [ "$(hostname -I 2>/dev/null | wc -w)" -gt 0 ] && ((score++)) || true

  local root_pct
  root_pct=$(df -P / 2>/dev/null | awk 'NR==2 {gsub("%", "", $5); print $5}')
  if [ -n "$root_pct" ] && [ "$root_pct" -lt 90 ]; then
    ((score++)) || true
  fi

  if [ "$score" -eq "$total" ]; then
    status_ok "Core systems nominal ($score/$total) — Ready for playback"
  elif [ "$score" -ge 8 ]; then
    status_info "Core systems mostly operational ($score/$total) — Functional, minor issues"
  elif [ "$score" -ge 5 ]; then
    status_warn "Partial core functionality ($score/$total) — Some services or outputs need attention"
  else
    status_fail "Critical core issues ($score/$total) — Check above for details"
  fi

  kv "Android DLNA casting" "$(android_cast_summary)"

  echo ""
  echo "═════════════════════════════════════════════════════════════"

  # Recommendations
  if ! is_user_service_active librespot.service; then
    echo "⚠️  Spotify not running. Try:"
    echo "    systemctl --user restart librespot.service"
  fi

  if ! is_service_active shairport-sync.service; then
    echo "ℹ️  AirPlay 2 is not running. Check:"
    echo "    journalctl -u shairport-sync -n 30 --no-pager"
  fi

  case "$(android_cast_state)" in
    running)
      echo "✅ Android DLNA casting is available as: $(dlna_friendly_name)"
      ;;
    running-with-safety-warning)
      echo "⚠️  Android DLNA is running, but Safe Sink verification is missing."
      ;;
    blocked)
      echo "⚠️  Android DLNA is blocked until Safe Sink verification succeeds."
      echo "    Run: ./scripts/setup-safe-sink.sh --apply && ./scripts/test-safe-sink.sh"
      ;;
    stopped)
      echo "ℹ️  Android DLNA is installed but stopped by design."
      echo "    Start manually: systemctl --user start $DLNA_UNIT"
      ;;
    not-installed)
      echo "ℹ️  Android DLNA receiver is not installed."
      echo "    After Safe Sink verification: ./scripts/install-dlna.sh"
      ;;
  esac

  local output
  output=$(output_configured_target)
  echo "ℹ️  Current output mode: $output"
  echo "    To switch: ./scripts/select-output.sh [onboard|usb|auto]"
}

# ============================================================================
# OUTPUT MODES
# ============================================================================

case "$MODE" in
  brief)
    diagnose_system_info
    diagnose_network
    diagnose_services
    diagnose_android_casting
    diagnose_system_health
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
    diagnose_android_casting
    diagnose_audio_safety
    diagnose_system_health
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
    diagnose_android_casting
    diagnose_audio_safety
    diagnose_system_health
    diagnose_summary
    ;;
esac

exit 0
