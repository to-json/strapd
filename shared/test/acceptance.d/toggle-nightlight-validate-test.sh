#!/bin/bash
#
# Runs the nightlight against the compositor that is actually there. The shell
# test stubs gammastep out entirely, which proves the state machine and nothing
# about whether gammastep can still bind what it needs.
#
# It deliberately stops short of asserting the screen got warmer. A gamma ramp
# lives in the display hardware, and neither output this repo can test against
# has one -- sway's headless backend has no LUT and QEMU's emulated GPU has none
# -- so gammastep binds the protocol, warns "Zero outputs support gamma
# adjustment", and keeps running. Warming a real panel is the one claim here
# that rests on gammastep being gammastep.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require jq gammastep

export PATH="$ROOT/bin:$PATH"

session=""
for backend in NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE; do
  [[ -n ${!backend:-} ]] && session=$backend
done

if [[ -z $session ]]; then
  pass "no compositor session; skipping the live nightlight run"
  exit 0
fi

# Somebody else's gammastep is not this test's to stop and restart.
if pgrep -u "$(id -u)" -x gammastep >/dev/null; then
  pass "a gammastep is already running; skipping the live nightlight run"
  exit 0
fi

cleanup() { pkill -u "$(id -u)" -x gammastep 2>/dev/null || true; }
trap cleanup EXIT

[[ $(strapd-toggle-nightlight status) == '{"enabled":false,"temperature":null}' ]] ||
  fail "a session with no gammastep reports disabled" "$(strapd-toggle-nightlight status)"
pass "a session with no gammastep reports disabled"

status=0
strapd-toggle-nightlight on >/dev/null 2>"$ARTIFACTS/nightlight-on.err" || status=$?

if (( status != 0 )); then
  # niri offers zwlr_gamma_control_manager_v1 on its TTY backend only, so a
  # nested niri is a session where this cannot work and says so. That is the
  # command being honest, not a failure to report.
  grep -q 'did not stay running' "$ARTIFACTS/nightlight-on.err" ||
    fail "a nightlight that cannot start says why" "$(cat "$ARTIFACTS/nightlight-on.err")"
  pass "this session offers no gamma control, and the command says so rather than claiming success"
  exit 0
fi

reported=$(strapd-toggle-nightlight status)
[[ $reported == '{"enabled":true,"temperature":4000}' ]] ||
  fail "a live gammastep reports the warm temperature" "got: $reported"
pass "a live gammastep reports the warm temperature"

strapd-toggle-nightlight off >/dev/null
[[ $(strapd-toggle-nightlight status) == '{"enabled":false,"temperature":null}' ]] ||
  fail "off stops the live gammastep" "$(strapd-toggle-nightlight status)"
pass "off stops the live gammastep"
