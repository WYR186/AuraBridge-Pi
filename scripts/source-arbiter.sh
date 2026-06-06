#!/usr/bin/env bash
# Deliberately NOT 'set -e': this is a long-running daemon and a single transient
# pactl hiccup must not kill it. We use -u and pipefail and guard explicitly.
set -uo pipefail

# source-arbiter.sh — AuraBridge playback arbiter (Phase 7, "中控修正").
#
# POLICY: barge-in. The most recently started wireless source wins the speaker;
# every other source that is ALSO playing is muted. All protocols stay DISCOVERED
# the whole time (AirPlay/mDNS, Spotify/Avahi, DLNA/SSDP are independent buses) —
# the arbiter only touches the PLAYBACK plane, never discovery.
#
# DESIGN (rebuilt to never break single-source playback):
#   - Idempotent reconcile. Every pass recomputes the desired state from a fresh
#     snapshot and converges to it. There is no event-delta state machine, so a
#     missed/duplicated event cannot strand a source muted.
#   - SAFETY RULE: when 0 or 1 managed source is playing, the arbiter mutes
#     NOTHING and makes sure that lone source is audible. AirPlay (or any source)
#     used on its own is therefore never touched.
#   - Self-healing watchdog. The event loop also reconciles on a periodic tick,
#     so any drift auto-corrects.
#   - We only ever unmute streams WE muted (tracked in _muted); a user/app mute is
#     left alone during steady state.
#   - Muting is non-destructive and reversible. On top of muting, the displaced
#     phone is asked to PAUSE over its own protocol (not Stop/disconnect): DLNA on
#     by default, AirPlay opt-in (needs --with-dbus), Spotify has no API so it can
#     only be muted. It NEVER raises volume.
#
# See docs/source-arbiter.md and docs/volume-safety.md.
#
# Usage:
#   source-arbiter.sh [--run]    run the arbiter (foreground; systemd runs this)
#   source-arbiter.sh --once     reconcile once (apply barge-in now) and exit
#   source-arbiter.sh --reset    unmute every managed source and exit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/arbiter-lib.sh
. "$SCRIPT_DIR/lib/arbiter-lib.sh"

log() { printf '[arbiter] %s\n' "$*"; }

# Reconcile at least this often even with no events (watchdog seconds).
ARB_TICK_SECONDS="${AURABRIDGE_ARBITER_TICK_SECONDS:-2}"

# --- arbiter state (plain string maps; works on bash 3.2 and 5) ---------------
_ord=0      # monotonic counter: order in which sources were first seen playing
_seen=""    # " id:ordinal id:ordinal " for currently-playing ids
_muted=""   # " id id "  ids that WE muted (only these may be unmuted by us)

# _seen: ordinal map keyed by sink-input id.
_seen_get() { # echo ordinal and return 0, or return 1 if absent
  local id="$1" kv
  for kv in $_seen; do
    case "$kv" in "${id}:"*) printf '%s' "${kv#*:}"; return 0 ;; esac
  done
  return 1
}
_seen_set() {
  local id="$1" ord="$2" out="" kv
  for kv in $_seen; do
    case "$kv" in "${id}:"*) ;; *) out="$out $kv" ;; esac
  done
  _seen="$out ${id}:${ord}"
}

# _muted: simple set of ids.
_muted_has() { case " $_muted " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
_muted_add() { _muted_has "$1" || _muted="$_muted $1"; }
_muted_del() {
  local id="$1" out="" x
  for x in $_muted; do [[ "$x" == "$id" ]] || out="$out $x"; done
  _muted="$out"
}

# Wait until pipewire-pulse answers, so we do not spin before the session is up.
wait_for_pulse() {
  local tries=0
  until pactl info >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [[ $tries -ge 30 ]]; then
      log "pipewire-pulse not reachable after 30s (pactl info failed); giving up for now."
      return 1
    fi
    sleep 1
  done
  return 0
}

# The whole policy, expressed as "converge to desired state from a fresh
# snapshot". Safe to call as often as we like; calling it twice is a no-op.
reconcile() {
  local snap; snap="$(arb_managed_inputs)"
  local id src corked _m ord
  local playing="" winner="" winner_ord=-1

  # Pass 1: collect playing ids (Corked: no), assign ordinals to new ones, and
  # track the winner = the playing id with the greatest ordinal (newest start).
  while IFS='|' read -r id src corked _m; do
    [[ -n "$id" ]] || continue
    [[ "$corked" == "no" ]] || continue
    playing="$playing $id"
    if ! ord="$(_seen_get "$id")"; then
      _ord=$((_ord + 1)); ord="$_ord"; _seen_set "$id" "$ord"
    fi
    if [[ "$ord" -gt "$winner_ord" ]]; then winner_ord="$ord"; winner="$id"; fi
  done < <(printf '%s\n' "$snap")

  # Release anything WE muted that is no longer playing (stopped/paused/gone).
  local mid
  for mid in $_muted; do
    case " $playing " in
      *" $mid "*) : ;;
      *) arb_unmute_input "$mid"; _muted_del "$mid"; log "released input #$mid (stopped/paused)" ;;
    esac
  done

  # Prune the ordinal map down to currently-playing ids.
  local kv sid newseen=""
  for kv in $_seen; do
    sid="${kv%%:*}"
    case " $playing " in *" $sid "*) newseen="$newseen $kv" ;; esac
  done
  _seen="$newseen"

  # Count playing sources.
  local n=0
  for id in $playing; do n=$((n + 1)); done

  # SAFETY RULE: 0 or 1 source playing => mute NOTHING. Make the lone source
  # audible if we had muted it. This is what makes single-source (e.g. AirPlay
  # alone) immune to the arbiter.
  if [[ "$n" -le 1 ]]; then
    for id in $playing; do
      if _muted_has "$id"; then
        arb_unmute_input "$id"; _muted_del "$id"
        log "single source: unmuted input #$id"
      fi
    done
    return 0
  fi

  # >= 2 sources playing: barge-in. Winner audible; everyone else muted.
  if _muted_has "$winner"; then arb_unmute_input "$winner"; _muted_del "$winner"; fi
  for id in $playing; do
    [[ "$id" == "$winner" ]] && continue
    _muted_has "$id" && continue
    src="$(arb_source_of "$id")"
    # Polite extra: ask the displaced phone to PAUSE over its own protocol
    # (DLNA on by default, AirPlay opt-in, Spotify has no API). Mute is the
    # guaranteed floor below, so the speaker is clean even if pause is a no-op.
    arb_protocol_preempt "$src" && log "paused ${src:-?} (input #$id) on its phone"
    arb_mute_input "$id"; _muted_add "$id"
    log "barge-in: winner input #$winner; muted ${src:-?} (input #$id)"
  done
}

# Unmute every managed source (used for clean-slate at startup and for --reset).
# This is the only place we touch mutes we did not set, on purpose.
unmute_all() {
  local id _s _c _m
  while IFS='|' read -r id _s _c _m; do
    arb_unmute_input "$id"
  done < <(arb_managed_inputs)
}

run_loop() {
  wait_for_pulse || return 1
  log "started (policy=barge-in, dlna_pause=${ARB_DLNA_PAUSE:-1}, airplay_pause=${ARB_AIRPLAY_PAUSE:-0}, tick=${ARB_TICK_SECONDS}s). All protocols stay discoverable; newest source wins playback."
  trap 'log "stopping; unmuting all managed sources"; unmute_all; exit 0' INT TERM
  # Clean slate: clear any stale mute left by a previous crashed run, reset state.
  unmute_all
  _ord=0; _seen=""; _muted=""
  reconcile
  # React to sink-input events for low latency, but also reconcile on a timeout
  # so the policy self-heals even if an event is missed.
  local ev rc
  while :; do
    if IFS= read -t "$ARB_TICK_SECONDS" -r ev; then
      case "$ev" in *sink-input*) reconcile ;; esac
    else
      rc=$?
      if [[ $rc -gt 128 ]]; then
        reconcile                      # read timed out -> watchdog tick
      else
        log "pactl subscribe ended; exiting for restart"
        return 1                       # EOF -> pipewire-pulse restarted
      fi
    fi
  done < <(pactl subscribe 2>/dev/null)
}

arbiter_main() {
  case "${1:-}" in
    --reset)
      wait_for_pulse || exit 0
      log "reset: unmuting all managed sources"
      unmute_all
      exit 0
      ;;
    --once)
      wait_for_pulse || exit 0
      reconcile
      exit 0
      ;;
    ""|--run)
      run_loop
      exit $?
      ;;
    *)
      printf 'usage: %s [--run|--once|--reset]\n' "$(basename "$0")" >&2
      exit 2
      ;;
  esac
}

# Only run when executed directly, so the reconcile/state functions above can be
# sourced and unit-tested (tests/test-arbiter-logic.sh relies on this guard).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  arbiter_main "$@"
fi
