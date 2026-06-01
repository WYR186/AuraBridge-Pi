#!/usr/bin/env bash
set -euo pipefail

# preflight-dev-machine.sh — static checks for development machines.
# This does not validate Raspberry Pi hardware and does not touch services.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

failures=0

section() { printf '\n========== %s ==========\n' "$*"; }
fail() { printf '[preflight-dev][FAIL] %s\n' "$*" >&2; failures=$((failures + 1)); }
ok() { printf '[preflight-dev][OK] %s\n' "$*"; }
warn() { printf '[preflight-dev][WARN] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

cd "$REPO_ROOT"

section "Host"
uname -a || true
if [[ "$(uname -s 2>/dev/null || echo unknown)" == "Linux" ]] && [[ -r /proc/device-tree/model ]]; then
  tr -d '\0' </proc/device-tree/model || true
  echo
else
  warn "This appears to be a development machine, not Raspberry Pi hardware."
fi

section "Required files"
required_files=(
  PROJECT_OVERVIEW_2_2.md
  WHITEPAPER_2_2.md
  README.md
  docs/pi-bringup-checklist.md
  docs/first-boot-runbook.md
  docs/pass-fail-matrix.md
  docs/rollback.md
  docs/known-risks-before-hardware.md
  scripts/preflight-pi.sh
  scripts/collect-report.sh
  scripts/rollback-audio-services.sh
  scripts/print-next-steps.sh
)
for f in "${required_files[@]}"; do
  if [[ -f "$f" ]]; then
    ok "$f"
  else
    fail "missing required file: $f"
  fi
done

section "bash -n scripts/*.sh"
if bash -n scripts/*.sh; then
  ok "bash syntax passed"
else
  fail "bash syntax failed"
fi

section "shellcheck scripts/*.sh"
if have shellcheck; then
  if shellcheck scripts/*.sh; then
    ok "shellcheck passed"
  else
    fail "shellcheck found issues"
  fi
else
  warn "shellcheck not installed; skipping"
fi

section "Forbidden active routing / enablement patterns"
if grep -R -n -E 'hw:1|plughw:1' scripts systemd \
  --exclude='preflight-dev-machine.sh' >/tmp/aurabridge-preflight-alsa.txt 2>/dev/null; then
  cat /tmp/aurabridge-preflight-alsa.txt
  fail "found hardcoded ALSA card-1 pattern in scripts/systemd"
else
  ok "no hardcoded hw:1/plughw:1 in scripts/systemd"
fi

if grep -R -n -E 'systemctl +(--user +)?enable +gmrender|systemctl +enable +gmrender|enable +gmrender' scripts systemd docs README.md TROUBLESHOOTING.md >/tmp/aurabridge-preflight-dlna.txt 2>/dev/null; then
  cat /tmp/aurabridge-preflight-dlna.txt
  fail "found unsafe gmrender enablement text"
else
  ok "no gmrender enablement found"
fi

if grep -R -n -i -E 'DLNA.*safe.*because.*volume guard|volume guard.*makes.*DLNA.*safe|volume-guard-loop\.sh.*makes.*DLNA.*safe' . \
  --exclude-dir=.git --exclude='preflight-dev-machine.sh' >/tmp/aurabridge-preflight-volume-guard.txt 2>/dev/null; then
  cat /tmp/aurabridge-preflight-volume-guard.txt
  fail "found text claiming volume guard makes DLNA safe"
else
  ok "no claim that volume guard makes DLNA safe"
fi

section "Future-phase gates"
if grep -q 'DLNA is blocked until real-time audio safety is verified' scripts/install-dlna.sh; then
  ok "install-dlna.sh contains explicit DLNA block message"
else
  fail "install-dlna.sh missing explicit DLNA block message"
fi

if grep -q 'SAFE_SINK_VERIFIED=yes' scripts/install-dlna.sh systemd/gmrender.service; then
  ok "DLNA installer/service gate on SAFE_SINK_VERIFIED=yes"
else
  fail "DLNA gate marker not found"
fi

if grep -R -n -i 'not implemented in Phase 0-3' scripts docs README.md TROUBLESHOOTING.md \
  --exclude='preflight-dev-machine.sh' >/tmp/aurabridge-preflight-placeholders.txt 2>/dev/null; then
  cat /tmp/aurabridge-preflight-placeholders.txt
  fail "stale Phase 0-3 placeholder text found"
else
  ok "no stale Phase 0-3 placeholder text"
fi

section "Result"
if [[ "$failures" -eq 0 ]]; then
  ok "development-machine preflight passed"
  echo "Reminder: this is static validation only, not Raspberry Pi hardware validation."
  exit 0
fi

fail "$failures check(s) failed"
exit 1
