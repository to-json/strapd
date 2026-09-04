#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
state="$test_tmp/gammastep-state"
log="$test_tmp/log"
mkdir -p "$stub_bin"

# The stubs stand in for one running gammastep. $state holds the line pgrep -a
# would print for it, or nothing when none is running.
cat >"$stub_bin/pgrep" <<'SH'
#!/bin/bash
[[ -s $NIGHTLIGHT_TEST_STATE ]] || exit 1
cat "$NIGHTLIGHT_TEST_STATE"
SH

cat >"$stub_bin/pkill" <<'SH'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$NIGHTLIGHT_TEST_LOG"
: >"$NIGHTLIGHT_TEST_STATE"
SH

# setsid runs the rest of the line, so stubbing uwsm-app catches the launch
# without either of them detaching a real process from the test.
cat >"$stub_bin/setsid" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$stub_bin/uwsm-app" <<'SH'
#!/bin/bash
printf 'launch %s\n' "$*" >>"$NIGHTLIGHT_TEST_LOG"
# Whatever temperature it was asked for is what pgrep reports from here on.
temp=""
prev=""
for arg in "$@"; do
  [[ $prev == "-O" ]] && temp=$arg
  prev=$arg
done
printf '4242 gammastep -P -O %s\n' "$temp" >"$NIGHTLIGHT_TEST_STATE"
SH

cat >"$stub_bin/strapd-cmd-present" <<'SH'
#!/bin/bash
for cmd in "$@"; do
  [[ -x "$NIGHTLIGHT_TEST_STUB_BIN/$cmd" ]] || exit 1
done
SH

cat >"$stub_bin/gammastep" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$stub_bin"/*

run() {
  NIGHTLIGHT_TEST_STATE="$state" \
    NIGHTLIGHT_TEST_LOG="$log" \
    NIGHTLIGHT_TEST_STUB_BIN="$stub_bin" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/strapd-toggle-nightlight" "$@"
}

# The launch is backgrounded on purpose -- a keybinding must not wait on a
# daemon that runs until logout -- so poll for the effect rather than assume it.
wait_for_log() {
  local pattern="$1" attempt

  for attempt in $(seq 1 40); do
    grep -q "$pattern" "$log" && return 0
    sleep 0.05
  done

  return 1
}

: >"$state"
: >"$log"

[[ $(run status) == '{"enabled":false,"temperature":null}' ]] ||
  fail "nothing running reports disabled" "$(run status)"
pass "nothing running reports disabled"

[[ $(run toggle) == "on" ]] || fail "toggle from cold turns the nightlight on"
wait_for_log 'launch -- gammastep -P -O 4000' ||
  fail "toggle starts gammastep at the warm temperature" "$(cat "$log")"
pass "toggle starts gammastep at the warm temperature"

[[ $(run status) == '{"enabled":true,"temperature":4000}' ]] ||
  fail "a running gammastep reports its temperature" "$(run status)"
pass "a running gammastep reports its temperature"

: >"$log"
[[ $(run toggle) == "off" ]] || fail "toggle while on turns the nightlight off"
grep -q 'pkill' "$log" || fail "toggle off stops gammastep" "$(cat "$log")"
[[ $(run status) == '{"enabled":false,"temperature":null}' ]] ||
  fail "status follows the process back down" "$(run status)"
pass "toggle turns the nightlight off again"

# `on` twice must not start a second gammastep: two clients both holding a gamma
# control means whichever exits last decides what the screen looks like.
: >"$log"
run on >/dev/null
wait_for_log 'launch' || fail "on starts gammastep" "$(cat "$log")"
run on >/dev/null
(( $(grep -c 'launch' "$log") == 1 )) ||
  fail "on is idempotent" "$(cat "$log")"
pass "on is idempotent"

: >"$log"
run off >/dev/null
run off >/dev/null
(( $(grep -c 'pkill' "$log") == 1 )) ||
  fail "off with nothing running does not call pkill" "$(cat "$log")"
pass "off with nothing running does nothing"

# A gammastep the user started in its sunrise/sunset mode has no -O to read.
# Enabled is still true, because the screen is warmed by something.
printf '4242 gammastep -l 51.5:0.0\n' >"$state"
[[ $(run status) == '{"enabled":true,"temperature":null}' ]] ||
  fail "a gammastep without -O reports an unknown temperature" "$(run status)"
pass "a gammastep without -O reports an unknown temperature"

: >"$state"
rm -f "$stub_bin/gammastep"
status=0
run on >/dev/null 2>"$test_tmp/err" || status=$?
(( status == 2 )) || fail "a missing gammastep is its own exit status" "exited $status"
grep -q 'gammastep is not installed' "$test_tmp/err" ||
  fail "a missing gammastep says so" "$(cat "$test_tmp/err")"
pass "a missing gammastep is its own exit status, and says so"

# gammastep exits at once where the compositor offers no gamma control, which is
# niri nested exactly. Reporting "on" for a process already gone would be the
# same lie as a compositor answering success for a no-op.
cat >"$stub_bin/uwsm-app" <<'SH'
#!/bin/bash
printf 'launch %s\n' "$*" >>"$NIGHTLIGHT_TEST_LOG"
# Started, and gone again before anyone can look.
SH
chmod +x "$stub_bin/uwsm-app"
cat >"$stub_bin/gammastep" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$stub_bin/gammastep"

: >"$state"
: >"$log"
status=0
output=$(run on 2>"$test_tmp/gone.err") || status=$?
(( status == 1 )) || fail "a gammastep that does not stay up is a failure" "exited $status"
[[ -z $output ]] || fail "a gammastep that does not stay up does not report on" "$output"
grep -q 'did not stay running' "$test_tmp/gone.err" ||
  fail "a gammastep that does not stay up says why" "$(cat "$test_tmp/gone.err")"
pass "a gammastep that does not stay up is a failure, and says why"

status=0
run sideways >/dev/null 2>"$test_tmp/usage" || status=$?
(( status == 1 )) || fail "an unknown argument is a usage error" "exited $status"
grep -q 'Usage: strapd-toggle-nightlight' "$test_tmp/usage" ||
  fail "an unknown argument prints usage" "$(cat "$test_tmp/usage")"
pass "an unknown argument is a usage error"
