#!/usr/bin/env bash
set -euo pipefail

# Static checks for AuraBridge Pi from a Mac/dev machine.
# This is not Raspberry Pi hardware validation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
failures=0

section() { printf '\n========== %s ==========' "$*"; printf '\n'; }
ok() { printf '[static][OK] %s\n' "$*"; }
warn() { printf '[static][WARN] %s\n' "$*" >&2; }
fail() { printf '[static][FAIL] %s\n' "$*" >&2; failures=$((failures + 1)); }
have() { command -v "$1" >/dev/null 2>&1; }

cd "$REPO_ROOT"

section "bash -n scripts/*.sh tests/*.sh"
if bash -n scripts/*.sh tests/*.sh; then
  ok "bash syntax passed"
else
  fail "bash syntax failed"
fi

section "shellcheck"
if have shellcheck; then
  if shellcheck scripts/*.sh tests/*.sh tests/mocks/mock-command.sh; then
    ok "shellcheck passed"
  else
    fail "shellcheck found issues"
  fi
else
  warn "shellcheck not available; skipped"
fi

section "Forbidden patterns"
check_no_match() {
  local label="$1"
  local pattern="$2"
  shift 2
  local tmp="/tmp/aurabridge-static-${label//[^A-Za-z0-9]/_}.txt"
  if grep -R -n -E "$pattern" "$@" >"$tmp" 2>/dev/null; then
    cat "$tmp"
    fail "forbidden pattern found: $label"
  else
    ok "no forbidden pattern: $label"
  fi
}

check_no_unsafe_match() {
  local label="$1"
  local pattern="$2"
  local allow_pattern="$3"
  shift 3
  local tmp="/tmp/aurabridge-static-${label//[^A-Za-z0-9]/_}.txt"
  local filtered="/tmp/aurabridge-static-${label//[^A-Za-z0-9]/_}-filtered.txt"
  if grep -R -n -E "$pattern" "$@" >"$tmp" 2>/dev/null; then
    grep -viE "$allow_pattern" "$tmp" >"$filtered" || true
    if [[ -s "$filtered" ]]; then
      cat "$filtered"
      fail "forbidden pattern found: $label"
    else
      ok "only allowed explanatory matches for: $label"
    fi
  else
    ok "no forbidden pattern: $label"
  fi
}

# Active scripts/services must never hardcode card-1 or route normal services to ALSA hardware.
check_no_match 'hw:1' 'hw:1' scripts systemd tests --exclude='run-static-checks.sh' --exclude='preflight-dev-machine.sh' --exclude-dir=reports
check_no_match 'plughw:1' 'plughw:1' scripts systemd tests --exclude='run-static-checks.sh' --exclude='preflight-dev-machine.sh' --exclude-dir=reports
check_no_unsafe_match 'card 1' 'card 1' 'never assumes|never assume|do not assume|not assumed|dynamic detection' scripts systemd tests --exclude='run-static-checks.sh' --exclude='preflight-dev-machine.sh' --exclude-dir=reports
check_no_match 'systemctl enable gmrender' 'systemctl +(--user +)?enable +gmrender|systemctl +enable +gmrender' scripts systemd docs README.md TROUBLESHOOTING.md tests --exclude='run-static-checks.sh' --exclude-dir=reports
check_no_unsafe_match 'volume guard as speaker protection' 'volume-guard-loop\.sh.*speaker protection|volume guard.*speaker protection|protected by the volume guard' 'do .*not.*treat|not .*speaker protection|not real-time speaker protection|is not speaker protection|not a speaker protection|only.*not|recovery|diagnostics' scripts systemd docs README.md TROUBLESHOOTING.md tests --exclude='run-static-checks.sh' --exclude='preflight-dev-machine.sh' --exclude-dir=reports

section "Safety gates"
if grep -q 'DLNA is blocked until real-time audio safety is verified' scripts/install-dlna.sh; then
  ok "install-dlna.sh still has the DLNA block message"
else
  fail "install-dlna.sh missing DLNA block message"
fi
if grep -q 'SAFE_SINK_VERIFIED=yes' scripts/install-dlna.sh systemd/gmrender.service; then
  ok "DLNA remains gated on SAFE_SINK_VERIFIED=yes"
else
  fail "DLNA gate marker missing"
fi

section "Result"
if [[ "$failures" -eq 0 ]]; then
  ok "static checks passed"
  echo "This is script/static validation only; it is not Raspberry Pi hardware validation."
  exit 0
fi
fail "$failures static check(s) failed"
exit 1
