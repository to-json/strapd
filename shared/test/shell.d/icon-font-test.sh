#!/bin/bash
#
# The icon font carries strapd's marks under strapd's name. It is the one file
# in the tree neither rename pass could read: both were substitutions over text
# and path names, and what a .ttf calls itself lives in a table inside it.
#
# The family name is not decoration: a menu entry names the font it wants as
# `"iconFont":"strapd"`, matched against what is inside the file.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

FONT="$ROOT/default/fonts/strapd/strapd.ttf"
README="$ROOT/default/fonts/strapd/README.md"
font_tool=("$ROOT/bin/strapd-dev-font" --font "$FONT")

[[ -f $FONT ]] || fail "the icon font is shipped" "no $FONT"
pass "the icon font is shipped"

family=$("${font_tool[@]}" family) || fail "the font reports a family name"
[[ $family == strapd ]] ||
  fail "the font's family is what a menu entry asks for" \
       "menu entries say \"iconFont\":\"strapd\"; the font calls itself \"$family\""
pass "the font's family is what a menu entry asks for"

mapfile -t glyphs < <("${font_tool[@]}" list)

(( ${#glyphs[@]} > 0 )) || fail "the font carries marks" "strapd dev font list printed nothing"
pass "the font carries marks"

# Every mapping is a private-use one. Fontello maps the letters of the font's
# own name to blank glyphs as a side effect of generating it, which is how seven
# empty ASCII letters ended up advertised here -- a font claiming to cover `a`
# and drawing nothing is invisible text wherever fontconfig reaches for it.
outside=()
for line in "${glyphs[@]}"; do
  codepoint=${line%% *}
  [[ $codepoint == U+E9?? ]] || outside+=("$codepoint")
done

(( ${#outside[@]} == 0 )) ||
  fail "the font maps nothing outside its private-use range" "$(printf '  %s\n' "${outside[@]}")"
pass "the font maps nothing outside its private-use range"

# A mark whose source nobody wrote down is one nobody can re-trace or
# re-license.
undocumented=() unshipped=()
for line in "${glyphs[@]}"; do
  codepoint=${line%% *}
  grep -q "^- \`$codepoint\`" "$README" || undocumented+=("$codepoint")
done
while read -r codepoint; do
  printf '%s\n' "${glyphs[@]}" | grep -q "^$codepoint " || unshipped+=("$codepoint")
done < <(grep -o '^- `U+[0-9A-F]*`' "$README" | tr -d '`-' | tr -d ' ')

(( ${#undocumented[@]} == 0 )) ||
  fail "every mark in the font has its source written down" "$(printf '  %s\n' "${undocumented[@]}")"
pass "every mark in the font has its source written down"

(( ${#unshipped[@]} == 0 )) ||
  fail "every mark the README lists is in the font" "$(printf '  %s\n' "${unshipped[@]}")"
pass "every mark the README lists is in the font"
