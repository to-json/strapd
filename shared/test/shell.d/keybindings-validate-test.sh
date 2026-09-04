#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command yq
require_command jq

source "$ROOT/keybindings/lib/toml-read.sh"
source "$ROOT/keybindings/lib/repeat-expand.sh"
source "$ROOT/keybindings/lib/validate.sh"

FIXTURES="$ROOT/test/shell.d/fixtures/keybindings"

# minimal.toml is the baseline: zero violations, exit 0, and the input JSON
# comes back out unchanged (the passthrough convention validate_actions
# documents for chaining).
json=$(expand_repeats "$(toml_to_json "$FIXTURES/minimal.toml")")

status=0
out=$(validate_actions "$json" niri) || status=$?
(( status == 0 )) || fail "minimal.toml passes validation" "exited $status"
pass "minimal.toml passes validation"

[[ $(jq -c . <<<"$out") == "$(jq -c . <<<"$json")" ]] || fail "minimal.toml validation passes the input JSON through unchanged" "got $out"
pass "minimal.toml validation passes the input JSON through unchanged"

# Each invalid-*.toml fixture is a single-rule violation; assert both that
# validation fails AND that it attributes the failure to the correct rule,
# so a validator that fails for the wrong reason would still be caught.
assert_fixture_fails() {
  local fixture="$1"
  local expected_rule="$2"

  local json
  json=$(expand_repeats "$(toml_to_json "$FIXTURES/$fixture")")

  local status=0
  local err
  err=$(validate_actions "$json" niri 2>&1 >/dev/null) || status=$?

  (( status != 0 )) || fail "$fixture fails validation" "exited 0, printed: $err"
  pass "$fixture fails validation"

  [[ $err == *"rule=$expected_rule"* ]] || fail "$fixture is attributed to $expected_rule" "got: $err"
  pass "$fixture is attributed to $expected_rule"
}

assert_fixture_fails "invalid-duplicate-id.toml" "rule1-duplicate-id"
assert_fixture_fails "invalid-duplicate-id-after-repeat.toml" "rule1-duplicate-id"
assert_fixture_fails "invalid-missing-backend-table.toml" "rule2-missing-backend-table"
assert_fixture_fails "invalid-both-dispatch-and-unsupported.toml" "rule3-dispatch-and-unsupported"
assert_fixture_fails "invalid-neither-dispatch-nor-unsupported.toml" "rule3-neither-dispatch-nor-unsupported"
assert_fixture_fails "invalid-unsupported-no-reason.toml" "rule4-unsupported-missing-reason"
