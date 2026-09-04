#!/bin/bash
#
# Takes a real screenshot on the compositor that is actually running. The unit
# tests mock grim, slurp and the two shims, which proves the wiring and nothing
# about whether a capture works: a rectangle in the wrong coordinate space, a
# compositor that will not answer a screencopy request, or a freeze that never
# lifts all look fine to a stub.
#
# Only `fullscreen` is exercised, because it is the one mode that needs no
# pointer.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require jq

export PATH="$ROOT/bin:$PATH"

session=""
for backend in NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE; do
  [[ -n ${!backend:-} ]] && session=$backend
done

if [[ -z $session ]]; then
  pass "no compositor session; skipping the live screenshot"
  exit 0
fi

require grim

# A picker already open means the first thing the screenshot script does is
# cancel it, which is correct and would look like a failure here.
if pgrep -u "$(id -u)" -x slurp >/dev/null 2>&1; then
  pass "a picker is already open; skipping the live screenshot"
  exit 0
fi

geometry=$(strapd-capture-region fullscreen) ||
  fail "the picker names the focused monitor" "exited $? under $session"
[[ $geometry =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] ||
  fail "the picker names a rectangle" "got: $geometry"
pass "the picker names the focused monitor as a rectangle"

want_width=${BASH_REMATCH[3]}
want_height=${BASH_REMATCH[4]}

# The rectangle has to be the monitor's, in the monitor's own coordinates.
jq -e --argjson w "$want_width" --argjson h "$want_height" \
  'any(.[]; .focused and .width == $w and .height == $h)' \
  <(strapd-wm-monitors) >/dev/null ||
  fail "the rectangle is the focused monitor's own size" \
       "picker said ${want_width}x${want_height}; monitors say $(strapd-wm-monitors)"
pass "the rectangle is the focused monitor's own size"

shots=$(mktemp -d)
trap 'rm -rf "$shots"' EXIT

# STRAPD_SCREENSHOT_DIR keeps the test out of the user's Pictures directory.
path=$(STRAPD_SCREENSHOT_DIR="$shots" strapd-capture-screenshot fullscreen save) ||
  fail "a screenshot is taken" "exited $? under $session"

[[ -s $path ]] || fail "the screenshot file has content" "got: $path"
pass "a screenshot is written"

# A PNG says its own dimensions in the IHDR chunk, 16 bytes in. A capture at a
# different size to the rectangle asked for means the geometry is in the wrong
# coordinate space, which is what a scaled display would expose.
read -r got_width got_height < <(
  od -An -tu4 -j16 -N8 --endian=big "$path" 2>/dev/null ||
    od -An -tu4 -j16 -N8 "$path"
)
(( got_width == want_width && got_height == want_height )) ||
  fail "the screenshot is the size that was asked for" \
       "asked for ${want_width}x${want_height}, got ${got_width}x${got_height}"
pass "the screenshot is the size that was asked for"

# The freeze must not outlive the capture: hyprpicker holds a fullscreen layer
# surface, and one left running is an unresponsive-looking desktop.
sleep 1
if pgrep -x hyprpicker >/dev/null; then
  pkill -x hyprpicker
  fail "the screen freeze is closed" "hyprpicker was still running afterwards"
fi
pass "the screen freeze does not outlive the capture"
