#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command yq
require_command jq

source "$ROOT/keybindings/lib/toml-read.sh"
source "$ROOT/keybindings/lib/repeat-expand.sh"
source "$ROOT/keybindings/lib/validate.sh"
source "$ROOT/keybindings/lib/render-niri.sh"

FIXTURES="$ROOT/test/shell.d/fixtures/keybindings"

# Full chain: toml -> json -> expanded -> validated -> rendered, exactly as a
# real caller would run it.
json=$(toml_to_json "$FIXTURES/minimal.toml")
json=$(expand_repeats "$json")
json=$(validate_actions "$json" niri)

status=0
kdl=$(render_niri "$json") || status=$?
(( status == 0 )) || fail "minimal.toml renders to niri KDL" "exited $status"
pass "minimal.toml renders to niri KDL"

[[ $kdl == *"binds {"* ]] || fail "output contains a binds { header" "got: $kdl"
pass "output contains a binds { header"

[[ $kdl == *$'\n}'* ]] || fail "output closes the binds block" "got: $kdl"
pass "output closes the binds block"

[[ $kdl == *"Mod+W { close-window; }"* ]] || fail "window.close renders as Mod+W { close-window; }" "got: $kdl"
pass "window.close renders as Mod+W { close-window; }"

for n in 1 2 3; do
  [[ $kdl == *"Mod+$n { focus-workspace $n; }"* ]] || fail "workspace.focus.$n renders as Mod+$n { focus-workspace $n; }" "got: $kdl"
  pass "workspace.focus.$n renders as Mod+$n { focus-workspace $n; }"
done

[[ $kdl == *"layout.toggle_split"* ]] || fail "unsupported layout.toggle_split is mentioned in a comment" "got: $kdl"
pass "unsupported layout.toggle_split is mentioned in a comment"

[[ $kdl == *"Scrolling-tiling model has no manual split-direction concept"* ]] || fail "unsupported comment includes the reason" "got: $kdl"
pass "unsupported comment includes the reason"

# No bind line for the unsupported action -- only the "// ...: unsupported -
# ..." comment should mention it.
bind_lines_mentioning_unsupported=$(grep '{ .*; }' <<<"$kdl" | grep -c 'toggle_split' || true)
(( bind_lines_mentioning_unsupported == 0 )) || fail "no malformed bind line was emitted for layout.toggle_split" "got: $kdl"
pass "no malformed bind line was emitted for layout.toggle_split"

# Plausibly-balanced KDL: no real parser available in this sandbox, so check
# brace balance as a text-based sanity check instead.
open_braces=$(grep -o '{' <<<"$kdl" | wc -l)
close_braces=$(grep -o '}' <<<"$kdl" | wc -l)
(( open_braces == close_braces )) || fail "output has balanced braces" "got $open_braces open, $close_braces close"
pass "output has balanced braces"

# SUPER -> Mod: no canonical token leaks through untranslated.
[[ $kdl != *"SUPER"* ]] || fail "no untranslated SUPER token leaks into rendered output" "got: $kdl"
pass "no untranslated SUPER token leaks into rendered output"

# An unrecognized modifier token must fail loudly, not pass through or get
# dropped. Built directly in JSON, bypassing the toml/expand/validate stages,
# since this exercises render_niri's own translation.
bad_json='{"action":[{"id":"bogus.action","category":"utilities","description":"Bogus","key":"HYPER+Q","niri":{"dispatch":"noop"}}]}'
status=0
err=$(render_niri "$bad_json" 2>&1 >/dev/null) || status=$?
(( status != 0 )) || fail "unrecognized modifier token fails loudly" "exited 0, printed: $err"
pass "unrecognized modifier token fails loudly"

[[ $err == *"bogus.action"* ]] || fail "unrecognized-modifier error names the action id" "got: $err"
pass "unrecognized-modifier error names the action id"

[[ $err == *"HYPER"* ]] || fail "unrecognized-modifier error names the bad token" "got: $err"
pass "unrecognized-modifier error names the bad token"
