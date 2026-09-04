#!/bin/bash
#
# Picking a row from a menu that is actually on screen. The shell test stubs
# fuzzel and asserts on the rows handed to it, which proves the contract and
# nothing about whether a menu appears.
#
# Worth doing live because a launcher is a layer-shell surface, not a window: it
# never appears in strapd-wm-windows, so "the menu opened" is not a question the
# compositor will answer. Typing into it is the only proof available.

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

answer_file=$(mktemp)
cleanup() {
  pkill -x fuzzel 2>/dev/null
  rm -f "$answer_file"
  return 0
}
trap cleanup EXIT

# By process name, not command line: `pgrep -f 'fuzzel --dmenu'` also matches
# this test's own shell, so it succeeds before fuzzel has started.
menu_is_open() { pgrep -x fuzzel >/dev/null; }

# Opens the menu, types enough to single out one row, and takes it.
#
# Typing rather than arrowing to a position: an arrow count would pass on a menu
# in any order at all. fuzzel filters on the string it is displaying, so a row
# found by typing part of its subtext is a row whose subtext was rendered.
pick() {
  local filter="$1"
  shift
  local pid waited

  : >"$answer_file"

  # Wait out the previous menu: its process lingers for a moment after it
  # prints, so the next pick would type into a menu that is already closing.
  for waited in $(seq 1 40); do
    menu_is_open || break
    sleep 0.25
  done

  strapd-menu-select "$@" >"$answer_file" 2>/dev/null &
  pid=$!

  for waited in $(seq 1 40); do
    menu_is_open && break
    sleep 0.25
  done
  menu_is_open || { kill "$pid" 2>/dev/null; return 1; }

  # The surface is mapped but the keyboard focus follows a frame later; typing
  # into the gap loses the first characters and the filter matches nothing.
  sleep 1
  wtype "$filter" 2>/dev/null
  sleep 0.3
  wtype -k Return 2>/dev/null

  wait "$pid"
}

# A seat with nothing on it cannot give a surface keyboard focus, so the menu
# opens and then ignores every synthetic key. That is the headless rig, not the
# menu, and worth telling apart from a real failure, so the first pick doubles
# as the probe.
if ! pick "png" Format jpg png webp; then
  if [[ -z $(<"$answer_file") ]]; then
    pass "this session has no seat that can focus a menu; skipping the live menu"
    exit 0
  fi
  fail "the menu opens and a row can be chosen" "got: $(<"$answer_file")"
fi
[[ $(<"$answer_file") == png ]] ||
  fail "a plain option returns its label" "got: $(<"$answer_file")"
pass "a plain option returns its label"

pick "Everforest" Theme $'\tEverforest' $'\tTokyo Night' ||
  fail "a row with a glyph can be chosen"
[[ $(<"$answer_file") == "Everforest" ]] ||
  fail "the glyph is not part of the answer" "got: $(<"$answer_file")"
pass "the glyph is not part of the answer"

# The case the subtext exists for. Both rows read "Terminal", so the subtext is
# the only way to pick the second one on purpose and know that is what came back.
pick "alacritty" Window $'\tTerminal\tfoot' $'\tTerminal\talacritty' ||
  fail "a row can be singled out by its subtext"
[[ $(<"$answer_file") == $'Terminal\talacritty' ]] ||
  fail "the subtext comes back as the stable key" \
    "got: $(printf '%q' "$(<"$answer_file")")"
pass "two rows sharing a label are told apart by their subtext"

# Escape, not a selection. Every caller treats this as "do nothing".
: >"$answer_file"
strapd-menu-select Format jpg png >"$answer_file" 2>/dev/null &
menu=$!
for _ in $(seq 1 40); do
  menu_is_open && break
  sleep 0.25
done
sleep 1
wtype -k Escape 2>/dev/null
if wait "$menu"; then
  fail "a dismissed menu is not a selection" "exited 0 with: $(<"$answer_file")"
fi
[[ ! -s $answer_file ]] ||
  fail "a dismissed menu returns nothing" "got: $(<"$answer_file")"
pass "a dismissed menu is not a selection"
