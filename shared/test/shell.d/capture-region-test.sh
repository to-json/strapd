#!/bin/bash
#
# The screenshot picker: which rectangles slurp is offered, and what a bare click
# resolves to. Which compositor is running is wm-monitors-test.sh's question;
# this covers the rectangle list, the freeze lifecycle and the click fallback.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

export PATH="$STUB_BIN:$ROOT/bin:$PATH"

cat >"$STUB_BIN/strapd-wm-monitors" <<'STUB'
#!/bin/bash
if [[ ${1:-} == --focused ]]; then
  jq -c 'first(.[] | select(.focused)) // empty' <"$MONITORS_FILE"
else
  cat "$MONITORS_FILE"
fi
STUB

cat >"$STUB_BIN/strapd-wm-windows" <<'STUB'
#!/bin/bash
cat "$WINDOWS_FILE"
STUB

# Records what it was offered and answers with $SLURP_REPLY. Real slurp reads a
# region list on stdin only when something pipes one in, and so does this: a
# `cat` that did not check would sit on the test runner's stdin.
cat >"$STUB_BIN/slurp" <<'STUB'
#!/bin/bash
{
  printf 'slurp %s\n' "$*"
  [[ -p /dev/stdin ]] && cat
} >>"$ACTION_FILE"
printf '%s\n' "$SLURP_REPLY"
STUB

cat >"$STUB_BIN/hyprpicker" <<'STUB'
#!/bin/bash
printf 'hyprpicker %s\n' "$*" >>"$ACTION_FILE"
sleep 20
STUB

chmod +x "$STUB_BIN"/*

ACTION_FILE="$STUB_BIN/actions.log"
MONITORS_FILE="$STUB_BIN/monitors.json"
WINDOWS_FILE="$STUB_BIN/windows.json"
export ACTION_FILE MONITORS_FILE WINDOWS_FILE

# One 1920x1080 monitor with two windows on it.
printf '%s\n' '[{"name":"eDP-1","focused":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1}]' >"$MONITORS_FILE"
printf '%s\n' '[{"id":1,"app_id":"one","x":0,"y":30,"width":960,"height":1050,"focused":false},
                {"id":2,"app_id":"two","x":960,"y":30,"width":960,"height":1050,"focused":true}]' >"$WINDOWS_FILE"

region() {
  : >"$ACTION_FILE"
  SLURP_REPLY="${SLURP_REPLY:-}" strapd-capture-region "$@"
}

# fullscreen asks nobody anything: no picker, and no freeze to pay for either.
selection=$(SLURP_REPLY= region fullscreen) || fail "fullscreen picks the focused monitor"
[[ $selection == "0,0 1920x1080" ]] ||
  fail "fullscreen picks the focused monitor" "got: $selection"
[[ ! -s $ACTION_FILE ]] ||
  fail "fullscreen runs neither slurp nor a freeze" "got: $(cat "$ACTION_FILE")"
pass "fullscreen picks the focused monitor without a picker or a freeze"

selection=$(SLURP_REPLY= region fullscreen --match-monitor)
[[ $selection == "monitor:eDP-1" ]] ||
  fail "--match-monitor names a monitor whose geometry matched" "got: $selection"
pass "--match-monitor names the monitor when the geometry is exactly its own"

# region is freeform: slurp gets a freeze and no rectangles at all.
selection=$(SLURP_REPLY='100,100 400x300' region region)
[[ $selection == "100,100 400x300" ]] ||
  fail "region returns what was dragged" "got: $selection"
grep -q '^hyprpicker -r -z$' "$ACTION_FILE" ||
  fail "region freezes the screen first" "got: $(cat "$ACTION_FILE")"
[[ $(grep -c '^slurp $' "$ACTION_FILE") == 1 ]] ||
  fail "region offers slurp no rectangles" "got: $(cat "$ACTION_FILE")"
pass "region freezes the screen and takes a freeform drag"

# windows snaps: slurp gets -r and the monitor plus every window.
selection=$(SLURP_REPLY='960,30 960x1050' region windows)
[[ $selection == "960,30 960x1050" ]] ||
  fail "windows returns the snapped rectangle" "got: $selection"
grep -q '^slurp -r$' "$ACTION_FILE" ||
  fail "windows restricts slurp to the rectangles it is given" "got: $(cat "$ACTION_FILE")"
offered=$(sed -n '/^slurp -r$/,$p' "$ACTION_FILE" | tail -n +2)
[[ $offered == "0,0 1920x1080
0,30 960x1050
960,30 960x1050" ]] ||
  fail "windows offers the monitor and every window" "got: $offered"
pass "windows offers slurp the monitor and every window, and nothing else"

# A drag big enough to mean it is taken at face value.
selection=$(SLURP_REPLY='300,300 500x400' region smart)
[[ $selection == "300,300 500x400" ]] ||
  fail "smart takes a real drag at face value" "got: $selection"
pass "smart takes a real drag at face value"

# A bare click slurp did not resolve: it lands in a gap, and the smallest
# containing rectangle wins -- here the window, not the screen. Taking the first
# match instead snaps a click inside a window to the whole screen.
selection=$(SLURP_REPLY='500,500 1x1' region smart)
[[ $selection == "0,30 960x1050" ]] ||
  fail "a bare click snaps to the smallest rectangle around it" "got: $selection"
pass "a bare click snaps to the smallest rectangle around it, not the screen"

# A click above the windows, in the bar strip, has only the monitor around it.
selection=$(SLURP_REPLY='500,10 1x1' region smart)
[[ $selection == "0,0 1920x1080" ]] ||
  fail "a click outside every window snaps to the monitor" "got: $selection"
pass "a click outside every window snaps to the monitor"

# Negative coordinates are ordinary: a monitor left of or above the origin.
printf '%s\n' '[{"name":"DP-1","focused":true,"x":-1920,"y":-200,"width":1920,"height":1080,"scale":1}]' >"$MONITORS_FILE"
printf '%s\n' '[{"id":1,"app_id":"one","x":-1900,"y":-180,"width":600,"height":400,"focused":true}]' >"$WINDOWS_FILE"
selection=$(SLURP_REPLY='-1800,-100 1x1' region smart)
[[ $selection == "-1900,-180 600x400" ]] ||
  fail "a click on a monitor left of the origin snaps correctly" "got: $selection"
pass "a monitor placed left of the origin snaps like any other"

printf '%s\n' '[{"name":"eDP-1","focused":true,"x":0,"y":0,"width":1920,"height":1080,"scale":1}]' >"$MONITORS_FILE"
printf '%s\n' '[{"id":1,"app_id":"one","x":0,"y":30,"width":960,"height":1050,"focused":false},
                {"id":2,"app_id":"two","x":960,"y":30,"width":960,"height":1050,"focused":true}]' >"$WINDOWS_FILE"

# Cancelling the picker is exit 1 and no output, so a caller stops rather than
# capturing something arbitrary.
output=$(SLURP_REPLY= region region)
status=$?
(( status == 1 )) || fail "a cancelled pick exits 1" "exited $status"
[[ -z $output ]] || fail "a cancelled pick prints nothing" "got: $output"
pass "a cancelled pick exits 1 and prints nothing"

# --keep-freeze hands the caller the freeze PID on the first line, because it
# is the caller that has to hold the freeze open until grim has run.
output=$(SLURP_REPLY='100,100 400x300' region region --keep-freeze)
[[ $(sed -n 1p <<<"$output") =~ ^[0-9]+$ ]] ||
  fail "--keep-freeze prints the freeze PID first" "got: $output"
[[ $(sed -n 2p <<<"$output") == "100,100 400x300" ]] ||
  fail "--keep-freeze prints the selection second" "got: $output"
pkill -x hyprpicker 2>/dev/null
pass "--keep-freeze hands the caller the freeze to close"

# Windows with no position (niri) have no rectangles to snap to, and the modes
# that need them say so rather than quietly offering monitors only.
printf '%s\n' '[{"id":1,"app_id":"one","x":null,"y":null,"width":196,"height":671,"focused":true}]' >"$WINDOWS_FILE"
for mode in windows smart; do
  output=$(NIRI_SOCKET=/nonexistent region $mode 2>&1)
  status=$?
  (( status == 2 )) || fail "$mode without window rectangles is refused" "exited $status"
  [[ $output == *"niri does not place its tiled windows"* ]] ||
    fail "$mode names niri as the reason" "got: $output"
done
pass "window snapping is refused, and explained, where windows have no position"

# The modes that need nothing from the window list still work there.
selection=$(NIRI_SOCKET=/nonexistent SLURP_REPLY= region fullscreen)
[[ $selection == "0,0 1920x1080" ]] ||
  fail "fullscreen still works without window rectangles" "got: $selection"
selection=$(NIRI_SOCKET=/nonexistent SLURP_REPLY='10,10 100x100' region region)
[[ $selection == "10,10 100x100" ]] ||
  fail "region still works without window rectangles" "got: $selection"
pass "region and fullscreen work without window rectangles"
