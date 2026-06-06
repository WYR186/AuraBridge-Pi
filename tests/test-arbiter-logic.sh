#!/usr/bin/env bash
set -uo pipefail

# test-arbiter-logic.sh — pure-logic unit tests for the source arbiter.
#
# Sources scripts/source-arbiter.sh (its BASH_SOURCE guard stops arbiter_main
# from running) and drives reconcile() against a stateful `pactl` MOCK. No real
# PipeWire, no hardware. The key assertion is the regression guard: a single
# playing source is NEVER muted (that is what broke AirPlay before).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

passes=0
failures=0
ok()   { printf '[arb-test][PASS] %s\n' "$*"; passes=$((passes + 1)); }
fail() { printf '[arb-test][FAIL] %s\n' "$*" >&2; failures=$((failures + 1)); }

# --- stateful pactl mock -----------------------------------------------------
# MOCK holds one "id|src|corked|mute" line per sink-input.
MOCK=""

_mock_appname() {
  case "$1" in
    airplay) printf 'Shairport Sync' ;;
    spotify) printf 'librespot' ;;
    dlna)    printf 'gmediarender' ;;
    *)       printf 'OtherApp' ;;
  esac
}

# Replaces the real `pactl` for the lib's helpers (shell functions shadow commands).
pactl() {
  local id src corked mute
  if [[ "$1" == "info" ]]; then
    return 0
  fi
  if [[ "$1" == "list" && "$2" == "short" && "$3" == "sink-inputs" ]]; then
    while IFS='|' read -r id src corked mute; do
      [[ -n "$id" ]] && printf '%s\t1\t40\tprotocol-native.c\ts16le 2ch 44100Hz\n' "$id"
    done < <(printf '%s\n' "$MOCK")
    return 0
  fi
  if [[ "$1" == "list" && "$2" == "sink-inputs" ]]; then
    while IFS='|' read -r id src corked mute; do
      [[ -n "$id" ]] || continue
      printf 'Sink Input #%s\n\tMute: %s\n\tCorked: %s\n\tProperties:\n\t\tapplication.name = "%s"\n' \
        "$id" "$mute" "$corked" "$(_mock_appname "$src")"
    done < <(printf '%s\n' "$MOCK")
    return 0
  fi
  if [[ "$1" == "set-sink-input-mute" ]]; then
    local tid="$2" val="$3" newmute out=""
    [[ "$val" == "1" ]] && newmute=yes || newmute=no
    while IFS='|' read -r id src corked mute; do
      [[ -n "$id" ]] || continue
      [[ "$id" == "$tid" ]] && mute="$newmute"
      out="${out}${id}|${src}|${corked}|${mute}"$'\n'
    done < <(printf '%s\n' "$MOCK")
    MOCK="$out"
    return 0
  fi
  return 0
}

# Helpers to set up / inspect the mock graph.
set_graph() { MOCK="$(printf '%s\n' "$@")"; }
mute_of()   { awk -F'|' -v id="$1" '$1==id{print $4}' < <(printf '%s\n' "$MOCK"); }
reset_state() { _ord=0; _seen=""; _muted=""; }

# shellcheck source=../scripts/source-arbiter.sh
. "$REPO_ROOT/scripts/source-arbiter.sh"

# Make sure protocol-level Pause never fires during logic tests (no curl/dbus).
ARB_DLNA_PAUSE=0
ARB_AIRPLAY_PAUSE=0

assert_mute() { # id expected label
  local got; got="$(mute_of "$1")"
  if [[ "$got" == "$2" ]]; then ok "$3 (input #$1 mute=$got)"; else fail "$3 (input #$1 mute=$got, expected $2)"; fi
}

expect_eq() { # actual expected label
  if [[ "$1" == "$2" ]]; then ok "$3"; else fail "$3 (got '$1', want '$2')"; fi
}

# === T1: single source is NEVER muted (the regression guard) =================
reset_state
set_graph "10|airplay|no|no"
reconcile
assert_mute 10 no "single AirPlay not muted"
reconcile   # idempotent: still untouched
assert_mute 10 no "single AirPlay still not muted after re-reconcile"

# === T2: barge-in = newest START wins, not lowest id ========================
reset_state
set_graph "11|spotify|no|no"
reconcile                         # only Spotify playing -> ordinal 1, no mute
assert_mute 11 no "lone Spotify not muted"
set_graph "11|spotify|no|no" "10|airplay|no|no"   # AirPlay starts AFTER Spotify
reconcile
assert_mute 11 yes "older Spotify muted when AirPlay barges in"
assert_mute 10 no  "newer AirPlay stays audible (newest start wins, not lowest id)"

# === T3: when the winner stops, the remaining source is auto-unmuted ========
set_graph "11|spotify|no|yes"     # AirPlay #10 removed; Spotify still muted by us
reconcile
assert_mute 11 no "remaining Spotify auto-unmuted after winner left"

# === T4: a no-op event on a muted background source does not resteal ========
reset_state
set_graph "10|airplay|no|no" "11|spotify|no|no" "12|dlna|no|no"
reconcile                         # DLNA #12 newest -> winner; 10,11 muted
assert_mute 12 no  "DLNA winner audible"
assert_mute 10 yes "AirPlay muted under DLNA"
assert_mute 11 yes "Spotify muted under DLNA"
reconcile                         # idempotent re-reconcile (e.g. metadata tick)
assert_mute 12 no  "winner unchanged after re-reconcile"
assert_mute 10 yes "AirPlay still muted (no resteal)"
assert_mute 11 yes "Spotify still muted (no resteal)"

# === T5: unmute_all releases everything (stop/reset path) ====================
unmute_all
assert_mute 10 no "unmute_all releases AirPlay"
assert_mute 11 no "unmute_all releases Spotify"
assert_mute 12 no "unmute_all releases DLNA"

# === T6: protocol PAUSE dispatcher honours per-protocol policy ===============
# Stub the actual pause calls so no curl/dbus runs; record what was invoked.
PAUSED=""
arb_dlna_pause()    { PAUSED="$PAUSED dlna"; return 0; }
arb_airplay_pause() { PAUSED="$PAUSED airplay"; return 0; }

# DLNA on, AirPlay off (the shipped default policy).
ARB_DLNA_PAUSE=1; ARB_AIRPLAY_PAUSE=0
PAUSED=""; arb_protocol_preempt dlna    || true
expect_eq "$PAUSED" " dlna" "DLNA pause fires when DLNA_PAUSE=1"
PAUSED=""; arb_protocol_preempt airplay || true
expect_eq "$PAUSED" "" "AirPlay pause suppressed when AIRPLAY_PAUSE=0"
PAUSED=""; arb_protocol_preempt spotify || true
expect_eq "$PAUSED" "" "Spotify never paused (no API)"

# Opt AirPlay in.
ARB_AIRPLAY_PAUSE=1
PAUSED=""; arb_protocol_preempt airplay || true
expect_eq "$PAUSED" " airplay" "AirPlay pause fires when AIRPLAY_PAUSE=1 (opt-in)"

# DLNA opt-out.
ARB_DLNA_PAUSE=0
PAUSED=""; arb_protocol_preempt dlna    || true
expect_eq "$PAUSED" "" "DLNA pause suppressed when DLNA_PAUSE=0"

# === Result ==================================================================
printf '\n[arb-test] PASS=%s FAIL=%s\n' "$passes" "$failures"
[[ "$failures" -eq 0 ]] || exit 1
echo "[arb-test] arbiter logic tests passed (simulation only; not hardware validation)."
