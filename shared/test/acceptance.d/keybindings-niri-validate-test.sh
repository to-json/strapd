#!/bin/bash
#
# Feeds the generated Niri keybindings to niri itself. The renderer's own test is
# a golden-file test: it proves the KDL is what *we wrote down*, which says
# nothing about whether niri accepts it. Every key and dispatch name in
# actions.toml is otherwise an unchecked assertion about niri's grammar.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require niri jq yq

WORK="$ARTIFACTS/keybindings-niri-validate"
rm -rf "$WORK"
mkdir -p "$WORK"

# `niri validate` wants a whole config file, not a fragment. Every other
# top-level section has a default, so the generated binds block alone is
# complete -- which keeps this test scoped to the binds.
generated="$WORK/binds.kdl"
if ! STRAPD_PATH="$ROOT" bash "$ROOT/bin/strapd-keybindings-generate" \
       "$ROOT/keybindings/actions.toml" --backend niri > "$generated" 2> "$WORK/generate.err"; then
  fail "generator produces a config for keybindings/actions.toml" "$(cat "$WORK/generate.err")"
fi
pass "generator produces a config for keybindings/actions.toml"

if ! niri validate -c "$generated" > "$WORK/validate.out" 2>&1; then
  fail "niri accepts the generated keybindings" \
       "$(cat "$WORK/validate.out")
generated config saved at $generated"
fi
pass "niri accepts the generated keybindings"
