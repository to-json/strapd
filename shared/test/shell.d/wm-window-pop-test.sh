#!/bin/bash
#
# Popping a window out and putting it back, three ways. The compositors agree on
# floating and disagree after it: sway needs one comma-joined message or it loses
# the resize to its own geometry restore, mango's pin is a toggle that has to be
# read before it is flipped, and niri has no pin at all. All string-shaped, so
# it is checked here; the acceptance test watches a real window move.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

export PATH="$STUB_BIN:$ROOT/bin:$PATH"
export STUB_DIR="$STUB_BIN"

# Each stub answers the one query the command starts with out of window.json and
# logs everything else, which keeps the fixture a single window record per case.
cat >"$STUB_BIN/niri" <<'STUB'
#!/bin/bash
if [[ $* == "msg -j focused-window" ]]; then
  cat "$STUB_DIR/window.json"
  exit 0
fi
printf 'niri %s\n' "$*" >>"$STUB_DIR/calls.log"
STUB

cat >"$STUB_BIN/swaymsg" <<'STUB'
#!/bin/bash
if [[ $* == "-t get_tree" ]]; then
  cat "$STUB_DIR/window.json"
  exit 0
fi
printf 'swaymsg %s\n' "$*" >>"$STUB_DIR/calls.log"
STUB

cat >"$STUB_BIN/mmsg" <<'STUB'
#!/bin/bash
if [[ $* == "get focusing-client" ]]; then
  cat "$STUB_DIR/window.json"
  exit 0
fi
printf 'mmsg %s\n' "$*" >>"$STUB_DIR/calls.log"
STUB

# Only mango asks, because only mango has no action that centers a window.
cat >"$STUB_BIN/strapd-wm-monitors" <<'STUB'
#!/bin/bash
printf 'strapd-wm-monitors %s\n' "$*" >>"$STUB_DIR/calls.log"
printf '%s\n' '{"name":"DP-1","x":0,"y":0,"width":1920,"height":1080}'
STUB

chmod +x "$STUB_BIN"/*

# sway reports a whole tree; the command reduces it with jq, so the fixture has
# to be a tree even though only one node in it matters.
sway_tree() {
  printf '{"nodes":[{"id":7,"pid":%s,"focused":true,"type":"%s"}],"floating_nodes":[]}' \
    "${2:-99}" "$1"
}

pop() {
  local backend=$1 window=$2
  shift 2

  printf '%s\n' "$window" >"$STUB_BIN/window.json"
  : >"$STUB_BIN/calls.log"

  unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
  case "$backend" in
    niri) export NIRI_SOCKET=/nonexistent ;;
    sway) export SWAYSOCK=/nonexistent ;;
    mango) export MANGO_INSTANCE_SIGNATURE=/nonexistent ;;
  esac

  # A file is the only way a status gets out of a subshell.
  strapd-wm-window-pop "$@"
  printf '%s\n' "$?" >"$STUB_BIN/status"
  cat "$STUB_BIN/calls.log"
}

pop_status() {
  cat "$STUB_BIN/status"
}

expected='niri msg action move-window-to-floating --id 3
niri msg action set-window-width --id 3 1300
niri msg action set-window-height --id 3 900
niri msg action center-window --id 3'
actual=$(pop niri '{"id":3,"is_floating":false}')
[[ $actual == "$expected" ]] ||
  fail "niri floats, sizes and centers a tiled window" "expected:
$expected
actual:
$actual"
pass "niri floats, sizes and centers a tiled window"

expected='niri msg action move-window-to-floating --id 3
niri msg action set-window-width --id 3 400
niri msg action set-window-height --id 3 300
niri msg action move-floating-window --id 3 -x 20 -y 30'
actual=$(pop niri '{"id":3,"is_floating":false}' 400 300 20 30)
[[ $actual == "$expected" ]] ||
  fail "a given position replaces the centering" "expected:
$expected
actual:
$actual"
pass "a given position replaces the centering"

actual=$(pop niri '{"id":3,"is_floating":true}')
[[ $actual == 'niri msg action move-window-to-tiling --id 3' ]] ||
  fail "niri tiles a window that is already floating" "got:
$actual"
pass "niri tiles a window that is already floating"

# niri has no sticky, and nothing here should pretend otherwise.
[[ $(pop niri '{"id":3,"is_floating":false}') != *sticky* ]] ||
  fail "niri is not asked to pin"
pass "niri is not asked to pin"

# One message. `floating enable` restores the last floated geometry after the
# reply comes back, so a separate resize loses that race about a third of the
# time, with four success replies to show for it.
expected='swaymsg [con_id=7] floating enable, resize set 1300 px 900 px, move position center, sticky enable'
actual=$(pop sway "$(sway_tree con)")
[[ $actual == "$expected" ]] ||
  fail "sway is told to float, size, place and pin in one message" "expected:
$expected
actual:
$actual"
pass "sway is told to float, size, place and pin in one message"

expected='swaymsg [con_id=7] floating enable, resize set 400 px 300 px, move position 20 30, sticky enable'
actual=$(pop sway "$(sway_tree con)" 400 300 20 30)
[[ $actual == "$expected" ]] ||
  fail "sway takes a given position in the same message" "expected:
$expected
actual:
$actual"
pass "sway takes a given position in the same message"

# Unpinning first: a sticky tiled window is a state sway will hold on to.
expected='swaymsg [con_id=7] sticky disable, floating disable'
actual=$(pop sway "$(sway_tree floating_con)")
[[ $actual == "$expected" ]] ||
  fail "sway unpins before it tiles" "expected:
$expected
actual:
$actual"
pass "sway unpins before it tiles"

expected='mmsg dispatch togglefloating client,5
mmsg dispatch resizewin,1300,900 client,5
strapd-wm-monitors --focused
mmsg dispatch movewin,310,90 client,5
mmsg dispatch toggleglobal client,5'
actual=$(pop mango '{"id":5,"is_floating":false,"is_global":false}')
[[ $actual == "$expected" ]] ||
  fail "mango floats, sizes, centers and pins" "expected:
$expected
actual:
$actual"
pass "mango floats, sizes, centers and pins"

# toggleglobal is a toggle, not a setter. A window already global would be
# unpinned by a pop that flipped it blind.
expected='mmsg dispatch togglefloating client,5
mmsg dispatch resizewin,400,300 client,5
mmsg dispatch movewin,20,30 client,5'
actual=$(pop mango '{"id":5,"is_floating":false,"is_global":true}' 400 300 20 30)
[[ $actual == "$expected" ]] ||
  fail "mango leaves an already-pinned window pinned" "expected:
$expected
actual:
$actual"
pass "mango leaves an already-pinned window pinned"

expected='mmsg dispatch toggleglobal client,5
mmsg dispatch togglefloating client,5'
actual=$(pop mango '{"id":5,"is_floating":true,"is_global":true}')
[[ $actual == "$expected" ]] ||
  fail "mango unpins before it tiles" "expected:
$expected
actual:
$actual"
pass "mango unpins before it tiles"

expected='mmsg dispatch togglefloating client,5'
actual=$(pop mango '{"id":5,"is_floating":true,"is_global":false}')
[[ $actual == "$expected" ]] ||
  fail "mango does not pin a window on the way back to the tiling" "expected:
$expected
actual:
$actual"
pass "mango does not pin a window on the way back to the tiling"

# A window wider than the display centers to a negative left edge, and mango
# reads a signed coordinate as a move *by* that much. Clamped at the origin.
actual=$(pop mango '{"id":5,"is_floating":false,"is_global":true}' 3000 2000)
[[ $actual == *'movewin,0,0 client,5'* ]] ||
  fail "a window bigger than the display is placed at the origin, not moved" "got:
$actual"
pass "a window bigger than the display is placed at the origin, not moved"

for backend in niri sway mango; do
  case "$backend" in
    niri) empty=null ;;
    sway) empty='{"nodes":[],"floating_nodes":[]}' ;;
    mango) empty='{"error":"no focusing client"}' ;;
  esac

  actual=$(pop "$backend" "$empty")
  status=$(pop_status)
  (( status == 1 )) ||
    fail "$backend with nothing focused is an ordinary no-answer" "exited $status"
  [[ -z $actual ]] || fail "$backend with nothing focused touches nothing" "got:
$actual"
done
pass "nothing focused is an ordinary no-answer on all three"

export SWAYSOCK=/nonexistent
printf '%s\n' "$(sway_tree con)" >"$STUB_BIN/window.json"

for args in "one 900" "1300 nine" "1300 900 20" "1300 900 20 30 40"; do
  # shellcheck disable=SC2086
  if output=$(strapd-wm-window-pop $args 2>&1); then
    fail "'$args' is rejected" "it was accepted"
  fi
  [[ $output == "Usage: strapd-wm-window-pop"* ]] ||
    fail "'$args' says what the arguments are" "got: $output"
done
pass "a size that is not two numbers, or a place that is not two, is a usage error"

unset SWAYSOCK
output=$(strapd-wm-window-pop 2>&1)
status=$?
(( status == 2 )) || fail "no compositor at all is its own exit status" "exited $status"
[[ $output == *"no niri, sway or mango session"* ]] ||
  fail "no compositor at all says so" "got: $output"
pass "no compositor at all is its own exit status, and says so"
