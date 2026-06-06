#!/usr/bin/env bash
# Deliberately NOT 'set -e': this is a long-running daemon and a single transient
# pactl hiccup must not kill it. We use -u and pipefail and guard explicitly.
set -uo pipefail

# source-arbiter.sh — AuraBridge playback arbiter (Phase 7, "中控修正").
#
# POLICY: barge-in. The most recently started wireless source wins the speaker;
# every other source that is playing is preempted. All protocols stay DISCOVERED
# the whole time (AirPlay/mDNS, Spotify/Avahi, DLNA/SSDP are independent buses) —
# the arbiter only touches the PLAYBACK plane, never discovery.
#
# Preemption is done on the PipeWire playback plane by default: displaced
# sink-inputs are muted so the speaker only plays the winner. Optional
# protocol-level Stop can be enabled with AURABRIDGE_ARBITER_PROTOCOL_STOP=1,
# but it is deliberately off by default because it can make AirPlay/DLNA sender
# UIs look disconnected even though discovery remains available.
#
# It NEVER raises volume. See docs/source-arbiter.md and docs/volume-safety.md.
#
# Usage:
#   source-arbiter.sh            run the arbiter (foreground; systemd runs this)
#   source-arbiter.sh --reset    unmute every managed source and exit
#   source-arbiter.sh --once     reconcile once (apply barge-in now) and exit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/arbiter-lib.sh
. "$SCRIPT_DIR/lib/arbiter-lib.sh"

log() { printf '[arbiter] %s\n' "$*"; }

# Id of the source that currently owns the speaker ("" = nobody yet).
current_winner=""

# Last-seen corked state per sink-input, encoded as " id:state id:state ".
# We only barge in on a TRANSITION into playing (a start or a resume), never on
# a bare 'change' event — otherwise a metadata/volume tick on a muted background
# stream (e.g. Spotify, which has no protocol stop and keeps streaming silently)
# would be misread as a fresh barge-in and wrongly steal the speaker back. Plain
# string map so this works on both bash 3.2 and bash 5 (no associative arrays).
_last_cork=""
_get_last_cork() {
  local id="$1" kv
  for kv in $_last_cork; do
    case "$kv" in "${id}:"*) printf '%s' "${kv#*:}"; return 0 ;; esac
  done
  printf 'unknown'
}
_set_last_cork() {
  local id="$1" st="$2" out="" kv
  for kv in $_last_cork; do
    case "$kv" in "${id}:"*) ;; *) out="$out $kv" ;; esac
  done
  _last_cork="$out ${id}:${st}"
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

# Preempt every managed source EXCEPT the winner: optional protocol-stop (opt-in)
# then mute (guaranteed). Already-corked (paused) sources are left alone. We also
# record each preempted source's corked state so the 'change' event our own mute
# triggers is not later misread as that source barging back in.
preempt_others() {
  local winner_id="$1" id src corked _mute
  while IFS='|' read -r id src corked _mute; do
    [[ "$id" == "$winner_id" ]] && continue
    [[ "$corked" == "yes" ]] && continue
    if arb_protocol_stop "$src"; then
      log "stopped $src (input #$id) via its own protocol"
    fi
    arb_mute_input "$id"
    _set_last_cork "$id" "$corked"
    log "preempted $src (input #$id) in favour of input #$winner_id"
  done < <(arb_managed_inputs)
}

# Seed last-known corked state for every managed input without acting, so the
# first organic event after startup is judged as a transition, not a cold start.
seed_states() {
  local id _s corked _m
  while IFS='|' read -r id _s corked _m; do
    _set_last_cork "$id" "$corked"
  done < <(arb_managed_inputs)
}

# Promote the newest actively-playing managed source to winner and preempt the
# rest. Used at startup and whenever the winner disappears.
reconcile() {
  local id src corked _mute newest="" newest_src=""
  while IFS='|' read -r id src corked _mute; do
    if [[ "$corked" == "no" ]]; then newest="$id"; newest_src="$src"; fi
  done < <(arb_managed_inputs)
  if [[ -n "$newest" ]]; then
    current_winner="$newest"
    arb_unmute_input "$newest"
    _set_last_cork "$newest" "no"
    log "winner=$newest_src (input #$newest) [reconcile]"
    preempt_others "$newest"
  else
    current_winner=""
  fi
}

# React to one sink-input id changing.
handle_input() {
  local id="$1" block src corked prev
  block="$(_arb_input_block "$id")"
  if [[ -z "$block" ]]; then
    # The input is gone. If it was the winner, let a remaining source take over.
    _set_last_cork "$id" "gone"
    if [[ "$id" == "$current_winner" ]]; then
      log "winner (input #$id) ended; reconciling"
      current_winner=""
      reconcile
    fi
    return
  fi
  src="$(_arb_classify_block "$block")"
  [[ -z "$src" ]] && return
  corked="$(_arb_field "$block" 'Corked:')"
  prev="$(_get_last_cork "$id")"
  _set_last_cork "$id" "$corked"
  # Barge-in only on a TRANSITION into playing (start or resume): corked is "no"
  # now but was not "no" before. A change event on an already-playing stream
  # (volume, metadata, our own mute) is intentionally ignored.
  if [[ "$corked" == "no" && "$prev" != "no" && "$id" != "$current_winner" ]]; then
    arb_unmute_input "$id"
    current_winner="$id"
    log "winner=$src (input #$id) [barge-in]"
    preempt_others "$id"
  fi
}

unmute_all() {
  local id _s _c _m
  while IFS='|' read -r id _s _c _m; do
    arb_unmute_input "$id"
  done < <(arb_managed_inputs)
}

run_loop() {
  wait_for_pulse || return 1
  log "started (policy=barge-in, protocol_stop=${ARB_PROTOCOL_STOP:-0}). All protocols stay discoverable; newest source wins playback."
  trap 'log "stopping; unmuting all managed sources"; unmute_all; exit 0' INT TERM
  # Seed per-input state, then apply the rule once for whatever is already playing.
  seed_states
  reconcile
  # Then react to every sink-input event. Process substitution keeps the loop in
  # this shell so current_winner persists across events.
  local ev id
  while read -r ev; do
    case "$ev" in
      *sink-input*)
        id="$(printf '%s' "$ev" | grep -oE '#[0-9]+' | head -n1 | tr -d '#')"
        [[ -n "$id" ]] && handle_input "$id"
        ;;
    esac
  done < <(pactl subscribe 2>/dev/null)
  # If we get here, `pactl subscribe` ended (pipewire-pulse restarted). Exit
  # non-zero so systemd restarts us and we re-subscribe cleanly.
  log "pactl subscribe ended; exiting for restart"
  return 1
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

# Only run when executed directly, so the decision functions above can be sourced
# and unit-tested (tests/ and the mock harness rely on this guard).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  arbiter_main "$@"
fi
