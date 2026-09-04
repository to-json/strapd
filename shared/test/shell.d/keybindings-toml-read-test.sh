#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command yq
require_command jq

source "$ROOT/keybindings/lib/toml-read.sh"

FIXTURES="$ROOT/test/shell.d/fixtures/keybindings"

json=$(toml_to_json "$FIXTURES/minimal.toml")

count=$(jq '.action | length' <<<"$json")
(( count == 4 )) || fail "minimal.toml has 4 actions" "got $count"
pass "minimal.toml has 4 actions"

# Selected by id rather than by position: the fixture grows an action
# whenever a new backend needs one, and an index would silently start reading
# a different action's table instead of failing.
repeat_range=$(jq -c '.action[] | select(.id == "workspace.focus.{n}") | .repeat.range' <<<"$json")
[[ $repeat_range == "[1,3]" ]] || fail "the repeat action's range comes through as [1, 3]" "got $repeat_range"
pass "the repeat action's range comes through as [1, 3]"

# yq keeps a table with nothing under it as an empty JSON object rather than
# omitting the key, so a validator can tell "table present but empty" from
# "table absent" by checking `has("niri")` rather than `niri == {}`.
json=$(toml_to_json "$FIXTURES/invalid-neither-dispatch-nor-unsupported.toml")

has_niri=$(jq '.action[0] | has("niri")' <<<"$json")
[[ $has_niri == "true" ]] || fail "an empty [action.niri] table is still present as a key" "got has(niri): $has_niri"
pass "an empty [action.niri] table is still present as a key"

niri_table=$(jq -c '.action[0].niri' <<<"$json")
[[ $niri_table == "{}" ]] || fail "an empty [action.niri] table converts to an empty object" "got $niri_table"
pass "an empty [action.niri] table converts to an empty object"

status=0
output=$(toml_to_json "$FIXTURES/does-not-exist.toml" 2>&1) || status=$?
(( status != 0 )) || fail "a missing file is refused" "exited 0, printed: $output"
pass "a missing file is refused"

status=0
malformed=$(mktemp)
printf 'this is [not valid toml\n' >"$malformed"
output=$(toml_to_json "$malformed" 2>&1) || status=$?
rm -f "$malformed"
(( status != 0 )) || fail "malformed TOML is refused" "exited 0, printed: $output"
pass "malformed TOML is refused"
