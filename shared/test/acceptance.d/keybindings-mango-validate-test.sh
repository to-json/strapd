#!/bin/bash
#
# Feeds the generated MangoWC keybindings to mango itself. The renderer's own
# test is a golden-file test: it proves the output is what *we wrote down*,
# which says nothing about whether mango accepts it. Every key and dispatcher
# name in the [action.mango] tables is otherwise an unchecked assertion about
# mango's grammar. `mango -p` reports both and exits non-zero if it found either.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require mango jq yq

WORK="$ARTIFACTS/keybindings-mango-validate"
rm -rf "$WORK"
mkdir -p "$WORK"

# Mango's config has no required sections, so the generated binds alone are a
# complete, valid config, which keeps this test scoped to the binds.
generated="$WORK/binds.conf"
if ! STRAPD_PATH="$ROOT" bash "$ROOT/bin/strapd-keybindings-generate" \
       "$ROOT/keybindings/actions.toml" --backend mango > "$generated" 2> "$WORK/generate.err"; then
  fail "generator produces a config for keybindings/actions.toml" "$(cat "$WORK/generate.err")"
fi
pass "generator produces a config for keybindings/actions.toml"

# -c has to come before -p. Mango resolves the config path while parsing
# arguments in order, so `-p -c <file>` runs the check against the system
# default and never opens the file that was named -- reporting errors in a file
# this repo does not own, which reads exactly like a failure of ours.
if ! mango -c "$generated" -p > "$WORK/validate.out" 2>&1; then
  fail "mango accepts the generated keybindings" \
       "$(cat "$WORK/validate.out")
generated config saved at $generated"
fi
pass "mango accepts the generated keybindings"
