#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command yq
require_command jq

source "$ROOT/keybindings/lib/toml-read.sh"
source "$ROOT/keybindings/lib/repeat-expand.sh"
source "$ROOT/keybindings/lib/validate.sh"
source "$ROOT/keybindings/lib/render-mango.sh"

FIXTURES="$ROOT/test/shell.d/fixtures/keybindings"

# Full chain: toml -> json -> expanded -> validated -> rendered, exactly as a
# real caller would run it.
json=$(toml_to_json "$FIXTURES/minimal.toml")
json=$(expand_repeats "$json")
json=$(validate_actions "$json" mango)

status=0
config=$(render_mango "$json") || status=$?
(( status == 0 )) || fail "minimal.toml renders to a mango config" "exited $status"
pass "minimal.toml renders to a mango config"

# Mango's line is bind=<MODS>,<KEY>,<dispatcher>: the modifiers are joined
# with +, and the comma is what separates them from the key.
[[ $config == *"bind=SUPER,w,killclient"* ]] || fail "window.close renders as bind=SUPER,w,killclient" "got: $config"
pass "window.close renders as bind=SUPER,w,killclient"

# Letters are lowercased on the way out: mango takes key names from xev/wev,
# where `W` is a different keysym from `w`.
[[ $config != *"bind=SUPER,W,"* ]] || fail "single-letter keys are lowercased for mango" "got: $config"
pass "single-letter keys are lowercased for mango"

# A dispatch that carries its own arguments passes through with its commas
# intact: they are mango's argument separator, not something this renderer
# splits on.
for n in 1 2 3; do
  [[ $config == *"bind=SUPER,$n,view,$n,0"* ]] || fail "workspace.focus.$n renders as bind=SUPER,$n,view,$n,0" "got: $config"
  pass "workspace.focus.$n renders as bind=SUPER,$n,view,$n,0"
done

# The three backends disagree in three different directions on these two
# actions, which is the reason each carries its own table.
[[ $config == *"# layout.toggle_split: unsupported - Mango switches whole named layouts"* ]] || fail "unsupported layout.toggle_split becomes a comment naming the reason" "got: $config"
pass "unsupported layout.toggle_split becomes a comment naming the reason"

[[ $config == *"bind=SUPER,o,toggleoverview"* ]] || fail "layout.toggle_overview renders for mango, which sway marks unsupported" "got: $config"
pass "layout.toggle_overview renders for mango, which sway marks unsupported"

# No bind line for the unsupported action -- only the "# ...: unsupported - ..."
# comment should mention it.
bind_lines_mentioning_unsupported=$(grep '^bind=' <<<"$config" | grep -c 'toggle_split' || true)
(( bind_lines_mentioning_unsupported == 0 )) || fail "no malformed bind line was emitted for layout.toggle_split" "got: $config"
pass "no malformed bind line was emitted for layout.toggle_split"

# Mango spells its modifiers the canonical way, so the translation is an
# identity map. It still has to be a map: an unrecognized token must fail rather
# than reach mango's parser as a key name.
mods_json='{"action":[{"id":"mods.check","category":"utilities","description":"Mods","key":"SUPER+SHIFT+ALT+CTRL+X","mango":{"dispatch":"killclient"}}]}'
mods=$(render_mango "$mods_json")
[[ $mods == *"bind=SUPER+SHIFT+ALT+CTRL,x,killclient"* ]] || fail "modifiers join with + and separate from the key with a comma" "got: $mods"
pass "modifiers join with + and separate from the key with a comma"

bad_json='{"action":[{"id":"bogus.action","category":"utilities","description":"Bogus","key":"HYPER+Q","mango":{"dispatch":"killclient"}}]}'
status=0
err=$(render_mango "$bad_json" 2>&1 >/dev/null) || status=$?
(( status != 0 )) || fail "unrecognized modifier token fails loudly" "exited 0, printed: $err"
pass "unrecognized modifier token fails loudly"

[[ $err == *"bogus.action"* ]] || fail "unrecognized-modifier error names the action id" "got: $err"
pass "unrecognized-modifier error names the action id"

[[ $err == *"HYPER"* ]] || fail "unrecognized-modifier error names the bad token" "got: $err"
pass "unrecognized-modifier error names the bad token"
