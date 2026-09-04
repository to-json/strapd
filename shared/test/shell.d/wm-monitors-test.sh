#!/bin/bash
#
# One monitor list, three compositors, which disagree about more than field
# names: niri marks no output focused, sway alone says whether a monitor is lit,
# and mango reports no make or model and names the focused one only through the
# cursor position.
#
# The replies below were captured in the VM. Two-monitor cases are constructed,
# since the VM has one virtual output, and are marked where they appear.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

export PATH="$STUB_BIN:$ROOT/bin:$PATH"

# Two of the three need two queries answered, so the stubs dispatch on the
# subcommand rather than replaying one file.
cat >"$STUB_BIN/niri" <<'STUB'
#!/bin/bash
case "$*" in
  "msg -j outputs") cat "$STUB_DIR/outputs.json" ;;
  "msg -j focused-output") cat "$STUB_DIR/focused.json" ;;
esac
STUB
cat >"$STUB_BIN/swaymsg" <<'STUB'
#!/bin/bash
cat "$STUB_DIR/outputs.json"
STUB
cat >"$STUB_BIN/mmsg" <<'STUB'
#!/bin/bash
case "$*" in
  "get all-monitors") cat "$STUB_DIR/outputs.json" ;;
  "get cursorpos") cat "$STUB_DIR/focused.json" ;;
esac
STUB
chmod +x "$STUB_BIN/niri" "$STUB_BIN/swaymsg" "$STUB_BIN/mmsg"

STUB_DIR=$STUB_BIN
export STUB_DIR

ask() {
  local backend=$1 outputs=$2 focused=${3:-} ; shift 3 2>/dev/null || shift $#

  printf '%s\n' "$outputs" >"$STUB_BIN/outputs.json"
  printf '%s\n' "$focused" >"$STUB_BIN/focused.json"

  unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
  case "$backend" in
    niri) export NIRI_SOCKET=/nonexistent ;;
    sway) export SWAYSOCK=/nonexistent ;;
    mango) export MANGO_INSTANCE_SIGNATURE=/nonexistent ;;
  esac

  strapd-wm-monitors "$@"
}

niri_outputs='{"eDP-1":{"name":"eDP-1","make":"BOE","model":"0x0BCA","serial":null,
  "logical":{"x":0,"y":0,"width":1920,"height":1200,"scale":1.0,"transform":"Normal"}}}'
niri_focused='{"name":"eDP-1","make":"BOE","model":"0x0BCA",
  "logical":{"x":0,"y":0,"width":1920,"height":1200,"scale":1.0,"transform":"Normal"}}'
sway_outputs='[{"name":"eDP-1","make":"BOE","model":"0x0BCA","focused":true,"dpms":true,"active":true,
  "rect":{"x":0,"y":0,"width":1920,"height":1200},"scale":1.0,"transform":"normal"}]'
mango_outputs='{"monitors":[{"name":"eDP-1","active":true,"x":0,"y":0,"width":1920,"height":1200,"scale":1}]}'
mango_focused='{"x":639.5,"y":400,"monitor":"eDP-1"}'

# The same physical laptop panel as each of them describes it: what differs is
# exactly what the compositor withholds.
niri_expected='[{"name":"eDP-1","make":"BOE","model":"0x0BCA","focused":true,"dpms":null,"x":0,"y":0,"width":1920,"height":1200,"scale":1.0}]'
sway_expected='[{"name":"eDP-1","make":"BOE","model":"0x0BCA","focused":true,"dpms":true,"x":0,"y":0,"width":1920,"height":1200,"scale":1.0}]'
# mango knows the make -- its monitor rules match on it -- but does not report
# it, so null is the honest answer rather than an empty string that would read
# like a real value.
mango_expected='[{"name":"eDP-1","make":null,"model":null,"focused":true,"dpms":null,"x":0,"y":0,"width":1920,"height":1200,"scale":1}]'

for backend in niri sway mango; do
  case "$backend" in
    niri) outputs=$niri_outputs focused=$niri_focused expected=$niri_expected ;;
    sway) outputs=$sway_outputs focused='' expected=$sway_expected ;;
    mango) outputs=$mango_outputs focused=$mango_focused expected=$mango_expected ;;
  esac

  monitors=$(ask "$backend" "$outputs" "$focused") ||
    fail "$backend lists its monitors"

  [[ $monitors == "$expected" ]] ||
    fail "$backend's monitor list is the shape every caller gets" "expected: $expected
actual:   $monitors"
  pass "$backend's monitor list is the shape every caller gets"

  one=$(ask "$backend" "$outputs" "$focused" --focused) ||
    fail "$backend names its focused monitor"
  [[ $(jq -r '.name' <<<"$one") == eDP-1 ]] ||
    fail "$backend names its focused monitor" "got: $one"
  pass "$backend names its focused monitor"
done

# Geometry is logical on all three, so nothing divides by the scale or swaps
# width and height the way upstream's Hyprland version had to.
#
# Constructed: the VM's single virtual output runs at scale 1.
hidpi='{"eDP-1":{"name":"eDP-1","make":"Apple","model":"StudioDisplay",
  "logical":{"x":0,"y":0,"width":2560,"height":1440,"scale":2.0,"transform":"Normal"}}}'
monitors=$(ask niri "$hidpi" '{"name":"eDP-1"}')
[[ $(jq -r '.[0] | "\(.width)x\(.height)@\(.scale)"' <<<"$monitors") == "2560x1440@2.0" ]] ||
  fail "a scaled monitor reports its logical size" "got: $monitors"
pass "a scaled monitor reports its logical size, not its mode"

# Two monitors, one focused, constructed, and the case --focused exists for.
two='[{"name":"eDP-1","make":"BOE","model":"0x0BCA","focused":false,"dpms":true,"active":true,
      "rect":{"x":0,"y":0,"width":1920,"height":1200},"scale":1.0},
     {"name":"DP-1","make":"HPN","model":"OMEN X 25f","focused":true,"dpms":false,"active":true,
      "rect":{"x":1920,"y":0,"width":2560,"height":1440},"scale":1.0}]'
monitors=$(ask sway "$two" '')
[[ $(jq 'length' <<<"$monitors") == 2 ]] || fail "both monitors are listed" "got: $monitors"
one=$(ask sway "$two" '' --focused)
[[ $(jq -r '.name' <<<"$one") == DP-1 ]] ||
  fail "--focused picks the focused one of several" "got: $one"
pass "--focused picks the focused one of several"

# niri names no output focused when the session has none, and the array is
# still the right answer, so only --focused is a failure.
none=$(ask niri "$niri_outputs" 'null')
[[ $(jq -r '.[0].focused' <<<"$none") == false ]] ||
  fail "no focused output leaves every monitor unfocused" "got: $none"
output=$(ask niri "$niri_outputs" 'null' --focused)
status=$?
(( status != 0 )) || fail "no focused monitor is not a success" "got: $output"
[[ -z $output ]] || fail "no focused monitor prints nothing" "got: $output"
pass "a session with no focused monitor still lists its monitors"

unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
output=$(strapd-wm-monitors 2>&1)
status=$?
(( status == 2 )) || fail "no compositor at all is its own exit status" "exited $status"
[[ $output == *"no niri, sway or mango session"* ]] ||
  fail "no compositor at all says so" "got: $output"
pass "no compositor at all is its own exit status, and says so"

export SWAYSOCK=/nonexistent
output=$(strapd-wm-monitors --everything 2>&1)
status=$?
(( status == 2 )) || fail "an unknown flag is a usage error" "exited $status"
[[ $output == Usage:* ]] || fail "an unknown flag prints usage" "got: $output"
pass "an unknown flag is a usage error"
