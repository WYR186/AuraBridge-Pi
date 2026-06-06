#!/usr/bin/env bash
set -euo pipefail

# Mock simulation tests for AuraBridge Pi scripts.
# These tests validate shell logic only. They do not validate real Raspberry Pi
# hardware, real PipeWire, KA11, AirPlay, Spotify, Bluetooth, or audio safety.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
REPORT_DIR="$SCRIPT_DIR/reports/mock-tests-$TS"
mkdir -p "$REPORT_DIR"

passes=0
warns=0
failures=0

ok() { printf '[mock][PASS] %s\n' "$*"; passes=$((passes + 1)); }
warn() { printf '[mock][WARN] %s\n' "$*"; warns=$((warns + 1)); }
fail() { printf '[mock][FAIL] %s\n' "$*" >&2; failures=$((failures + 1)); }
section() { printf '\n========== %s ==========' "$*"; printf '\n'; }

run_case_script() {
  local case_name="$1"
  local label="$2"
  shift 2
  local out="$REPORT_DIR/${case_name}-${label}.txt"
  local mock_bin="$SCRIPT_DIR/mocks/$case_name/bin"
  set +e
  (
    cd "$REPO_ROOT"
    PATH="$mock_bin:$PATH" "$@"
  ) >"$out" 2>&1
  local rc=$?
  set -e
  printf '%s\n' "$rc" > "$out.rc"
  echo "$out"
}

rc_of() { cat "$1.rc"; }
contains() { grep -q "$2" "$1"; }

run_core_case() {
  local case_name="$1"
  section "$case_name"

  local check_out wp_out status_out dlna_out safe_out
  check_out="$(run_case_script "$case_name" check-ka11 ./scripts/check-ka11.sh)"
  wp_out="$(run_case_script "$case_name" wireplumber-version-check ./scripts/wireplumber-version-check.sh)"
  status_out="$(run_case_script "$case_name" status ./scripts/status.sh)"
  dlna_out="$(run_case_script "$case_name" install-dlna ./scripts/install-dlna.sh)"

  if [[ -x "$SCRIPT_DIR/mocks/$case_name/bin/wpctl" ]]; then
    safe_out="$(run_case_script "$case_name" safe-volume ./scripts/safe-volume.sh)"
    if [[ "$(rc_of "$safe_out")" -eq 0 ]] && contains "$safe_out" 'Done. Default sink volume'; then
      ok "$case_name safe-volume works with mocked wpctl"
    else
      fail "$case_name safe-volume did not succeed with mocked wpctl; see $safe_out"
    fi
  else
    warn "$case_name safe-volume skipped because wpctl is intentionally missing"
  fi

  if [[ "$(rc_of "$dlna_out")" -ne 0 ]] && contains "$dlna_out" 'DLNA is blocked until real-time audio safety is verified'; then
    ok "$case_name DLNA stays blocked without Safe Sink verification"
  else
    fail "$case_name DLNA did not fail closed; see $dlna_out"
  fi

  if contains "$status_out" 'DLNA gate:' && contains "$status_out" 'BLOCKED'; then
    ok "$case_name status reports DLNA blocked"
  else
    fail "$case_name status did not report DLNA blocked; see $status_out"
  fi

  case "$case_name" in
    case-ka11-present)
      if [[ "$(rc_of "$check_out")" -eq 0 ]] && contains "$check_out" 'RESULT: PASS'; then
        ok "KA11 present case passes detection"
      else
        fail "KA11 present case did not pass detection; see $check_out"
      fi ;;
    case-ka11-missing)
      if [[ "$(rc_of "$check_out")" -ne 0 ]] && contains "$check_out" 'RESULT: FAIL' && contains "$check_out" 'not detected'; then
        ok "KA11 missing case fails clearly"
      else
        fail "KA11 missing case did not fail clearly; see $check_out"
      fi ;;
    case-pipewire-missing)
      if contains "$wp_out" 'wireplumber not found' && contains "$check_out" 'PipeWire session reachable   : no'; then
        ok "PipeWire-missing case reports missing audio stack"
      else
        fail "PipeWire-missing case did not report missing stack clearly; see $wp_out / $check_out"
      fi ;;
    case-wireplumber-04)
      if contains "$wp_out" 'Lua-style configuration' && contains "$wp_out" 'Use 0.4-era docs'; then
        ok "WirePlumber 0.4 case warns to use Lua-style docs"
      else
        fail "WirePlumber 0.4 case missing Lua guidance; see $wp_out"
      fi ;;
    case-wireplumber-05)
      if contains "$wp_out" 'SPA-JSON / JSON-style configuration' && contains "$wp_out" 'Use matching docs'; then
        ok "WirePlumber 0.5 case warns to use SPA-JSON / JSON-style docs"
      else
        fail "WirePlumber 0.5 case missing SPA-JSON guidance; see $wp_out"
      fi ;;
    case-services-present)
      if contains "$status_out" 'AirPlay (shairport-sync):  active' && contains "$status_out" 'Spotify (librespot, user): active'; then
        ok "services-present case reports AirPlay/Spotify services active"
      else
        fail "services-present case did not show expected active services; see $status_out"
      fi ;;
  esac
}

section "Mock cases"
for case_name in \
  case-ka11-present \
  case-ka11-missing \
  case-pipewire-missing \
  case-wireplumber-04 \
  case-wireplumber-05 \
  case-services-present; do
  run_core_case "$case_name"
done

section "Source arbiter logic"
arb_out="$REPORT_DIR/arbiter-logic.txt"
set +e
( cd "$REPO_ROOT" && bash ./tests/test-arbiter-logic.sh ) >"$arb_out" 2>&1
arb_rc=$?
set -e
if [[ "$arb_rc" -eq 0 ]] && grep -q 'single AirPlay not muted' "$arb_out"; then
  ok "source arbiter logic tests passed (incl. single-source-never-muted guard)"
else
  cat "$arb_out"
  fail "source arbiter logic tests failed; see $arb_out"
fi

section "No hardware-validation claims"
if grep -R -n -i -E 'hardware validation (passed|complete)|real hardware validated|Raspberry Pi validation passed' "$REPORT_DIR" >/tmp/aurabridge-mock-claims.txt 2>/dev/null; then
  cat /tmp/aurabridge-mock-claims.txt
  fail "mock output contains a real-hardware validation claim"
else
  ok "mock outputs do not claim real hardware validation"
fi

section "Summary"
printf 'Reports: %s\n' "$REPORT_DIR"
printf 'PASS=%s WARN=%s FAIL=%s\n' "$passes" "$warns" "$failures"
if [[ "$failures" -eq 0 ]]; then
  echo "Mock tests passed. This is simulation only, not hardware validation."
  exit 0
fi
exit 1
