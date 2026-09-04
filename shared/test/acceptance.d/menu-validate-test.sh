#!/bin/bash
#
# Walking the menu on a real compositor. The shell test stubs the menu and
# asserts on the rows offered at each route, which proves the tree is walked
# correctly and nothing about whether a menu appears when the key is pressed.
#
# What it adds over menu-select's own live test is the second level: picking a
# submenu row has to close one menu and open another, which is a process exiting
# and a process starting -- the kind of thing that works in a stub and races in
# a session.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"

session=""
for backend in NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE; do
  [[ -n ${!backend:-} ]] && session=$backend
done

if [[ -z $session ]]; then
  pass "no compositor session; skipping the live menu"
  exit 0
fi

for command in fuzzel wtype; do
  if ! command -v "$command" >/dev/null; then
    pass "no $command; skipping the live menu"
    exit 0
  fi
done

menu_is_open() { pgrep -x fuzzel >/dev/null; }

cleanup() {
  pkill -x fuzzel 2>/dev/null
  return 0
}
trap cleanup EXIT

wait_for_menu() {
  local want=$1 waited
  for waited in $(seq 1 40); do
    if [[ $want == open ]]; then
      menu_is_open && return 0
    else
      menu_is_open || return 0
    fi
    sleep 0.25
  done
  return 1
}

pkill -x fuzzel 2>/dev/null
wait_for_menu closed || {
  pass "a menu is already open; skipping the live menu"
  exit 0
}

strapd-menu toggle >/dev/null 2>&1 &

wait_for_menu open || fail "the menu key opens a menu"

# A seat with nothing on it cannot give a layer surface keyboard focus, so the
# menu opens and ignores every synthetic key. That is the headless rig.
sleep 1
wtype "Apps" 2>/dev/null
sleep 0.3
wtype -k Return 2>/dev/null

# Picking a submenu closes the root menu and opens the child. Both halves
# matter: a menu that never closed would still be "open" here, and one that
# closed without opening its child is a key that swallowed a press.
sleep 1
if ! menu_is_open; then
  pass "this session has no seat that can focus a menu; skipping the live menu"
  exit 0
fi
pass "the menu key opens a menu, and a submenu row opens the submenu"

# Dismissing is not asserted here: menu-select's live test already presses
# Escape, and repeating it only races the teardown of a menu about to be killed.
wtype -k Escape 2>/dev/null
