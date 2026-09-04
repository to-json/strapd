#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command yq
require_command jq

GENERATE="$ROOT/bin/strapd-keybindings-generate"
ACTIONS="$ROOT/keybindings/actions.toml"

# The generator resolves its lib/ through STRAPD_PATH, which defaults to the
# installed tree. Point it at this checkout, or the test exercises whatever is
# installed on the machine running it -- which on an installed system happens to
# be the same tree, so leaving it unset passed there and nowhere else.
export STRAPD_PATH="$ROOT"

[[ -f $ACTIONS ]] || fail "keybindings/actions.toml exists" "not found at $ACTIONS"
pass "keybindings/actions.toml exists"

# Regression guard: the real, shipped content file must always generate clean
# niri KDL through the real entrypoint, exactly as a user would invoke it.
status=0
kdl=$("$GENERATE" "$ACTIONS" --backend niri) || status=$?
(( status == 0 )) || fail "actions.toml --backend niri succeeds" "exited $status"
pass "actions.toml --backend niri succeeds"

[[ $kdl == *"binds {"* ]] || fail "output contains a binds { header" "got: $kdl"
pass "output contains a binds { header"

[[ $kdl == *$'\n}'* ]] || fail "output closes the binds block" "got: $kdl"
pass "output closes the binds block"

# A representative dispatch and a representative unsupported comment, so this
# catches either a rendering regression or the file losing its
# unsupported-with-reason content entirely.
[[ $kdl == *"Mod+W { close-window; }"* ]] || fail "window.close renders as Mod+W { close-window; }" "got: $kdl"
pass "window.close renders as Mod+W { close-window; }"

[[ $kdl == *"layout.toggle_split: unsupported"* ]] || fail "layout.toggle_split is mentioned as unsupported" "got: $kdl"
pass "layout.toggle_split is mentioned as unsupported"

# Same file, one backend over. Rule 2 of the schema makes a missing sway table a
# validation error rather than a silently dropped bind, so this run is what keeps
# a newly added action from shipping niri-only.
status=0
swaycfg=$("$GENERATE" "$ACTIONS" --backend sway) || status=$?
(( status == 0 )) || fail "actions.toml --backend sway succeeds" "exited $status"
pass "actions.toml --backend sway succeeds"

[[ $swaycfg == "set \$mod Mod4"* ]] || fail "output opens by defining \$mod" "got: $swaycfg"
pass "output opens by defining \$mod"

[[ $swaycfg == *"bindsym \$mod+w kill"* ]] || fail "window.close renders as bindsym \$mod+w kill" "got: $swaycfg"
pass "window.close renders as bindsym \$mod+w kill"

# The two backends disagree, and the file records it in both directions: niri
# cannot express a split toggle, sway cannot express the workspace overview. A
# pass that lost either table would still produce plausible output.
[[ $swaycfg == *"bindsym \$mod+Control+j layout toggle split"* ]] || fail "layout.toggle_split renders for sway, which niri marks unsupported" "got: $swaycfg"
pass "layout.toggle_split renders for sway, which niri marks unsupported"

[[ $swaycfg == *"# layout.toggle_overview: unsupported"* ]] || fail "layout.toggle_overview is mentioned as unsupported for sway" "got: $swaycfg"
pass "layout.toggle_overview is mentioned as unsupported for sway"

status=0
mangocfg=$("$GENERATE" "$ACTIONS" --backend mango) || status=$?
(( status == 0 )) || fail "actions.toml --backend mango succeeds" "exited $status"
pass "actions.toml --backend mango succeeds"

[[ $mangocfg == *"bind=SUPER,w,killclient"* ]] || fail "window.close renders as bind=SUPER,w,killclient" "got: $mangocfg"
pass "window.close renders as bind=SUPER,w,killclient"

# Mango has nine tags, so the tenth workspace is the one action the other two
# bind and this one cannot -- and the one easiest to fake with a bind nothing
# reaches.
[[ $mangocfg == *"bind=SUPER,9,view,9,0"* ]] || fail "workspace 9 binds for mango" "got: $mangocfg"
pass "workspace 9 binds for mango"

[[ $mangocfg == *"# workspace.focus.10: unsupported"* ]] || fail "workspace 10 is mentioned as unsupported for mango" "got: $mangocfg"
pass "workspace 10 is mentioned as unsupported for mango"

[[ $mangocfg == *"bind=SUPER,o,toggleoverview"* ]] || fail "layout.toggle_overview renders for mango, which sway marks unsupported" "got: $mangocfg"
pass "layout.toggle_overview renders for mango, which sway marks unsupported"
