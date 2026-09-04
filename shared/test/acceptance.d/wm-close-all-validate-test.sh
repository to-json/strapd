#!/bin/bash
#
# Closes every window in the session that is actually running. The shell test
# checks the three dialects against a stubbed window list, which proves the
# strings and nothing about whether the windows go away.
#
# It opens its own and refuses to run where it did not: a test that closes
# everything must not be the reason somebody loses what they were doing, and
# there is no way to close only the windows it made once the list is shared.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require jq

export PATH="$ROOT/bin:$PATH"

session=""
for backend in NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE; do
  [[ -n ${!backend:-} ]] && session=$backend
done

if [[ -z $session ]]; then
  pass "no compositor session; skipping the live close-all"
  exit 0
fi

if ! command -v foot >/dev/null; then
  pass "no foot to open windows with; skipping the live close-all"
  exit 0
fi

existing=$(strapd-wm-windows --all 2>/dev/null | jq 'length') || existing=0
if (( existing > 0 )); then
  pass "session already has $existing window(s); skipping rather than closing somebody's work"
  exit 0
fi

for _ in 1 2; do
  setsid foot -e sleep 600 >/dev/null 2>&1 &
done

# Windows map when they map. Wait for both rather than sleeping a guessed amount
# and then reporting a race as a failure.
opened=0
for _ in $(seq 1 40); do
  opened=$(strapd-wm-windows --all 2>/dev/null | jq 'length') || opened=0
  (( opened >= 2 )) && break
  sleep 0.25
done

(( opened >= 2 )) || fail "two windows open before closing them" "saw $opened"
pass "two windows open before closing them"

strapd-wm-close-all

remaining=1
for _ in $(seq 1 40); do
  remaining=$(strapd-wm-windows --all 2>/dev/null | jq 'length') || remaining=0
  (( remaining == 0 )) && break
  sleep 0.25
done

(( remaining == 0 )) || fail "close-all leaves no windows behind" "$remaining still open"
pass "close-all leaves no windows behind"
