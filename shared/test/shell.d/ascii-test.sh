#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"

columns() {
  awk 'NR == 1 { print length($0) }'
}

# The wordmark FIGlet itself draws for this font, so a change to the embedded
# font or to the kerning shows up here rather than in someone's terminal.
expected=$(
  cat <<'WORDMARK'
   ▄████████     ███        ▄████████    ▄████████    ▄███████▄ ████████▄
  ███    ███ ▀█████████▄   ███    ███   ███    ███   ███    ███ ███   ▀███
  ███    █▀     ▀███▀▀██   ███    ███   ███    ███   ███    ███ ███    ███
  ███            ███   ▀  ▄███▄▄▄▄██▀   ███    ███   ███    ███ ███    ███
▀███████████     ███     ▀▀███▀▀▀▀▀   ▀███████████ ▀█████████▀  ███    ███
         ███     ███     ▀███████████   ███    ███   ███        ███    ███
   ▄█    ███     ███       ███    ███   ███    ███   ███        ███   ▄███
 ▄████████▀     ▄████▀     ███    ███   ███    █▀   ▄████▀      ████████▀
                           ███    ███
WORDMARK
)

output=$(strapd-ascii strapd)
[[ $output == "$expected" ]] || fail "the wordmark matches the reference rendering" "expected:
$expected
actual:
$output"
pass "the wordmark matches the reference rendering"

# figlet.js and figlet.c disagree about a first M: the C one trims the column of
# blanks every row of that glyph shares, the JavaScript one keeps it. asciiart.eu
# runs figlet.js, so this pins the leading blanks.
expected_m=$(
  cat <<'LETTER_M'
   ▄▄▄▄███▄▄▄▄
 ▄██▀▀▀███▀▀▀██▄
 ███   ███   ███
 ███   ███   ███
 ███   ███   ███
 ███   ███   ███
 ███   ███   ███
  ▀█   ███   █▀

LETTER_M
)

output=$(strapd-ascii M)
[[ $output == "$expected_m" ]] || fail "a leading M keeps the blanks figlet.js gives it" "expected:
$expected_m
actual:
$output"
pass "a leading M keeps the blanks figlet.js gives it"

output=$(printf 'strapd' | strapd-ascii)
[[ $output == "$expected" ]] || fail "text can arrive on stdin"
pass "text can arrive on stdin"

# The route dispatches on whether the metadata says an argument is required, so
# a piped run has to be exercised through `strapd` itself.
output=$(printf 'strapd' | strapd ascii)
[[ $output == "$expected" ]] || fail "piped text renders through the strapd route" "got:
$output"
pass "piped text renders through the strapd route"

# The block characters are three bytes each, so the column arithmetic has to
# count columns rather than bytes wherever the locale lands.
output=$(LC_ALL=C strapd-ascii strapd)
[[ $output == "$expected" ]] || fail "a byte-only locale draws the same wordmark"
pass "a byte-only locale draws the same wordmark"

blanks=$(strapd-ascii strapd | grep -c ' $' || true)
[[ $blanks == "0" ]] || fail "no line is padded with trailing blanks" "$blanks lines end in a blank"
pass "no line is padded with trailing blanks"

# The space is a glyph of five hardblank columns, so it is worth exactly five
# columns of art, not merely more than none.
tight=$(strapd-ascii "Hi" | columns)
spaced=$(strapd-ascii "H i" | columns)
(( tight == 18 )) || fail "Hi is 18 columns wide" "got $tight"
(( spaced == tight + 5 )) || fail "a space between words is five columns" "expected $((tight + 5)), got $spaced"
pass "a space between words is five columns"

rows=$(strapd-ascii Hi | wc -l)
(( rows == 9 )) || fail "a block is nine rows" "got $rows"
pass "a block is nine rows"

# An empty line is a block of its own in figlet, and dropping it would silently
# close up the gap someone put there on purpose.
rows=$(printf 'A\n\nB\n' | strapd-ascii | wc -l)
(( rows == 27 )) || fail "an empty line still draws its block" "expected 27 rows, got $rows"
pass "an empty line still draws its block"

# awk reads escapes in a variable given on its command line, so text has to
# reach it as input instead: a backslash is a character the font lacks.
rows=$(strapd-ascii 'A\nB' 2>/dev/null | wc -l)
(( rows == 9 )) || fail "a backslash in the text is not an escape" "expected 9 rows, got $rows"
pass "a backslash in the text is not an escape"

# Delta Corps Priest 1 carries letters and spaces only. Dropping the rest in
# silence would leave a version number looking like a renderer bug.
status=0
warning=$(strapd-ascii "strapd 4.0" 2>&1 >/dev/null) || status=$?
(( status == 0 )) || fail "text with unusable characters still draws" "exited $status"
[[ $warning == *"Skipped"* && $warning == *"4"* && $warning == *"."* && $warning == *"0"* ]] ||
  fail "skipped characters are named on stderr" "got: $warning"
pass "skipped characters are named on stderr"

output=$(strapd-ascii "strapd 4.0" 2>/dev/null)
[[ $output == "$expected" ]] || fail "the drawable characters still render"
pass "the drawable characters still render"

# Naming a skipped control character by writing it out would send it to the
# terminal as a control character.
warning=$(printf 'A\001B\n' | strapd-ascii 2>&1 >/dev/null)
[[ $warning == *'\x01'* ]] || fail "a skipped control character is named by code" "got: $warning"
[[ $warning != *$'\001'* ]] || fail "a skipped control character is not written out raw"
pass "a skipped control character is named by code"

status=0
output=$(strapd-ascii "4.0" 2>/dev/null) || status=$?
(( status == 1 )) || fail "text the font cannot draw at all fails" "exited $status"
[[ -z $output ]] || fail "text the font cannot draw at all prints nothing"
pass "text the font cannot draw at all fails"

# A mistyped option would otherwise be drawn as art, silently.
status=0
output=$(strapd-ascii --width 40 2>&1 >/dev/null) || status=$?
(( status == 1 )) || fail "an unknown option is refused" "exited $status"
[[ $output == *"Unknown option: --width"* ]] || fail "an unknown option is named" "got: $output"
pass "an unknown option is refused"

output=$(strapd-ascii -- Hi | columns)
(( output == 18 )) || fail "text after -- is still text" "got $output columns"
pass "text after -- is still text"

output=$(strapd-ascii --help)
[[ $output == *"Usage: strapd-ascii"* ]] || fail "help renders"
pass "help renders"
