#!/usr/bin/env bash
set -euo pipefail

cmd="${MOCK_COMMAND:-$(basename "$0")}"
bin_dir="$(cd "$(dirname "$0")" && pwd)"
case_name="${MOCK_CASE:-$(basename "$(dirname "$bin_dir")")}"

ka11_present=0
pipewire_present=1
wp_version="0.5.6"
services_present=0

case "$case_name" in
  case-ka11-present)
    ka11_present=1 ;;
  case-ka11-missing)
    ka11_present=0 ;;
  case-pipewire-missing)
    ka11_present=1
    pipewire_present=0 ;;
  case-wireplumber-04)
    ka11_present=1
    wp_version="0.4.17" ;;
  case-wireplumber-05)
    ka11_present=1
    wp_version="0.5.6" ;;
  case-services-present)
    ka11_present=1
    services_present=1 ;;
  *)
    echo "unknown mock case: $case_name" >&2
    exit 127 ;;
esac

print_lsusb() {
  cat <<USB
Bus 001 Device 001: ID 1d6b:0002 Linux Foundation 2.0 root hub
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
USB
  if [[ "$ka11_present" -eq 1 ]]; then
    echo "Bus 001 Device 004: ID 2972:0047 FiiO Electronics Technology KA11 USB DAC"
  fi
}

print_aplay_l() {
  if [[ "$ka11_present" -eq 1 ]]; then
    cat <<APLAY
**** List of PLAYBACK Hardware Devices ****
card 0: vc4hdmi [vc4-hdmi], device 0: MAI PCM i2s-hifi-0 [MAI PCM i2s-hifi-0]
  Subdevices: 1/1
  Subdevice #0: subdevice #0
card 2: KA11 [FiiO KA11 USB DAC], device 0: USB Audio [USB Audio]
  Subdevices: 1/1
  Subdevice #0: subdevice #0
APLAY
  else
    cat <<APLAY
**** List of PLAYBACK Hardware Devices ****
card 0: vc4hdmi [vc4-hdmi], device 0: MAI PCM i2s-hifi-0 [MAI PCM i2s-hifi-0]
  Subdevices: 1/1
  Subdevice #0: subdevice #0
APLAY
  fi
}

print_aplay_L() {
  cat <<APLAYL
default
    Playback/recording through the PulseAudio sound server
sysdefault:CARD=vc4hdmi
    vc4-hdmi, MAI PCM i2s-hifi-0
APLAYL
  if [[ "$ka11_present" -eq 1 ]]; then
    cat <<APLAYL
sysdefault:CARD=KA11
    FiiO KA11 USB DAC, USB Audio
front:CARD=KA11,DEV=0
    FiiO KA11 USB DAC, USB Audio
APLAYL
  fi
}

print_wpctl_status() {
  [[ "$pipewire_present" -eq 1 ]] || return 1
  cat <<WP
PipeWire 'pipewire-0' [1.0.5, mock@aurabridge, cookie:123456]
 └─ Clients:
        31. WirePlumber                         [1.0.5, mock@aurabridge]
Audio
 ├─ Devices:
 │      40. Built-in Audio                      [alsa]
WP
  if [[ "$ka11_present" -eq 1 ]]; then
    cat <<WP
 │      52. FiiO KA11 USB DAC                   [alsa]
 ├─ Sinks:
 │  *   60. FiiO KA11 USB DAC Analog Stereo     [vol: 0.30]
WP
  else
    cat <<WP
 ├─ Sinks:
 │  *   41. Built-in HDMI Stereo                [vol: 0.30]
WP
  fi
  cat <<WP
 └─ Sources:
        70. Monitor of Default Sink             [vol: 1.00]
WP
}

print_pactl_sinks() {
  [[ "$pipewire_present" -eq 1 ]] || return 1
  if [[ "$ka11_present" -eq 1 ]]; then
    printf '60\talsa_output.usb-FiiO_KA11_USB_DAC-00.analog-stereo\tPipeWire\ts16le 2ch 48000Hz\tRUNNING\n'
  else
    printf '41\talsa_output.platform-vc4_hdmi.stereo\tPipeWire\ts16le 2ch 48000Hz\tIDLE\n'
  fi
}

print_pactl_info() {
  [[ "$pipewire_present" -eq 1 ]] || return 1
  cat <<PACTL
Server String: /run/user/1000/pulse/native
Library Protocol Version: 35
Server Protocol Version: 35
Is Local: yes
Client Index: 77
Server Name: PulseAudio (on PipeWire 1.0.5)
Default Sink: $(if [[ "$ka11_present" -eq 1 ]]; then echo 'alsa_output.usb-FiiO_KA11_USB_DAC-00.analog-stereo'; else echo 'alsa_output.platform-vc4_hdmi.stereo'; fi)
PACTL
}

systemctl_cat() {
  local unit="${1:-}"
  if [[ "$services_present" -eq 1 ]]; then
    case "$unit" in
      shairport-sync.service|nqptp.service|bluetooth.service|librespot.service|pipewire.service|pipewire-pulse.service|wireplumber.service)
        echo "# mock unit $unit"
        return 0 ;;
    esac
  fi
  case "$unit" in
    pipewire.service|pipewire-pulse.service|wireplumber.service)
      [[ "$pipewire_present" -eq 1 ]] || return 1
      echo "# mock user unit $unit"
      return 0 ;;
  esac
  return 1
}

systemctl_active() {
  local unit="${1:-}"
  if [[ "$services_present" -eq 1 ]]; then
    case "$unit" in
      shairport-sync.service|nqptp.service|bluetooth.service|librespot.service|pipewire.service|pipewire-pulse.service|wireplumber.service)
        echo active
        return 0 ;;
    esac
  fi
  case "$unit" in
    pipewire.service|pipewire-pulse.service|wireplumber.service)
      if [[ "$pipewire_present" -eq 1 ]]; then echo active; return 0; fi ;;
  esac
  echo inactive
  return 3
}

case "$cmd" in
  lsusb)
    print_lsusb ;;
  aplay)
    case "${1:-}" in
      -l) print_aplay_l ;;
      -L) print_aplay_L ;;
      *) echo "mock aplay supports -l and -L" >&2; exit 1 ;;
    esac ;;
  amixer)
    echo "Simple mixer control 'PCM',0"
    echo "Simple mixer control 'Speaker',0" ;;
  pipewire)
    [[ "$pipewire_present" -eq 1 ]] || { echo "pipewire: command unavailable in mock" >&2; exit 127; }
    if [[ "${1:-}" == "--version" ]]; then echo "pipewire 1.0.5"; else echo "mock pipewire"; fi ;;
  wireplumber)
    [[ "$pipewire_present" -eq 1 ]] || { echo "wireplumber: command unavailable in mock" >&2; exit 127; }
    if [[ "${1:-}" == "--version" ]]; then echo "wireplumber $wp_version"; else echo "mock wireplumber"; fi ;;
  wpctl)
    [[ "$pipewire_present" -eq 1 ]] || { echo "wpctl: PipeWire remote not available" >&2; exit 1; }
    case "${1:-}" in
      status) print_wpctl_status ;;
      get-volume) echo "Volume: 0.30" ;;
      set-volume|set-mute) exit 0 ;;
      *) echo "mock wpctl: $*" ;;
    esac ;;
  pactl)
    [[ "$pipewire_present" -eq 1 ]] || { echo "Connection failure: Connection refused" >&2; exit 1; }
    if [[ "${1:-}" == "info" ]]; then
      print_pactl_info
    elif [[ "${1:-}" == "get-default-sink" ]]; then
      if [[ "$ka11_present" -eq 1 ]]; then echo "alsa_output.usb-FiiO_KA11_USB_DAC-00.analog-stereo"; else echo "alsa_output.platform-vc4_hdmi.stereo"; fi
    elif [[ "${1:-}" == "list" && "${2:-}" == "sinks" && "${3:-}" == "short" ]]; then
      print_pactl_sinks
    elif [[ "${1:-}" == "list" && "${2:-}" == "sink-inputs" ]]; then
      echo "Sink Input #101"
      printf '\tmedia.name = "mock stream"\n'
    else
      echo "mock pactl: $*"
    fi ;;
  systemctl)
    user_mode=0
    if [[ "${1:-}" == "--user" ]]; then user_mode=1; shift; fi
    sub="${1:-}"; shift || true
    case "$sub" in
      cat) systemctl_cat "${1:-}" ;;
      is-active) systemctl_active "${1:-}" ;;
      status)
        unit="${1:-unknown.service}"
        echo "● $unit - mock service"
        echo "   Loaded: loaded (/mock/$unit; enabled; preset: enabled)"
        if systemctl_active "$unit" >/dev/null; then echo "   Active: active (running)"; else echo "   Active: inactive (dead)"; fi ;;
      list-unit-files)
        echo "pipewire.service enabled"
        echo "pipewire-pulse.service enabled"
        echo "wireplumber.service enabled" ;;
      *) echo "mock systemctl user=$user_mode sub=$sub $*" ;;
    esac ;;
  journalctl)
    echo "Jun 01 12:00:00 aurabridge mock[$$]: no critical errors in mock journal" ;;
  hostname)
    if [[ "${1:-}" == "-I" ]]; then echo "192.168.1.50 "; else echo "aurabridge-mock"; fi ;;
  ip)
    echo "default via 192.168.1.1 dev eth0 src 192.168.1.50" ;;
  *)
    echo "mock command not implemented: $cmd" >&2
    exit 127 ;;
esac
