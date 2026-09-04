#!/bin/bash
#
# The one menu every other menu is made of. Nine commands ask this and none of
# them knows what draws it, so the contract is the thing under test, not fuzzel:
# a glyph is shown and never returned, and a row's subtext comes back as part of
# the answer, which is what lets a caller tell two same-labelled rows apart.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

STUB_BIN="$test_tmp/bin"
mkdir -p "$STUB_BIN"

# Records the arguments and rows it was handed, and picks whichever row
# FUZZEL_PICK names by index, which is what the real one prints under --index.
cat >"$STUB_BIN/fuzzel" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >"$STUB_DIR/args"
cat >"$STUB_DIR/rows"
[[ -n ${FUZZEL_PICK:-} ]] && printf '%s\n' "$FUZZEL_PICK"
exit 0
STUB
chmod +x "$STUB_BIN/fuzzel"

export STUB_DIR="$test_tmp"

select_from() {
  env PATH="$STUB_BIN:$ROOT/bin:$PATH" STUB_DIR="$test_tmp" \
    FUZZEL_PICK="${FUZZEL_PICK:-}" \
    "$ROOT/bin/strapd-menu-select" "$@"
}

rows() { cat "$test_tmp/rows"; }
menu_args() { cat "$test_tmp/args"; }

FUZZEL_PICK=1 answer=$(select_from Format jpg png webp)
[[ $answer == png ]] || fail "a plain option returns its label" "got: $answer"
pass "a plain option returns its label"

[[ $(rows) == 'jpg
png
webp' ]] || fail "every option is offered, in order" "$(rows)"
pass "every option is offered, in order"

FUZZEL_PICK=0 answer=$(select_from Theme $'\tEverforest' $'\tTokyo Night')
[[ $answer == "Everforest" ]] ||
  fail "a glyph is not part of the answer" "got: $answer"
pass "a glyph is not part of the answer"

grep -q 'Everforest' <<<"$(rows)" || fail "the label is shown" "$(rows)"
grep -q $'' <<<"$(rows)" || fail "the glyph is shown" "$(rows)"
pass "the glyph is shown even though it is not returned"

# Two rows, one label. Without the subtext coming back there is no way for the
# caller to know which was picked, which is the entire reason it exists.
FUZZEL_PICK=1 answer=$(select_from Window \
  $'\tTerminal\tfoot' \
  $'\tTerminal\talacritty')
[[ $answer == $'Terminal\talacritty' ]] ||
  fail "a subtext comes back with the label" "got: $(printf '%q' "$answer")"
pass "a subtext comes back with the label"

# fuzzel draws one line per row, so the subtext shares the label's line --
# but dropping it would leave the user picking between two identical rows.
(( $(grep -c 'Terminal' <<<"$(rows)") == 2 )) || fail "both rows are offered" "$(rows)"
grep -q 'alacritty' <<<"$(rows)" ||
  fail "the subtext is shown, not just returned" "$(rows)"
pass "the subtext is shown, not just returned"

# The subtext form with an empty glyph, a row a caller is allowed to write and
# the one that broke: `IFS=$'\t' read` treats tab as IFS whitespace, strips the
# leading empty field, and hands back the subtext as the whole answer.
FUZZEL_PICK=1 answer=$(select_from Window \
  $'\tTerminal\tfoot' \
  $'\tTerminal\talacritty')
[[ $answer == $'Terminal\talacritty' ]] ||
  fail "a row with no icon still returns label and subtext" \
    "got: $(printf '%q' "$answer")"
pass "a row with no icon still returns label and subtext"

# And it is not drawn with a stray leading space where the icon would be.
[[ $(head -1 "$test_tmp/rows") == "Terminal"* ]] ||
  fail "a row with no icon has no gap in front of it" \
    "got: $(printf '%q' "$(head -1 "$test_tmp/rows")")"
pass "a row with no icon has no gap in front of it"

FUZZEL_PICK=2 answer=$(printf 'one\ntwo\nthree\n' | select_from Pick)
[[ $answer == three ]] || fail "options may arrive on stdin" "got: $answer"
pass "options may arrive on stdin"

# Every caller treats "nothing picked" as "do nothing".
FUZZEL_PICK="" answer=$(select_from Format jpg png)
status=$?
(( status != 0 )) || fail "a dismissed menu is not a selection" "exited 0 with: $answer"
[[ -z $answer ]] || fail "a dismissed menu returns nothing" "got: $answer"
pass "a dismissed menu is not a selection"

# Callers size in pixels, fuzzel in characters and rows. The conversion is
# approximate on purpose, so this pins that the numbers are scaled, not dropped.
FUZZEL_PICK=0 select_from Keybindings a b -- --width 800 --height 500 >/dev/null
[[ $(menu_args) == *"--width 100"* ]] ||
  fail "a pixel width becomes a column count" "$(menu_args)"
[[ $(menu_args) == *"--lines 20"* ]] ||
  fail "a pixel height becomes a row count" "$(menu_args)"
pass "a pixel size is converted to fuzzel's columns and rows"

# A menu narrower than its own prompt, or taller than the screen, helps nobody.
FUZZEL_PICK=0 select_from Tiny a -- --width 8 --height 20 >/dev/null
[[ $(menu_args) == *"--width 20"* && $(menu_args) == *"--lines 3"* ]] ||
  fail "an unusable size is clamped" "$(menu_args)"
pass "an unusable size is clamped"

output=$(select_from 2>&1)
(( $? != 0 )) || fail "a menu with no prompt is a usage error"
[[ $output == *"Usage:"* ]] || fail "a menu with no prompt says how to call it" "$output"

output=$(select_from Prompt </dev/null 2>&1)
(( $? != 0 )) || fail "a menu with no options is a usage error"
pass "a menu with no prompt or no options is a usage error"
