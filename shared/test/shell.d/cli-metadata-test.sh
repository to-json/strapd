#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# `strapd commands --check` validates that every binary in bin/ carries the
# metadata the dispatcher routes on, and that no two commands claim the same
# route. It is the one check that sees the whole ported tree at once: a script
# that came over without a summary, or a rename that collided two routes, shows
# up here and nowhere else.
output=$(STRAPD_PATH="$ROOT" PATH="$ROOT/bin:$PATH" "$ROOT/bin/strapd" commands --check 2>&1) ||
  fail "every command in bin/ has valid metadata and a unique route" "$output"
pass "every command in bin/ has valid metadata and a unique route"
