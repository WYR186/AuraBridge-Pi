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
# Protocol-level PAUSE on barge-in (so the displaced phone shows "paused", not
# just goes silent). We send Pause, NOT Stop — Pause is gentle (the session stays
# and the user can resume); Stop disconnects AirPlay and was the thing that broke
# it before. Muting is always the guaranteed floor; pause is the polite extra.
#
#   - DLNA pause: ON by default. UPnP AVTransport::Pause is clean and low-risk;
#     a subscribed control point (BubbleUPnP / Hi-Fi Cast) reflects the pause.
#   - AirPlay pause: OFF by default. Needs shairport-sync built --with-dbus
#     (AURABRIDGE_AIRPLAY_DBUS=1 ./scripts/install-airplay2.sh) and must be
#     validated on the Pi first, because this is the path that broke AirPlay.
#   - Spotify: there is NO option — stock librespot has no remote-control API, so
#     a displaced Spotify can only be muted (it keeps "playing" silently).
ARB_DLNA_PAUSE="${AURABRIDGE_ARBITER_DLNA_PAUSE:-1}"
ARB_AIRPLAY_PAUSE="${AURABRIDGE_ARBITER_AIRPLAY_PAUSE:-0}"
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

# --- protocol-level PAUSE (best effort; per-protocol capability differs) ------

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

# Post a SOAP AVTransport action (Pause / Stop) to the DLNA renderer. Best effort.
_arb_dlna_soap() {
  local action="$1"
  arb_have curl || return 1
  local url; url="$(arb_dlna_control_url)" || return 1
  local body
  body='<?xml version="1.0" encoding="utf-8"?>'
  body+='<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"'
  body+=' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">'
  body+="<s:Body><u:${action} xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"
  body+="<InstanceID>0</InstanceID></u:${action}></s:Body></s:Envelope>"
  curl -fsS --max-time 2 \
    -H 'Content-Type: text/xml; charset="utf-8"' \
    -H "SOAPAction: \"urn:schemas-upnp-org:service:AVTransport:1#${action}\"" \
    -d "$body" "$url" >/dev/null 2>&1
}

# DLNA: pause the renderer. A subscribed control point reflects "paused" via GENA
# eventing and the user can resume. Gentle and reversible (no disconnect).
arb_dlna_pause() { _arb_dlna_soap Pause; }

# AirPlay: shairport-sync exposes a native D-Bus RemoteControl interface ONLY if
# it was built --with-dbus (opt-in: AURABRIDGE_AIRPLAY_DBUS=1 install-airplay2.sh).
# It may live on the system bus (shairport runs as a system service) or the
# session bus, so try both. We send Pause, NOT Stop: Pause asks the iPhone to
# pause (session stays, resumable); Stop disconnects it (the old breakage).
arb_airplay_pause() {
  arb_have dbus-send || return 1
  dbus-send --system --print-reply --dest="$ARB_SPS_DBUS_DEST" \
    "$ARB_SPS_DBUS_OBJ" "${ARB_SPS_DBUS_IFACE}.Pause" >/dev/null 2>&1 && return 0
  dbus-send --session --print-reply --dest="$ARB_SPS_DBUS_DEST" \
    "$ARB_SPS_DBUS_OBJ" "${ARB_SPS_DBUS_IFACE}.Pause" >/dev/null 2>&1 && return 0
  return 1
}

_arb_on() { case "$1" in 1|yes|true|on) return 0 ;; *) return 1 ;; esac; }

# Best-effort: tell the displaced source's phone to PAUSE, per-protocol policy.
# Returns 0 only if a pause was actually sent. Spotify has no API (mute only).
# This is the "polite extra" on top of muting; muting is the guaranteed floor.
arb_protocol_preempt() {
  case "$1" in
    dlna)    _arb_on "$ARB_DLNA_PAUSE"    && arb_dlna_pause ;;
    airplay) _arb_on "$ARB_AIRPLAY_PAUSE" && arb_airplay_pause ;;
    *)       return 1 ;;
  esac
}
