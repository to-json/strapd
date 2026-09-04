#!/bin/bash
#
# The cheatsheet. strapd reads the file the compositor configs are generated
# from, so what is worth testing is that the list a user sees and the list their
# compositor was configured with are the same list. Two ways they could drift:
# an action the running compositor cannot do showing up as though it could, and
# a repeated action appearing once as a literal "{n}".

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command yq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

STUB_BIN="$test_tmp/bin"
mkdir -p "$STUB_BIN"

cat >"$STUB_BIN/strapd-menu-select" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >"$STUB_DIR/menu.args"
cat >"$STUB_DIR/menu.rows"
STUB
chmod +x "$STUB_BIN/strapd-menu-select"

export STUB_DIR="$test_tmp"

keybindings() {
  env STRAPD_PATH="$ROOT" PATH="$STUB_BIN:$ROOT/bin:$PATH" STUB_DIR="$test_tmp" \
    NIRI_SOCKET="" SWAYSOCK="" MANGO_INSTANCE_SIGNATURE="" \
    "$ROOT/bin/strapd-menu-keybindings" "$@"
}

niri=$(keybindings --print --backend niri) || fail "the cheatsheet prints" "$niri"

grep -q '→' <<<"$niri" || fail "a row is a chord and what it does" "$(head -3 <<<"$niri")"
pass "a row is a chord and what it does"

# The canonical MOD+MOD+KEY of the table, spaced out for reading. A row still
# carrying a raw "SUPER+W" is one nobody spaced.
grep -q 'SUPER + W .* → Close focused window' <<<"$niri" ||
  fail "a chord is spelled out" "$(grep -i 'close focused' <<<"$niri")"
pass "a chord is spelled out"

# window.windowed_fullscreen is unsupported on sway and dispatches on the other
# two, which makes it the case separating "read the table" from "read the table
# for this compositor".
grep -q 'CTRL + F' <<<"$niri" ||
  fail "niri lists the action it supports" "$niri"
sway=$(keybindings --print --backend sway)
grep -q 'SUPER + CTRL + F .*fullscreen while leaving it' <<<"$sway" &&
  fail "sway does not list an action it cannot do" "$(grep -i 'leaving it' <<<"$sway")"
pass "an action the compositor cannot do is not listed"

# Counting the two lists against each other proves nothing -- each compositor is
# missing different actions and they happen to come out even. Each list against
# the table it came from is the whole claim this command makes.
for backend in niri sway mango; do
  listed=$(keybindings --print --backend "$backend" | wc -l)
  dispatched=$(yq -p toml -o json "$ROOT/keybindings/actions.toml" |
    jq --arg backend "$backend" '
      [ .action[]
        | select(.[$backend].dispatch != null)
        | (if has("repeat") then (.repeat.range[1] - .repeat.range[0] + 1) else 1 end)
      ] | add')
  (( listed == dispatched )) ||
    fail "every dispatchable action is listed, and only those" \
      "$backend: $listed rows for $dispatched dispatches"
done
pass "every dispatchable action is listed for each compositor, and only those"

# `repeat` puts nine workspace keys in the table as one action. A cheatsheet
# showing "SUPER + {n}" would be showing the template rather than the keys.
grep -q '{n}' <<<"$niri" && fail "no row shows a template" "$(grep '{n}' <<<"$niri")"
for n in 1 5 9; do
  grep -q "SUPER + $n .*workspace $n" <<<"$niri" ||
    fail "every repeated key gets its own row" "missing workspace $n"
done
pass "a repeated action is listed once per key, not once as a template"

# The most obvious thing to look up in a cheatsheet is how to open it again.
grep -q 'SUPER + SHIFT + K .*keybindings' <<<"$niri" ||
  fail "the cheatsheet lists its own key" "$(grep -i keybind <<<"$niri")"
pass "the cheatsheet lists its own key"

detected=$(env STRAPD_PATH="$ROOT" PATH="$STUB_BIN:$ROOT/bin:$PATH" \
  MANGO_INSTANCE_SIGNATURE=/nonexistent \
  "$ROOT/bin/strapd-menu-keybindings" --print)
[[ $detected == "$(keybindings --print --backend mango)" ]] ||
  fail "the running compositor is the one it reports on"
pass "the running compositor is the one it reports on"

output=$(keybindings --print 2>&1)
status=$?
(( status == 2 )) || fail "no session and no --backend is its own exit status" "exited $status"
[[ $output == *"no niri, sway or mango session"* ]] ||
  fail "no session says so" "got: $output"
pass "no session and no --backend is its own exit status, and says so"

output=$(keybindings --print --backend hyprland 2>&1)
(( $? != 0 )) || fail "an unknown compositor is refused"
pass "an unknown compositor is refused"

keybindings --backend niri
[[ $(cat "$test_tmp/menu.rows") == "$niri" ]] ||
  fail "the menu is handed the same rows --print shows" "$(head -3 "$test_tmp/menu.rows")"
pass "the menu is handed the same rows --print shows"

[[ $(cat "$test_tmp/menu.args") == "Keybindings"* ]] ||
  fail "the menu is given a prompt" "$(cat "$test_tmp/menu.args")"
pass "the menu is given a prompt"
