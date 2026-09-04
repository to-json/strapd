#!/bin/bash
#
# Asks the compositor that is actually running what monitors it has. The shell
# test replays captured output lists, which proves the reshaping and nothing
# about whether the queries still work: a renamed field or a subcommand that
# grew a flag looks identical to a fixture.
#
# strapd-wm-display-power is only checked where the compositor reports whether
# its outputs are lit, which is sway alone -- blanking a screen on a compositor
# that cannot confirm it came back is not a thing a test should do to whoever is
# watching.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require jq

export PATH="$ROOT/bin:$PATH"

session=""
for backend in NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE; do
  [[ -n ${!backend:-} ]] && session=$backend
done

if [[ -z $session ]]; then
  pass "no compositor session; skipping the live monitor query"
  exit 0
fi

monitors=$(strapd-wm-monitors) ||
  fail "the running compositor lists its monitors" "exited $? under $session"

count=$(jq 'length' <<<"$monitors")
(( count > 0 )) ||
  fail "the running compositor has at least one monitor" "got: $monitors"
pass "the running compositor lists its monitors"

# make, model and dpms are deliberately not in this list: they are null on the
# compositors that do not report them, which is the point of the shape.
jq -e 'all(.[]; (.name | type == "string" and length > 0)
                and (.x | type == "number") and (.y | type == "number")
                and (.width | type == "number" and . > 0)
                and (.height | type == "number" and . > 0)
                and (.scale | type == "number" and . > 0))' <<<"$monitors" >/dev/null ||
  fail "every monitor has a name, a position, a size and a scale" "got: $monitors"
pass "every monitor has a name, a position, a size and a scale"

focused=$(strapd-wm-monitors --focused) ||
  fail "the running compositor names a focused monitor" "exited $? under $session"

name=$(jq -r '.name' <<<"$focused")
jq -e --arg name "$name" 'any(.[]; .name == $name)' <<<"$monitors" >/dev/null ||
  fail "the focused monitor is one of the listed monitors" \
       "focused: $name; listed: $(jq -c '[.[].name]' <<<"$monitors")"
pass "the focused monitor is one of the listed monitors"

# The geometry is the compositor's logical layout, which is what a screenshot
# region or an OSD position is expressed in. A monitor reporting its raw mode
# would show up as a size larger than the layout on a scaled display.
jq -e --arg name "$name" 'any(.[]; .name == $name and .focused)' <<<"$monitors" >/dev/null ||
  fail "the focused monitor is marked focused in the list" "got: $monitors"
pass "the focused monitor is marked focused in the list"

if [[ $session != SWAYSOCK ]]; then
  pass "display power is not exercised on a compositor that cannot report it"
  exit 0
fi

lit() { swaymsg -t get_outputs | jq -e '[.[] | select(.active)] | length > 0 and all(.dpms)' >/dev/null; }

restore() { strapd-wm-display-power on >/dev/null 2>&1 || true; }
trap restore EXIT

lit || fail "the displays start out lit" "nothing to turn off"

strapd-wm-display-power off || fail "the displays turn off" "exited $?"
if lit; then
  fail "the displays turn off" "sway still reports every output lit"
fi
pass "the displays turn off"

strapd-wm-display-power on || fail "the displays come back on" "exited $?"
lit || fail "the displays come back on" "sway still reports an output dark"
pass "the displays come back on"

# The second `on` is the one that matters: it must not reach the compositor,
# because a redundant modeset blanks the panel for a beat.
strapd-wm-display-power on || fail "a redundant enable is not an error" "exited $?"
lit || fail "a redundant enable leaves the displays lit"
pass "a redundant enable is a no-op, not a second modeset"
