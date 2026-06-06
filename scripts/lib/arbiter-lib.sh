#!/usr/bin/env bash
# arbiter-lib.sh — shared helpers for the AuraBridge source arbiter.
#
# Source it; do NOT run it directly. It only inspects the PipeWire graph (through
# the PulseAudio API of pipewire-pulse) and sends best-effort "stop" commands to
# wireless sources. It never raises volume, so it is safe with respect to the
# project's speaker-safety rules (see docs/volume-safety.md).
#
# Two planes, kept separate on purpose (see docs/source-arbiter.md):
#   - DISCOVERY plane: AirPlay (mDNS), Spotify (Avahi zeroconf) and DLNA (SSDP)
#     advertise on independent buses. They are ALWAYS visible at the same time;
#     this library never touches discovery.
#   - PLAYBACK plane: PipeWire MIXES by default. This library is what turns that
#     into barge-in (newest source wins) at playback time only.
#
# Source classification is by the sink-input's PulseAudio properties, never by a
# hardcoded sink-input index.

# --- tunables ----------------------------------------------------------------
# DLNA renderer HTTP/SOAP port; must match gmrender.service --port.
ARB_DLNA_PORT="${DLNA_HTTP_PORT:-49494}"
# Optional override for nonstandard gmrender binding, e.g.
# http://192.168.50.151:49494. If unset, probe localhost and local IPv4 addrs.
ARB_DLNA_BASE_URL="${AURABRIDGE_ARBITER_DLNA_BASE_URL:-}"
# Protocol-level Stop is intentionally OFF by default. It can make sender UIs
# (especially AirPlay and DLNA control points) look like they were disconnected,
# even though discovery remains available. The safe default is playback-plane
# arbitration only: mute losers locally, do not tell phones to stop.
ARB_PROTOCOL_STOP="${AURABRIDGE_ARBITER_PROTOCOL_STOP:-0}"
# shairport-sync native D-Bus interface (present only if built --with-dbus).
ARB_SPS_DBUS_DEST="org.gnome.ShairportSync"
ARB_SPS_DBUS_OBJ="/org/gnome/ShairportSync"
ARB_SPS_DBUS_IFACE="org.gnome.ShairportSync.RemoteControl"

arb_have() { command -v "$1" >/dev/null 2>&1; }

# --- sink-input inspection ---------------------------------------------------

# Print the verbose property block for ONE sink-input id (everything from its
# "Sink Input #<id>" header up to the next header / EOF). Empty if it is gone.
_arb_input_block() {
  local id="$1"
  pactl list sink-inputs 2>/dev/null | awk -v id="$id" '
    $0 ~ ("^Sink Input #" id "$") { grab = 1; print; next }
    /^Sink Input #/               { grab = 0 }
    grab                          { print }
  '
}

# Extract a single field value (e.g. "Corked:" -> "no") from a property block.
_arb_field() {
  local block="$1" key="$2"
  printf '%s\n' "$block" \
    | sed -nE "s/^[[:space:]]*${key}[[:space:]]*//p" \
    | head -n1
}

# Classify a property block -> airplay | spotify | dlna | "" (not ours).
_arb_classify_block() {
  local hay
  hay="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  if   printf '%s' "$hay" | grep -qE 'shairport|airplay'; then echo airplay
  elif printf '%s' "$hay" | grep -qE 'librespot|spotify'; then echo spotify
  elif printf '%s' "$hay" | grep -qE 'gmediarender|gmrender|aura studio 3 dlna'; then echo dlna
  else echo ""
  fi
}

# Classify a sink-input by id -> airplay | spotify | dlna | "".
arb_source_of() {
  _arb_classify_block "$(_arb_input_block "$1")"
}

# List every managed sink-input as "id|source|corked|mute", in pactl order
# (ascending id, so the LAST line that is playing is the most recently created).
# "Corked: no" means the stream is actively playing (PulseAudio has no RUNNING
# state for sink-inputs — corked is the pause flag).
arb_managed_inputs() {
  arb_have pactl || return 0
  local id block src corked mute
  while read -r id _; do
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    block="$(_arb_input_block "$id")"
    src="$(_arb_classify_block "$block")"
    [[ -z "$src" ]] && continue
    corked="$(_arb_field "$block" 'Corked:')"
    mute="$(_arb_field "$block" 'Mute:')"
    printf '%s|%s|%s|%s\n' "$id" "$src" "${corked:-unknown}" "${mute:-unknown}"
  done < <(pactl list short sink-inputs 2>/dev/null)
}

# --- PipeWire-level suppression (the guaranteed floor) -----------------------

arb_mute_input()   { arb_have pactl && pactl set-sink-input-mute "$1" 1 >/dev/null 2>&1 || true; }
arb_unmute_input() { arb_have pactl && pactl set-sink-input-mute "$1" 0 >/dev/null 2>&1 || true; }

# --- protocol-level Stop (best effort; per-protocol capability differs) -------

# DLNA: discover the AVTransport controlURL from the renderer's device
# description (cached), then POST a SOAP Stop. Returns non-zero on any failure;
# the caller falls back to muting.
_ARB_DLNA_CTRL=""
arb_dlna_control_url() {
  [[ -n "$_ARB_DLNA_CTRL" ]] && { printf '%s' "$_ARB_DLNA_CTRL"; return 0; }
  arb_have curl || return 1
  local desc="" path ctrl base found_base="" ip
  local bases=()
  [[ -n "$ARB_DLNA_BASE_URL" ]] && bases+=("${ARB_DLNA_BASE_URL%/}")
  bases+=("http://127.0.0.1:${ARB_DLNA_PORT}")
  if arb_have hostname; then
    while read -r ip; do
      [[ -n "$ip" ]] && bases+=("http://${ip}:${ARB_DLNA_PORT}")
    done < <(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9.]+$' || true)
  fi
  for base in "${bases[@]}"; do
    for path in /description.xml /rootDesc.xml /upnp/description.xml /; do
      desc="$(curl -fsS --max-time 2 "${base}${path}" 2>/dev/null)" && [[ -n "$desc" ]] && {
        found_base="$base"
        break 2
      }
      desc=""
    done
  done
  [[ -n "$desc" ]] || return 1
  # Take the <controlURL> from the same <service> block as AVTransport. Do not
  # rely on XML newlines or use a loose "first controlURL after AVTransport"
  # scan; gmrender also exposes ConnectionManager/RenderingControl.
  ctrl="$(printf '%s' "$desc" \
    | tr '\r\n' '  ' \
    | awk '
        BEGIN { RS = "</service>"; ORS = "" }
        /<service[ >]/ && /urn:schemas-upnp-org:service:AVTransport:1/ {
          block = $0
          if (block ~ /<controlURL>/) {
            sub(/.*<controlURL>/, "", block)
            sub(/<\/controlURL>.*/, "", block)
            print block
            exit
          }
        }')"
  [[ -n "$ctrl" ]] || return 1
  case "$ctrl" in
    http*) _ARB_DLNA_CTRL="$ctrl" ;;
    /*)    _ARB_DLNA_CTRL="${found_base}${ctrl}" ;;
    *)     _ARB_DLNA_CTRL="${found_base}/${ctrl}" ;;
  esac
  printf '%s' "$_ARB_DLNA_CTRL"
}

arb_dlna_stop() {
  arb_have curl || return 1
  local url; url="$(arb_dlna_control_url)" || return 1
  local body
  body='<?xml version="1.0" encoding="utf-8"?>'
  body+='<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
  body+=' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
  body+='<s:Body><u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
  body+='<InstanceID>0</InstanceID></u:Stop></s:Body></s:Envelope>'
  curl -fsS --max-time 2 \
    -H 'Content-Type: text/xml; charset="utf-8"' \
    -H 'SOAPAction: "urn:schemas-upnp-org:service:AVTransport:1#Stop"' \
    -d "$body" "$url" >/dev/null 2>&1
}

# AirPlay: shairport-sync exposes a native D-Bus RemoteControl interface ONLY if
# it was built with --with-dbus (install-airplay2.sh now adds that flag). It may
# live on the system bus (shairport runs as a system service) or the session
# bus, so try both. RemoteControl.Stop tells the AirPlay sender (the iPhone) to
# stop — genuine barge-in, not just local muting.
arb_airplay_stop() {
  arb_have dbus-send || return 1
  dbus-send --system --print-reply --dest="$ARB_SPS_DBUS_DEST" \
    "$ARB_SPS_DBUS_OBJ" "${ARB_SPS_DBUS_IFACE}.Stop" >/dev/null 2>&1 && return 0
  dbus-send --session --print-reply --dest="$ARB_SPS_DBUS_DEST" \
    "$ARB_SPS_DBUS_OBJ" "${ARB_SPS_DBUS_IFACE}.Stop" >/dev/null 2>&1 && return 0
  return 1
}

# Spotify: stock librespot exposes NO remote-control API, so there is no clean
# protocol-level stop. The arbiter falls back to muting its sink-input (the
# Spotify app keeps "playing" silently). Documented limitation.
arb_spotify_stop() { return 1; }

# Dispatch a best-effort protocol stop. Returns 0 if a stop was actually sent.
arb_protocol_stop() {
  case "$ARB_PROTOCOL_STOP" in
    1|yes|true|on) ;;
    *) return 1 ;;
  esac
  case "$1" in
    airplay) arb_airplay_stop ;;
    dlna)    arb_dlna_stop ;;
    spotify) arb_spotify_stop ;;
    *)       return 1 ;;
  esac
}
