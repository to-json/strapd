#!/bin/bash
#
# Reading tmux's keybindings back out of tmux. The command starts a throwaway
# server, sources a config into it and asks what it bound, rather than parsing
# the config: a `bind` this never sees is a row the cheatsheet silently lacks,
# and parsing would miss exactly the ones tmux resolves for itself.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command tmux

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

print_keybindings() {
  env STRAPD_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    "$ROOT/bin/strapd-menu-tmux-keybindings" --print "$@"
}

shipped=$(print_keybindings --config "$ROOT/config/tmux/tmux.conf") ||
  fail "the shipped tmux config lists its keybindings" "$shipped"

# The prefix leads the list, because every other row is spelled relative to it.
[[ $(head -1 <<<"$shipped") == "PREFIX"*"→"* ]] ||
  fail "the prefix chord leads the list" "$(head -3 <<<"$shipped")"
pass "the prefix chord leads the list"

# Whatever strapd binds, it binds something; an empty table means tmux read the
# config and found nothing, which is the failure this is here to catch.
(( $(wc -l <<<"$shipped") > 5 )) ||
  fail "the shipped config has keybindings to list" "$shipped"
pass "the shipped config has keybindings to list"

grep -q '→' <<<"$shipped" ||
  fail "every row names a chord and what it does" "$(head -3 <<<"$shipped")"
pass "every row names a chord and what it does"

# Chords tmux spells in its own shorthand: C- is CTRL, M- is ALT, and a bare
# lowercase letter stays lowercase because that is the key you press.
cat >"$test_tmp/tmux.conf" <<'CONF'
set -g prefix C-a
bind -N "Split sideways" v split-window -h
bind -N "Reload" r source-file ~/.config/tmux/tmux.conf
CONF

mine=$(print_keybindings --config "$test_tmp/tmux.conf")

[[ $(head -1 <<<"$mine") == *"CTRL + A"* ]] ||
  fail "a rebound prefix is reported as the chord it is" "$(head -1 <<<"$mine")"
pass "a rebound prefix is reported as the chord it is"

grep -q 'PREFIX + v.*→.*Split sideways' <<<"$mine" ||
  fail "a binding's note is what the row says it does" "$mine"
pass "a binding's note is what the row says it does"

# The note, not the command: `split-window -h` is what tmux runs, "Split
# sideways" is what the user was told it does.
grep -q 'split-window' <<<"$mine" &&
  fail "the row shows the note rather than the command" "$mine"
pass "the row shows the note rather than the command"

# The fallback is the shipped config, not an error: somebody who has not written
# a tmux.conf still gets the cheatsheet for the one they are running.
fallback=$(print_keybindings --config "$test_tmp/absent.conf") ||
  fail "a missing config falls back to the shipped one" "$fallback"
[[ $fallback == "$shipped" ]] ||
  fail "a missing config falls back to the shipped one" "got:
$fallback"
pass "a missing config falls back to the shipped one"

# A private socket, so this never reads, writes or kills the tmux the user is
# sitting in -- and listing would otherwise depend on whatever the default
# server already had loaded.
grep -q 'tmux -S "$socket"' "$ROOT/bin/strapd-menu-tmux-keybindings" ||
  fail "the throwaway server runs on a socket of its own"
pass "the throwaway server runs on a socket of its own"
