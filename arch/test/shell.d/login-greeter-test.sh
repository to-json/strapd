#!/bin/bash
#
# The login screen. Two things here can lock somebody out of their own machine
# without announcing it: a greeter command whose flags the greeter does not
# accept, leaving a blank VT, and taking over display-manager.service on a
# machine that already had one.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

CONFIG="$ROOT/etc/greetd/config.toml"
LAYER="$ROOT/install/login/all.sh"

[[ -f $CONFIG ]] || fail "a greetd config is shipped"
pass "a greetd config is shipped"

if command -v yq >/dev/null; then
  yq -p toml -o json "$CONFIG" >/dev/null 2>&1 ||
    fail "the greetd config is valid TOML" "$(yq -p toml -o json "$CONFIG" 2>&1 | head -3)"
  pass "the greetd config is valid TOML"
else
  pass "no yq; skipping the TOML check"
fi

command=$(sed -n 's/^command = "\(.*\)"$/\1/p' "$CONFIG")
[[ -n $command ]] || fail "the config names a greeter to run"

# The flags are the part that rots: tuigreet renames one, and the login screen
# is a blank VT on the next boot with the reason only in an unreachable journal.
if command -v tuigreet >/dev/null; then
  help=$(tuigreet --help 2>&1)
  while read -r flag; do
    grep -q -- "$flag" <<<"$help" ||
      fail "tuigreet accepts every flag the config passes it" "$flag is not in --help"
  done < <(grep -oE '(^|[[:space:]])--[a-z-]+' <<<"$command" | tr -d ' ')
  pass "tuigreet accepts every flag the config passes it"
else
  pass "no tuigreet installed; skipping the flag check"
fi

# Left to its default, tuigreet also searches the X11 paths, and strapd ships no
# X session.
#
# strapd's own directory, not the shared one: niri, sway and mango each drop a
# session file into /usr/share/wayland-sessions, and those three start a bare
# compositor with none of the session environment, which comes up looking like a
# broken strapd rather than failing.
[[ $command == *"--sessions /usr/share/strapd/wayland-sessions"* ]] ||
  fail "the greeter is pointed at strapd's own sessions, not the shared directory" \
    "$command"
pass "the greeter is pointed at strapd's own sessions, not the shared directory"

# Both directories are filled by install/place-tree.sh, which serves both routes.
placer="$ROOT/install/place-tree.sh"
grep -q 'target/wayland-sessions' "$placer" ||
  fail "the tree placer fills the directory the greeter reads"
grep -q 'root/usr/share/wayland-sessions' "$placer" ||
  fail "the tree placer also fills the shared directory, for other greeters"
pass "both directories are installed: one for strapd's greeter, one for any other"

sessions=$(ls "$ROOT"/default/wayland-sessions/*.desktop 2>/dev/null | wc -l)
(( sessions == 3 )) ||
  fail "three sessions are shipped for it to list" "found $sessions"
pass "three sessions are shipped for it to list"

# A machine that came with GDM or SDDM has display-manager.service pointing at
# it. Enabling a second either fails or quietly replaces what the user boots
# into, and an installer should not make that call for them.
grep -q 'display-manager.service' "$LAYER" ||
  fail "the login layer checks for an existing display manager"
grep -q 'systemctl enable greetd.service' "$LAYER" ||
  fail "the login layer enables greetd when nothing else owns the screen"
pass "an existing display manager is left alone"

# And it has to say so, because a silent skip looks identical to a silent
# success right up until the next reboot.
grep -q 'leaving the existing display manager alone' "$LAYER" ||
  fail "skipping the greeter is written to the install log"
pass "skipping the greeter is written to the install log"
