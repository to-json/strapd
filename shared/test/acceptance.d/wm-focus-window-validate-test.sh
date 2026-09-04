#!/bin/bash
#
# Focuses a window on the compositor that is actually running. The shell test
# replays captured window lists and checks the command each backend would be
# sent, which proves the matching and nothing about whether it works: niri
# answers success for a window id that does not exist, and mango for a `focusid`
# it then ignores, so a wrong focus command is invisible to a fixture.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require jq

export PATH="$ROOT/bin:$PATH"

session=""
for backend in NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE; do
  [[ -n ${!backend:-} ]] && session=$backend
done

if [[ -z $session ]]; then
  pass "no compositor session; skipping the live focus-window query"
  exit 0
fi

require foot

# Two windows, so focusing is a change and not a coincidence: whichever one the
# compositor focused on its own, the test asks for the other.
foot --app-id=strapd.test.one -e sleep 60 >/dev/null 2>&1 &
one=$!
foot --app-id=strapd.test.two -e sleep 60 >/dev/null 2>&1 &
two=$!
trap 'kill "$one" "$two" 2>/dev/null' EXIT

focused_app_id() { strapd-wm-focused-window 2>/dev/null | jq -r '.app_id // empty'; }

for _ in {1..20}; do
  [[ $(focused_app_id) == strapd.test.* ]] && break
  sleep 0.5
done

start=$(focused_app_id)
[[ $start == strapd.test.* ]] ||
  fail "both test windows opened" "10s after launching two terminals, focus is on '$start'"

case "$start" in
  strapd.test.one) other=strapd.test.two ;;
  *) other=strapd.test.one ;;
esac

strapd-wm-focus-window "$other" ||
  fail "the running compositor focuses a window by app-id" "exited $? asking for $other"

# The compositor may have a workspace or tag switch to animate first.
for _ in {1..20}; do
  [[ $(focused_app_id) == "$other" ]] && break
  sleep 0.5
done

[[ $(focused_app_id) == "$other" ]] ||
  fail "the window it says it focused is the focused window" \
       "asked for $other under $session; focus is on '$(focused_app_id)'"
pass "the running compositor focuses a window by app-id"

# The title half of the match, live. What foot puts in the title depends on how
# it was configured, so the test asks the compositor rather than assuming.
title=$(strapd-wm-focused-window | jq -r '.title // empty')
[[ -n $title ]] || fail "the focused window has a title to match on" "got: '$title'"
strapd-wm-focus-window "$title" ||
  fail "a window is findable by its title" "exited $? asking for '$title'"
pass "a window is findable by its title"

# Nothing matching is exit 1, the answer strapd-launch-or-focus turns into a
# launch. An app-id no window has must not come back as a success.
if strapd-wm-focus-window strapd.test.nothing; then
  fail "a pattern no window matches is not a success" "exited 0 under $session"
fi
pass "a pattern no window matches exits non-zero"

# The whole point of the shim, end to end: an open window gets focused rather
# than a second copy launched.
strapd-launch-or-focus strapd.test.one "false" ||
  fail "launch-or-focus focuses rather than launching" "exited $? with a window open"
pass "launch-or-focus focuses an open window rather than launching another"
