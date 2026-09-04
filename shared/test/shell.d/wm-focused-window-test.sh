#!/bin/bash
#
# One question, three compositors, one answer shape. niri calls the field app_id
# and mango appid; sway calls the title `name`, leaves app_id null for XWayland
# windows, and reports the workspace as focused when it holds no windows.
#
# The replies below were captured in the VM. The XWayland one at the bottom was
# built from the tree sway documents, because no X client survives the VM's
# software renderer. test/acceptance.d does the live half.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

export PATH="$STUB_BIN:$ROOT/bin:$PATH"

# Each stub answers the one query the script makes of it, out of $REPLY_FILE.
for backend in niri swaymsg mmsg; do
  cat >"$STUB_BIN/$backend" <<'STUB'
#!/bin/bash
cat "$REPLY_FILE"
STUB
  chmod +x "$STUB_BIN/$backend"
done

ask() {
  local backend=$1 reply=$2

  REPLY_FILE="$STUB_BIN/reply.json"
  printf '%s\n' "$reply" >"$REPLY_FILE"
  export REPLY_FILE

  unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
  case "$backend" in
    niri) export NIRI_SOCKET=/nonexistent ;;
    sway) export SWAYSOCK=/nonexistent ;;
    mango) export MANGO_INSTANCE_SIGNATURE=/nonexistent ;;
  esac

  strapd-wm-focused-window
}

niri_reply='{"id":2,"title":"foot","app_id":"shapeterm","pid":610,"workspace_id":1,"is_focused":true,"is_floating":false}'
sway_reply='{"type":"root","nodes":[{"type":"output","nodes":[{"type":"workspace","focused":false,"nodes":[{"type":"con","focused":true,"pid":573,"app_id":"shapeterm","name":"foot"}],"floating_nodes":[]}],"floating_nodes":[]}],"floating_nodes":[]}'
mango_reply='{"id":1,"pid":1015,"title":"foot","appid":"shapeterm","monitor":"Virtual-1","is_focused":true}'

for backend in niri sway mango; do
  case "$backend" in
    niri) reply=$niri_reply pid=610 ;;
    sway) reply=$sway_reply pid=573 ;;
    mango) reply=$mango_reply pid=1015 ;;
  esac

  window=$(ask "$backend" "$reply") ||
    fail "$backend reports the focused window"

  expected='{"pid":'$pid',"app_id":"shapeterm","title":"foot"}'
  [[ $window == "$expected" ]] ||
    fail "$backend's answer is the shape every caller gets" "expected: $expected
actual:   $window"
  pass "$backend's answer is the shape every caller gets"
done

# An empty desktop is a normal state, not a failure to report: exit non-zero
# and say nothing, so a caller can fall back rather than parse an error.
declare -A EMPTY=(
  [niri]='null'
  [sway]='{"type":"root","focused":false,"nodes":[{"type":"workspace","focused":true,"nodes":[],"floating_nodes":[]}],"floating_nodes":[]}'
  [mango]='{"error":"no focused client"}'
)

for backend in niri sway mango; do
  output=$(ask "$backend" "${EMPTY[$backend]}")
  status=$?

  (( status != 0 )) || fail "$backend with nothing focused is not a success" "got: $output"
  [[ -z $output ]] || fail "$backend with nothing focused prints nothing" "got: $output"
  pass "$backend with nothing focused exits non-zero and prints nothing"
done

# Sway leaves app_id null on an XWayland window and puts the class where X11 put
# it -- app_id criteria match Wayland views, class criteria match X11 ones,
# which is why default/sway/windows.conf catches every window with a title
# match. Something is better than null for a caller matching on app-id.
#
# Constructed, not captured: see the note at the top.
xwayland='{"type":"root","nodes":[{"type":"con","focused":true,"pid":42,"app_id":null,"name":"Files","window_properties":{"class":"Nautilus"}}],"floating_nodes":[]}'
window=$(ask sway "$xwayland") || fail "sway reports an XWayland window"
[[ $(jq -r '.app_id' <<<"$window") == Nautilus ]] ||
  fail "an XWayland window falls back to its class" "got: $window"
pass "an XWayland window falls back to its class"

# Run outside a session and the answer is not "nothing focused" but "nobody to
# ask", which is a different thing to a caller deciding whether to fall back.
unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
output=$(strapd-wm-focused-window 2>&1)
status=$?
(( status == 2 )) || fail "no compositor at all is its own exit status" "exited $status"
[[ $output == *"no niri, sway or mango session"* ]] ||
  fail "no compositor at all says so" "got: $output"
pass "no compositor at all is its own exit status, and says so"
