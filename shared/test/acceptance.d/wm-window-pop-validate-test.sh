#!/bin/bash
#
# Pops a real window out of the tiling and puts it back. The shell test checks
# the three dialects against a stubbed window record, which proves the strings
# and nothing about whether the window moves.
#
# It opens its own window and closes it again, and finds it by title rather than
# by asking what is focused, because in a session with anything else in it those
# stop being the same window partway through.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require jq

export PATH="$ROOT/bin:$PATH"

session=""
for backend in NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE; do
  [[ -n ${!backend:-} ]] && session=$backend
done

if [[ -z $session ]]; then
  pass "no compositor session; skipping the live pop"
  exit 0
fi

if ! command -v foot >/dev/null; then
  pass "no foot to pop; skipping the live pop"
  exit 0
fi

WIDTH=500
HEIGHT=400

# The window this test opened, by title, normalized to
# {"floating":bool,"pid":N,"width":N,"height":N}. strapd-wm-windows would give
# the geometry but not the floating state, which is the whole question here.
MARKER="strapd-window-pop-$$"

window_state() {
  case "$session" in
    NIRI_SOCKET)
      niri msg -j windows |
        jq -c --arg marker "$MARKER" 'first(.[] | select(.title == $marker))
               | {floating: .is_floating, pid,
                  width: .layout.window_size[0], height: .layout.window_size[1]}'
      ;;
    SWAYSOCK)
      swaymsg -t get_tree |
        jq -c --arg marker "$MARKER" 'first(recurse(.nodes[]?, .floating_nodes[]?)
                     | select(.name == $marker))
               | {floating: (.type == "floating_con"), pid,
                  width: .rect.width, height: .rect.height}'
      ;;
    MANGO_INSTANCE_SIGNATURE)
      mmsg get all-clients |
        jq -c --arg marker "$MARKER" 'first(.clients[]? | select(.title == $marker))
               | {floating: .is_floating, pid, width, height}'
      ;;
  esac
}

# The pop acts on whatever is focused, so asking is what makes that true.
focus_marked() {
  local id
  case "$session" in
    NIRI_SOCKET)
      id=$(niri msg -j windows | jq -r --arg marker "$MARKER" \
        'first(.[] | select(.title == $marker)) | .id')
      niri msg action focus-window --id "$id" >/dev/null 2>&1
      ;;
    SWAYSOCK)
      swaymsg "[title=\"^${MARKER}$\"] focus" >/dev/null 2>&1
      ;;
    MANGO_INSTANCE_SIGNATURE)
      id=$(mmsg get all-clients | jq -r --arg marker "$MARKER" \
        'first(.clients[]? | select(.title == $marker)) | .id')
      mmsg dispatch focusid "client,$id" >/dev/null 2>&1
      ;;
  esac
}

field() {
  jq -r ".$2" <<<"$1"
}

wait_for_floating() {
  local want=$1 state=""

  for _ in $(seq 1 40); do
    state=$(window_state 2>/dev/null) || state=""
    [[ -n $state && $(field "$state" floating) == "$want" ]] && { printf '%s\n' "$state"; return 0; }
    sleep 0.25
  done

  printf '%s\n' "$state"
  return 1
}

# -T so the window can be found again, and --override so no theme or user
# config renames it out from under the search.
setsid foot -T "$MARKER" --override=locked-title=yes -e sleep 600 >/dev/null 2>&1 &

cleanup() {
  local pid
  pid=$(window_state 2>/dev/null | jq -r '.pid // empty') || pid=""
  [[ -n $pid ]] && kill "$pid" 2>/dev/null
  return 0
}
trap cleanup EXIT

opened=""
for _ in $(seq 1 40); do
  opened=$(window_state 2>/dev/null) || opened=""
  [[ -n $opened ]] && break
  sleep 0.25
done
[[ -n $opened ]] || fail "a window to pop"
[[ $(field "$opened" floating) == false ]] ||
  fail "the window starts tiled" "$opened"
pass "a tiled window to pop"

focus_marked
strapd-wm-window-pop "$WIDTH" "$HEIGHT"
popped=$(wait_for_floating true) || fail "the popped window floats" "$popped"
pass "the popped window floats"

# Within a character cell of what was asked for, not equal to it: foot rounds
# its surface down to whole cells, so 500x400 comes back as 494x370 on sway.
# The claim is that the request reached the compositor at all -- losing it
# entirely, which is what the resize race did, leaves some previous size.
width=$(field "$popped" width)
height=$(field "$popped" height)
(( width <= WIDTH && width >= WIDTH - 40 )) ||
  fail "the popped window is about $WIDTH wide" "$popped"
(( height <= HEIGHT && height >= HEIGHT - 40 )) ||
  fail "the popped window is about $HEIGHT tall" "$popped"
pass "the popped window is the size it was popped to"

focus_marked
strapd-wm-window-pop
tiled=$(wait_for_floating false) || fail "the same key puts it back" "$tiled"
pass "the same key puts it back"
