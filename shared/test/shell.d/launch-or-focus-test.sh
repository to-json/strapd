#!/bin/bash
#
# Focus it if it is open, start it if it is not. Three lines of script, and every
# one is a decision: what counts as "already open" (strapd-wm-focus-window's
# answer, so all three compositors agree), what to run when it is not, and what
# to do when there is no compositor to ask.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

export PATH="$STUB_BIN:$ROOT/bin:$PATH"

# The shim stands in for all three compositors; which one is running is
# wm-focus-window-test.sh's question. $FOCUS_STATUS is its answer.
cat >"$STUB_BIN/strapd-wm-focus-window" <<'STUB'
#!/bin/bash
printf 'focus %s\n' "$*" >>"$ACTION_FILE"
exit "${FOCUS_STATUS:-0}"
STUB

# setsid, because the launch path ends in `eval exec setsid $LAUNCH_COMMAND` and
# there is nothing left of the script after the exec to record anything.
cat >"$STUB_BIN/setsid" <<'STUB'
#!/bin/bash
printf 'setsid %s\n' "$*" >>"$ACTION_FILE"
STUB

chmod +x "$STUB_BIN/strapd-wm-focus-window" "$STUB_BIN/setsid"

ACTION_FILE="$STUB_BIN/actions.log"
export ACTION_FILE

run() {
  FOCUS_STATUS=$1 && shift
  export FOCUS_STATUS
  : >"$ACTION_FILE"
  strapd-launch-or-focus "$@"
}

# An open window is focused and nothing is started.
run 0 chromium || fail "an open window is focused"
[[ $(cat "$ACTION_FILE") == "focus chromium" ]] ||
  fail "an open window is focused and nothing else happens" "got: $(cat "$ACTION_FILE")"
pass "an open window is focused, and nothing is launched"

# Nothing matching open: run the command that was given.
run 1 chromium 'uwsm-app -- chromium --app=https://example.com' ||
  fail "a closed app is launched"
[[ $(cat "$ACTION_FILE") == "focus chromium
setsid uwsm-app -- chromium --app=https://example.com" ]] ||
  fail "a closed app is launched with the command it was given" "got: $(cat "$ACTION_FILE")"
pass "a closed app is launched with the command it was given"

# With no command the pattern is the command, through uwsm-app, so the app lands
# in its own systemd scope rather than as a child of whatever key was pressed.
run 1 chromium || fail "the pattern doubles as the command"
[[ $(cat "$ACTION_FILE") == *"setsid uwsm-app -- chromium" ]] ||
  fail "the pattern doubles as the command" "got: $(cat "$ACTION_FILE")"
pass "with no command, the pattern is launched through uwsm-app"

# No compositor to ask is exit 2, and it launches too: from a TTY or a session
# that is not one of ours, starting the app is still the useful answer.
run 2 chromium || fail "no session still launches"
[[ $(cat "$ACTION_FILE") == *"setsid uwsm-app -- chromium" ]] ||
  fail "no session still launches" "got: $(cat "$ACTION_FILE")"
pass "no compositor to ask still launches the app"

output=$(strapd-launch-or-focus 2>&1)
status=$?
(( status != 0 )) || fail "no arguments is a usage error" "exited 0"
[[ $output == Usage:* ]] || fail "no arguments prints usage" "got: $output"
pass "no arguments is a usage error"
