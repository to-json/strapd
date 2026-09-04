#!/bin/bash
#
# Feeds the generated Sway keybindings to sway itself. The renderer's own test
# is a golden-file test: it proves the output is what *we wrote down*, which
# says nothing about whether sway accepts it. Every keysym name and command in
# the [action.sway] tables is otherwise an unchecked assertion about sway's
# grammar. `sway -C` reports an unknown keysym and an unknown command, and exits
# 1 if it found either.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require sway jq yq

WORK="$ARTIFACTS/keybindings-sway-validate"
rm -rf "$WORK"
mkdir -p "$WORK"

# `sway -C` wants a whole config file, not a fragment. Sway has no required
# top-level sections and the renderer emits the `set $mod Mod4` its binds refer
# to, so the generated output alone is complete -- which keeps this test scoped
# to the binds.
generated="$WORK/binds.config"
if ! STRAPD_PATH="$ROOT" bash "$ROOT/bin/strapd-keybindings-generate" \
       "$ROOT/keybindings/actions.toml" --backend sway > "$generated" 2> "$WORK/generate.err"; then
  fail "generator produces a config for keybindings/actions.toml" "$(cat "$WORK/generate.err")"
fi
pass "generator produces a config for keybindings/actions.toml"

# `sway -C` brings the wlroots backend up before it reads the config, so on a
# box with no seat it dies at "Failed to start a DRM session" without ever
# looking at the file. The headless backend is what lets this run over ssh in
# the VM. It still logs "Failed to find any DRM render node"; that is the
# renderer, not the config, and sway carries on past it.
export XDG_RUNTIME_DIR="$WORK/runtime"
mkdir -p "$XDG_RUNTIME_DIR"

if ! WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
       sway --validate --config "$generated" > "$WORK/validate.out" 2>&1; then
  fail "sway accepts the generated keybindings" \
       "$(cat "$WORK/validate.out")
generated config saved at $generated"
fi
pass "sway accepts the generated keybindings"
