#!/bin/bash
#
# The windows on screen, three ways, and the one thing niri will not say.
#
# sway and mango report an absolute rectangle per window. niri reports a size
# and a [column, row] index, and its one pixel field is null for tiled windows.
# So x and y are null on niri, which is what stops strapd-capture-region from
# offering window snapping there.
#
# The replies below were captured in the VM.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

export PATH="$STUB_BIN:$ROOT/bin:$PATH"

cat >"$STUB_BIN/niri" <<'STUB'
#!/bin/bash
case "$*" in
  "msg -j windows") cat "$STUB_DIR/windows.json" ;;
  "msg -j workspaces") cat "$STUB_DIR/extra.json" ;;
esac
STUB
cat >"$STUB_BIN/swaymsg" <<'STUB'
#!/bin/bash
cat "$STUB_DIR/windows.json"
STUB
cat >"$STUB_BIN/mmsg" <<'STUB'
#!/bin/bash
cat "$STUB_DIR/windows.json"
STUB
chmod +x "$STUB_BIN/niri" "$STUB_BIN/swaymsg" "$STUB_BIN/mmsg"

STUB_DIR=$STUB_BIN
export STUB_DIR

ask() {
  local backend=$1 windows=$2 extra=${3:-'[]'} flag=${4:-}

  printf '%s\n' "$windows" >"$STUB_BIN/windows.json"
  printf '%s\n' "$extra" >"$STUB_BIN/extra.json"

  unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
  case "$backend" in
    niri) export NIRI_SOCKET=/nonexistent ;;
    sway) export SWAYSOCK=/nonexistent ;;
    mango) export MANGO_INSTANCE_SIGNATURE=/nonexistent ;;
  esac

  strapd-wm-windows ${flag:+"$flag"}
}

niri_windows='[{"id":4,"title":"foot","app_id":"one","pid":2180,"workspace_id":1,"is_focused":false,
                "layout":{"pos_in_scrolling_layout":[1,1],"window_size":[196,671],"tile_pos_in_workspace_view":null}},
               {"id":5,"title":"foot","app_id":"two","pid":2181,"workspace_id":1,"is_focused":true,
                "layout":{"pos_in_scrolling_layout":[2,1],"window_size":[196,671],"tile_pos_in_workspace_view":null}},
               {"id":9,"title":"elsewhere","app_id":"three","pid":2199,"workspace_id":2,"is_focused":false,
                "layout":{"pos_in_scrolling_layout":[1,1],"window_size":[196,671],"tile_pos_in_workspace_view":null}}]'
niri_workspaces='[{"id":1,"idx":1,"is_active":true},{"id":2,"idx":2,"is_active":false}]'

sway_windows='{"type":"root","nodes":[{"type":"output","nodes":[
  {"type":"workspace","nodes":[
    {"type":"con","id":8,"pid":2168,"app_id":"one","name":"foot","visible":true,"focused":false,
     "rect":{"x":427,"y":27,"width":427,"height":693},"nodes":[],"floating_nodes":[]},
    {"type":"con","id":9,"pid":2169,"app_id":"two","name":"foot","visible":true,"focused":true,
     "rect":{"x":854,"y":27,"width":426,"height":693},"nodes":[],"floating_nodes":[]},
    {"type":"con","id":12,"pid":2200,"app_id":"hidden","name":"scratch","visible":false,"focused":false,
     "rect":{"x":0,"y":0,"width":100,"height":100},"nodes":[],"floating_nodes":[]}],
   "floating_nodes":[]}],"floating_nodes":[]}],"floating_nodes":[]}'

mango_windows='{"clients":[
  {"id":4,"pid":2196,"title":"foot","appid":"one","x":10,"y":10,"width":701,"height":780,"is_visible":true,"is_focused":true},
  {"id":3,"pid":2197,"title":"foot","appid":"two","x":716,"y":10,"width":554,"height":780,"is_visible":true,"is_focused":false},
  {"id":7,"pid":2201,"title":"hidden","appid":"three","x":0,"y":0,"width":100,"height":100,"is_visible":false,"is_focused":false}]}'

niri_expected='[{"id":4,"pid":2180,"app_id":"one","title":"foot","x":null,"y":null,"width":196,"height":671,"focused":false},{"id":5,"pid":2181,"app_id":"two","title":"foot","x":null,"y":null,"width":196,"height":671,"focused":true}]'
sway_expected='[{"id":8,"pid":2168,"app_id":"one","title":"foot","x":427,"y":27,"width":427,"height":693,"focused":false},{"id":9,"pid":2169,"app_id":"two","title":"foot","x":854,"y":27,"width":426,"height":693,"focused":true}]'
mango_expected='[{"id":4,"pid":2196,"app_id":"one","title":"foot","x":10,"y":10,"width":701,"height":780,"focused":true},{"id":3,"pid":2197,"app_id":"two","title":"foot","x":716,"y":10,"width":554,"height":780,"focused":false}]'

for backend in niri sway mango; do
  case "$backend" in
    niri) windows=$niri_windows extra=$niri_workspaces expected=$niri_expected ;;
    sway) windows=$sway_windows extra='[]' expected=$sway_expected ;;
    mango) windows=$mango_windows extra='[]' expected=$mango_expected ;;
  esac

  actual=$(ask "$backend" "$windows" "$extra") || fail "$backend lists its windows"
  [[ $actual == "$expected" ]] ||
    fail "$backend's window list is the shape every caller gets" "expected: $expected
actual:   $actual"
  pass "$backend's window list is the shape every caller gets"
done

# Visible means visible: a window on a workspace nobody is looking at, or in
# sway's scratchpad, is not something a selection can snap to.
pass "a window nobody can see is not listed"

# --all asks the other question. Every fixture carries exactly one window the
# visible list drops, so the count going from two to three is the filter coming
# off. Closing every window before a reboot needs this; a screenshot needs the
# default, hence a flag rather than a new command.
for backend in niri sway mango; do
  case "$backend" in
    niri) windows=$niri_windows extra=$niri_workspaces ;;
    sway) windows=$sway_windows extra='[]' ;;
    mango) windows=$mango_windows extra='[]' ;;
  esac

  visible=$(ask "$backend" "$windows" "$extra" | jq 'length')
  every=$(ask "$backend" "$windows" "$extra" --all | jq 'length')
  [[ $visible == 2 && $every == 3 ]] ||
    fail "$backend --all lists the window the visible list drops" "visible: $visible, all: $every"
done
pass "--all lists the windows nobody can see as well"

status=0
output=$(ask sway "$sway_windows" '[]' --sideways 2>&1) || status=$?
(( status == 2 )) || fail "an unknown flag is a usage error" "exited $status"
[[ $output == *"Usage: strapd-wm-windows"* ]] ||
  fail "an unknown flag prints usage" "got: $output"
pass "an unknown flag is a usage error"

# The point of the whole file: a caller that wants rectangles has to check.
niri_out=$(ask niri "$niri_windows" "$niri_workspaces")
jq -e 'all(.[]; .x == null and .y == null and .width != null)' <<<"$niri_out" >/dev/null ||
  fail "niri reports sizes without positions" "got: $niri_out"
pass "niri reports a size for every window and a position for none"

for backend in sway mango; do
  case "$backend" in
    sway) windows=$sway_windows ;;
    mango) windows=$mango_windows ;;
  esac
  out=$(ask "$backend" "$windows")
  jq -e 'all(.[]; .x != null and .y != null)' <<<"$out" >/dev/null ||
    fail "$backend places every window it lists" "got: $out"
done
pass "sway and mango place every window they list"

# Sway leaves app_id null on an XWayland window and puts the class where X11 put
# it. Constructed, not captured: no X client survives the VM's software renderer.
xwayland='{"type":"root","nodes":[{"type":"con","id":8,"pid":42,"app_id":null,"name":"Files","visible":true,"focused":true,
  "window_properties":{"class":"Nautilus"},"rect":{"x":0,"y":0,"width":800,"height":600},"nodes":[],"floating_nodes":[]}],"floating_nodes":[]}'
out=$(ask sway "$xwayland")
[[ $(jq -r '.[0].app_id' <<<"$out") == Nautilus ]] ||
  fail "an XWayland window falls back to its class" "got: $out"
pass "an XWayland window falls back to its class"

# An empty desktop is a list, not a failure.
out=$(ask sway '{"type":"root","nodes":[],"floating_nodes":[]}') ||
  fail "an empty desktop still answers"
[[ $out == "[]" ]] || fail "an empty desktop is an empty list" "got: $out"
pass "an empty desktop is an empty list, not a failure"

unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
output=$(strapd-wm-windows 2>&1)
status=$?
(( status == 2 )) || fail "no compositor at all is its own exit status" "exited $status"
[[ $output == *"no niri, sway or mango session"* ]] ||
  fail "no compositor at all says so" "got: $output"
pass "no compositor at all is its own exit status, and says so"
