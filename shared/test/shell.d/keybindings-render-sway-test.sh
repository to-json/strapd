#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command yq
require_command jq

source "$ROOT/keybindings/lib/toml-read.sh"
source "$ROOT/keybindings/lib/repeat-expand.sh"
source "$ROOT/keybindings/lib/validate.sh"
source "$ROOT/keybindings/lib/render-sway.sh"

FIXTURES="$ROOT/test/shell.d/fixtures/keybindings"

# Full chain: toml -> json -> expanded -> validated -> rendered, exactly as a
# real caller would run it.
json=$(toml_to_json "$FIXTURES/minimal.toml")
json=$(expand_repeats "$json")
json=$(validate_actions "$json" sway)

status=0
config=$(render_sway "$json") || status=$?
(( status == 0 )) || fail "minimal.toml renders to a sway config" "exited $status"
pass "minimal.toml renders to a sway config"

# The output stands on its own: it defines the $mod it then binds against,
# rather than depending on an enclosing config having set it first.
[[ $config == "set \$mod Mod4"* ]] || fail "output opens by defining \$mod" "got: $config"
pass "output opens by defining \$mod"

[[ $config == *"bindsym \$mod+w kill"* ]] || fail "window.close renders as bindsym \$mod+w kill" "got: $config"
pass "window.close renders as bindsym \$mod+w kill"

# Letters are lowercased on the way out: sway binds on X keysym names, where
# `W` is the shifted keysym and would bind Super+Shift+w instead.
[[ $config != *"bindsym \$mod+W "* ]] || fail "single-letter keys are lowercased for sway" "got: $config"
pass "single-letter keys are lowercased for sway"

for n in 1 2 3; do
  [[ $config == *"bindsym \$mod+$n workspace number $n"* ]] || fail "workspace.focus.$n renders as bindsym \$mod+$n workspace number $n" "got: $config"
  pass "workspace.focus.$n renders as bindsym \$mod+$n workspace number $n"
done

# An action niri cannot express but sway can, and the reverse: the point of
# per-backend tables is that the files disagree where the compositors do.
[[ $config == *"bindsym \$mod+j layout toggle split"* ]] || fail "layout.toggle_split renders for sway even though niri marks it unsupported" "got: $config"
pass "layout.toggle_split renders for sway even though niri marks it unsupported"

[[ $config == *"# layout.toggle_overview: unsupported - Sway has no built-in workspace overview"* ]] || fail "unsupported layout.toggle_overview becomes a comment naming the reason" "got: $config"
pass "unsupported layout.toggle_overview becomes a comment naming the reason"

# No bindsym line for the unsupported action -- only the "# ...: unsupported -
# ..." comment should mention it.
bind_lines_mentioning_unsupported=$(grep '^bindsym ' <<<"$config" | grep -c 'toggle_overview' || true)
(( bind_lines_mentioning_unsupported == 0 )) || fail "no malformed bindsym line was emitted for layout.toggle_overview" "got: $config"
pass "no malformed bindsym line was emitted for layout.toggle_overview"

# Modifier-token translation happens: canonical SUPER/CTRL/ALT tokens never
# leak through untranslated into the rendered binds.
[[ $config != *"SUPER"* ]] || fail "no untranslated SUPER token leaks into rendered output" "got: $config"
pass "no untranslated SUPER token leaks into rendered output"

# Modifier translation, checked directly rather than through a fixture: sway
# spells Alt as Mod1 and Ctrl as Control.
mods_json='{"action":[{"id":"mods.check","category":"utilities","description":"Mods","key":"SUPER+SHIFT+ALT+CTRL+X","sway":{"dispatch":"nop"}}]}'
mods=$(render_sway "$mods_json")
[[ $mods == *"bindsym \$mod+Shift+Mod1+Control+x nop"* ]] || fail "SHIFT/ALT/CTRL translate to Shift/Mod1/Control" "got: $mods"
pass "SHIFT/ALT/CTRL translate to Shift/Mod1/Control"

# An unrecognized modifier token must fail loudly, not pass through silently
# or get dropped.
bad_json='{"action":[{"id":"bogus.action","category":"utilities","description":"Bogus","key":"HYPER+Q","sway":{"dispatch":"nop"}}]}'
status=0
err=$(render_sway "$bad_json" 2>&1 >/dev/null) || status=$?
(( status != 0 )) || fail "unrecognized modifier token fails loudly" "exited 0, printed: $err"
pass "unrecognized modifier token fails loudly"

[[ $err == *"bogus.action"* ]] || fail "unrecognized-modifier error names the action id" "got: $err"
pass "unrecognized-modifier error names the action id"

[[ $err == *"HYPER"* ]] || fail "unrecognized-modifier error names the bad token" "got: $err"
pass "unrecognized-modifier error names the bad token"
