#!/bin/bash
#
# Feeds every file strapd-refresh-keybindings writes to the compositor that
# reads it.
#
# The three keybindings-<backend>-validate tests check what the generator prints.
# What they cannot check is the file the refresh command puts on disk: it
# prepends a header, and a header in the wrong comment syntax is a parse error on
# line 1 of a config every session of that compositor loads.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require niri sway mango jq yq

WORK="$ARTIFACTS/keybindings-refresh-validate"
rm -rf "$WORK"
mkdir -p "$WORK/home"

# The refresh command calls the generator by name, the way it will once bin/ is
# symlinked into /usr/bin, and that generator resolves its libs through
# STRAPD_PATH. Both point at this checkout.
export PATH="$ROOT/bin:$PATH"
export STRAPD_PATH="$ROOT"

out="$WORK/home/.local/state/strapd/keybindings"

if ! HOME="$WORK/home" strapd-refresh-keybindings > "$WORK/refresh.out" 2>&1; then
  fail "refresh writes a config for every backend" "$(cat "$WORK/refresh.out")"
fi
pass "refresh writes a config for every backend"

if ! niri validate -c "$out/niri.kdl" > "$WORK/niri.out" 2>&1; then
  fail "niri accepts the file refresh wrote" \
       "$(cat "$WORK/niri.out")
written config saved at $out/niri.kdl"
fi
pass "niri accepts the file refresh wrote"

# Same headless backend the sway generator test uses: `sway --validate` brings
# wlroots up before it reads the config, so without it a box with no seat fails
# at the DRM session and never looks at the file.
export XDG_RUNTIME_DIR="$WORK/runtime"
mkdir -p "$XDG_RUNTIME_DIR"

if ! WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
       sway --validate --config "$out/sway.conf" > "$WORK/sway.out" 2>&1; then
  fail "sway accepts the file refresh wrote" \
       "$(cat "$WORK/sway.out")
written config saved at $out/sway.conf"
fi
pass "sway accepts the file refresh wrote"

if ! mango -c "$out/mango.conf" -p > "$WORK/mango.out" 2>&1; then
  fail "mango accepts the file refresh wrote" \
       "$(cat "$WORK/mango.out")
written config saved at $out/mango.conf"
fi
pass "mango accepts the file refresh wrote"
