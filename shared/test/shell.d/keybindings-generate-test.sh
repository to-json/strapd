#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command yq
require_command jq

FIXTURES="$ROOT/test/shell.d/fixtures/keybindings"
GENERATE="$ROOT/bin/strapd-keybindings-generate"

# The generator resolves its lib/ through STRAPD_PATH, which defaults to the
# installed tree. Point it at this checkout.
export STRAPD_PATH="$ROOT"

[[ -x $GENERATE ]] || fail "bin/strapd-keybindings-generate exists and is executable" "not found or not executable at $GENERATE"
pass "bin/strapd-keybindings-generate exists and is executable"

# Full chain via the real entrypoint, invoked as a subprocess exactly as a user
# would run it. Every other test here sources the lib functions directly; this
# is the one that exercises the CLI.
status=0
kdl=$("$GENERATE" "$FIXTURES/minimal.toml" --backend niri) || status=$?
(( status == 0 )) || fail "minimal.toml --backend niri succeeds" "exited $status"
pass "minimal.toml --backend niri succeeds"

[[ $kdl == *"binds {"* ]] || fail "output contains a binds { header" "got: $kdl"
pass "output contains a binds { header"

[[ $kdl == *$'\n}'* ]] || fail "output closes the binds block" "got: $kdl"
pass "output closes the binds block"

[[ $kdl == *"Mod+W { close-window; }"* ]] || fail "window.close renders as Mod+W { close-window; }" "got: $kdl"
pass "window.close renders as Mod+W { close-window; }"

for n in 1 2 3; do
  [[ $kdl == *"Mod+$n { focus-workspace $n; }"* ]] || fail "workspace.focus.$n renders as Mod+$n { focus-workspace $n; }" "got: $kdl"
  pass "workspace.focus.$n renders as Mod+$n { focus-workspace $n; }"
done

[[ $kdl == *"layout.toggle_split: unsupported"* ]] || fail "unsupported layout.toggle_split is mentioned in a comment" "got: $kdl"
pass "unsupported layout.toggle_split is mentioned in a comment"

# What this checks that the renderer's own test does not is the dispatch:
# --backend picks the render_<backend> function, so a backend added to
# KNOWN_BACKENDS without its lib file sourced fails here rather than at a user's
# first run.
status=0
swaycfg=$("$GENERATE" "$FIXTURES/minimal.toml" --backend sway) || status=$?
(( status == 0 )) || fail "minimal.toml --backend sway succeeds" "exited $status"
pass "minimal.toml --backend sway succeeds"

[[ $swaycfg == *"bindsym \$mod+w kill"* ]] || fail "window.close renders as bindsym \$mod+w kill" "got: $swaycfg"
pass "window.close renders as bindsym \$mod+w kill"

[[ $swaycfg != *"binds {"* ]] || fail "the sway backend does not emit niri KDL" "got: $swaycfg"
pass "the sway backend does not emit niri KDL"

status=0
mangocfg=$("$GENERATE" "$FIXTURES/minimal.toml" --backend mango) || status=$?
(( status == 0 )) || fail "minimal.toml --backend mango succeeds" "exited $status"
pass "minimal.toml --backend mango succeeds"

[[ $mangocfg == *"bind=SUPER,w,killclient"* ]] || fail "window.close renders as bind=SUPER,w,killclient" "got: $mangocfg"
pass "window.close renders as bind=SUPER,w,killclient"

# Every invalid-*.toml fixture must fail loudly: non-zero exit and a non-empty
# stderr naming what went wrong.
for fixture in "$FIXTURES"/invalid-*.toml; do
  name=$(basename "$fixture")

  status=0
  err=$("$GENERATE" "$fixture" --backend niri 2>&1 >/dev/null) || status=$?
  (( status != 0 )) || fail "$name fails" "exited 0"
  pass "$name fails"

  [[ -n $err ]] || fail "$name failure has non-empty stderr" "stderr was empty"
  pass "$name failure has non-empty stderr"
done

# Nonexistent file.
status=0
err=$("$GENERATE" "$FIXTURES/does-not-exist.toml" --backend niri 2>&1 >/dev/null) || status=$?
(( status != 0 )) || fail "nonexistent file fails" "exited 0"
pass "nonexistent file fails"

[[ -n $err ]] || fail "nonexistent file failure has non-empty stderr" "stderr was empty"
pass "nonexistent file failure has non-empty stderr"

# Unknown backend: must fail clearly, naming it, not crash with a confusing
# "command not found" from a dynamic dispatch gone wrong. hyprland is the
# stand-in, since every backend that does get support stops failing here.
status=0
err=$("$GENERATE" "$FIXTURES/minimal.toml" --backend hyprland 2>&1 >/dev/null) || status=$?
(( status != 0 )) || fail "unknown backend 'hyprland' fails" "exited 0"
pass "unknown backend 'hyprland' fails"

[[ $err == *"hyprland"* ]] || fail "unknown backend error names the backend" "got: $err"
pass "unknown backend error names the backend"

# Missing or malformed arguments print a usage message rather than falling
# through into a confusing pipeline error.
status=0
err=$("$GENERATE" 2>&1 >/dev/null) || status=$?
(( status != 0 )) || fail "no arguments fails" "exited 0"
pass "no arguments fails"

[[ $err == *"usage"* ]] || fail "no-arguments error prints a usage message" "got: $err"
pass "no-arguments error prints a usage message"

status=0
err=$("$GENERATE" "$FIXTURES/minimal.toml" 2>&1 >/dev/null) || status=$?
(( status != 0 )) || fail "missing --backend fails" "exited 0"
pass "missing --backend fails"

[[ $err == *"usage"* ]] || fail "missing-backend error prints a usage message" "got: $err"
pass "missing-backend error prints a usage message"

status=0
err=$("$GENERATE" --backend 2>&1 >/dev/null) || status=$?
(( status != 0 )) || fail "--backend with no value fails" "exited 0"
pass "--backend with no value fails"

[[ $err == *"usage"* ]] || fail "--backend-with-no-value error prints a usage message" "got: $err"
pass "--backend-with-no-value error prints a usage message"
