#!/bin/bash
#
# Closing everything, three ways. All three of these compositors need to be told
# which window, and two of them will happily report success for a dispatch they
# aimed somewhere else.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

export PATH="$STUB_BIN:$ROOT/bin:$PATH"
export STUB_DIR="$STUB_BIN"

# strapd-wm-close-all asks strapd-wm-windows --all for the ids, so that is the
# seam: the window list is stubbed, the three dialects are what is under test.
cat >"$STUB_BIN/strapd-wm-windows" <<'STUB'
#!/bin/bash
printf 'strapd-wm-windows %s\n' "$*" >>"$STUB_DIR/calls.log"
cat "$STUB_DIR/windows.json"
STUB

for command in niri swaymsg mmsg; do
  cat >"$STUB_BIN/$command" <<'STUB'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$STUB_DIR/calls.log"
STUB
done
chmod +x "$STUB_BIN"/*

close_all() {
  local backend=$1 windows=${2:-'[{"id":4},{"id":9}]'}

  printf '%s\n' "$windows" >"$STUB_BIN/windows.json"
  : >"$STUB_BIN/calls.log"

  unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
  case "$backend" in
    niri) export NIRI_SOCKET=/nonexistent ;;
    sway) export SWAYSOCK=/nonexistent ;;
    mango) export MANGO_INSTANCE_SIGNATURE=/nonexistent ;;
  esac

  strapd-wm-close-all
  cat "$STUB_BIN/calls.log"
}

niri_expected='strapd-wm-windows --all
niri msg action close-window --id 4
niri msg action close-window --id 9
niri msg action focus-workspace 1'

sway_expected='strapd-wm-windows --all
swaymsg [con_id=4] kill
swaymsg [con_id=9] kill
swaymsg workspace number 1'

# Two comma conventions in the same command. `client,<id>` is a separate token
# aiming the dispatch at an unfocused window -- without it mango kills whatever
# is focused, twice, and answers success both times. A function's own arguments
# are comma-joined onto the function instead: `dispatch view 1,0` answers
# {"error":"unknown function"} and still exits 0.
mango_expected='strapd-wm-windows --all
mmsg dispatch killclient client,4
mmsg dispatch killclient client,9
mmsg dispatch view,1,0'

for backend in niri sway mango; do
  case "$backend" in
    niri) expected=$niri_expected ;;
    sway) expected=$sway_expected ;;
    mango) expected=$mango_expected ;;
  esac

  actual=$(close_all "$backend")
  [[ $actual == "$expected" ]] ||
    fail "$backend is asked to close each window by id" "expected:
$expected
actual:
$actual"
  pass "$backend is asked to close each window by id"
done

# Every window, not just the visible ones: a document left on a workspace nobody
# is looking at is exactly the one that would be lost.
[[ $(close_all sway | head -1) == "strapd-wm-windows --all" ]] ||
  fail "the window list is the unfiltered one"
pass "the window list is the unfiltered one"

# An empty desktop still goes back to the first workspace.
actual=$(close_all sway '[]')
[[ $actual == 'strapd-wm-windows --all
swaymsg workspace number 1' ]] ||
  fail "an empty desktop still returns to the first workspace" "got:
$actual"
pass "an empty desktop still returns to the first workspace"

# A window list that cannot be had is not a reason to leave the session on
# whatever workspace it was on.
cat >"$STUB_BIN/strapd-wm-windows" <<'STUB'
#!/bin/bash
printf 'strapd-wm-windows %s\n' "$*" >>"$STUB_DIR/calls.log"
exit 1
STUB
chmod +x "$STUB_BIN/strapd-wm-windows"
actual=$(close_all sway)
[[ $actual == 'strapd-wm-windows --all
swaymsg workspace number 1' ]] ||
  fail "a window list that fails still returns to the first workspace" "got:
$actual"
pass "a window list that fails still returns to the first workspace"

unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
output=$(strapd-wm-close-all 2>&1)
status=$?
(( status == 2 )) || fail "no compositor at all is its own exit status" "exited $status"
[[ $output == *"no niri, sway or mango session"* ]] ||
  fail "no compositor at all says so" "got: $output"
pass "no compositor at all is its own exit status, and says so"
