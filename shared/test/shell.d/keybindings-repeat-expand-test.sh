#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command yq
require_command jq

source "$ROOT/keybindings/lib/toml-read.sh"
source "$ROOT/keybindings/lib/repeat-expand.sh"

FIXTURES="$ROOT/test/shell.d/fixtures/keybindings"

raw=$(toml_to_json "$FIXTURES/minimal.toml")
json=$(expand_repeats "$raw")

count=$(jq '.action | length' <<<"$json")
(( count == 6 )) || fail "minimal.toml expands to 6 actions" "got $count"
pass "minimal.toml expands to 6 actions"

ids=$(jq -c '[.action[].id]' <<<"$json")
expected_ids='["window.close","layout.toggle_split","layout.toggle_overview","workspace.focus.1","workspace.focus.2","workspace.focus.3"]'
[[ $ids == "$expected_ids" ]] || fail "expanded ids are the three literal actions followed by workspace.focus.1..3" "got $ids"
pass "expanded ids are the three literal actions followed by workspace.focus.1..3"

for n in 1 2 3; do
  action=$(jq -c --arg n "$n" '.action[] | select(.id == "workspace.focus." + $n)' <<<"$json")
  [[ -n $action ]] || fail "workspace.focus.$n exists" "got nothing"

  dispatch=$(jq -r '.niri.dispatch' <<<"$action")
  [[ $dispatch == "focus-workspace $n" ]] || fail "workspace.focus.$n dispatch substitutes {n}" "got $dispatch"
  pass "workspace.focus.$n dispatch substitutes {n}"

  description=$(jq -r '.description' <<<"$action")
  [[ $description == "Switch to workspace $n" ]] || fail "workspace.focus.$n description substitutes {n}" "got $description"
  pass "workspace.focus.$n description substitutes {n}"

  key=$(jq -r '.key' <<<"$action")
  [[ $key == "SUPER+$n" ]] || fail "workspace.focus.$n key substitutes {n}" "got $key"
  pass "workspace.focus.$n key substitutes {n}"

  has_repeat=$(jq 'has("repeat")' <<<"$action")
  [[ $has_repeat == "false" ]] || fail "workspace.focus.$n has no leftover repeat field" "got has(repeat): $has_repeat"
  pass "workspace.focus.$n has no leftover repeat field"
done

# An action with no repeat table comes out byte-identical. Compared against the
# input rather than a literal copied out of it: the fixture grows a table every
# time a backend is added.
for id in window.close layout.toggle_split; do
  before=$(jq -c --arg id "$id" '.action[] | select(.id == $id)' <<<"$raw")
  after=$(jq -c --arg id "$id" '.action[] | select(.id == $id)' <<<"$json")
  [[ $after == "$before" ]] || fail "$id passes through expansion unchanged" "before: $before
after:  $after"
  pass "$id passes through expansion unchanged"
done

# layout.toggle_split is the unsupported-with-reason case, so the loop above
# also covers a backend table carrying unsupported/reason surviving intact.
has_unsupported=$(jq -c '.action[] | select(.id == "layout.toggle_split") | .niri.unsupported' <<<"$json")
[[ $has_unsupported == "true" ]] || fail "an unsupported/reason table survives expansion" "got $has_unsupported"
pass "an unsupported/reason table survives expansion"

status=0
dup_json=$(expand_repeats "$(toml_to_json "$FIXTURES/invalid-duplicate-id-after-repeat.toml")") || status=$?
(( status == 0 )) || fail "expansion succeeds on invalid-duplicate-id-after-repeat.toml" "exited $status"
pass "expansion succeeds on invalid-duplicate-id-after-repeat.toml"

# The fixture's repeat block (range [1,3]) and its separate literal action both
# contribute a workspace.focus.2. Expansion does not dedupe or reject that;
# uniqueness is the next unit's job.
dup_count=$(jq '[.action[] | select(.id == "workspace.focus.2")] | length' <<<"$dup_json")
(( dup_count == 2 )) || fail "workspace.focus.2 appears twice (1 from repeat + 1 literal), uniqueness not enforced here" "got $dup_count"
pass "workspace.focus.2 appears twice (1 from repeat + 1 literal), uniqueness not enforced here"
