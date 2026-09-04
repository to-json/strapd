#!/bin/bash
#
# Feeds every file strapd-refresh-keyboard-layout writes to the compositor that
# reads it. The shell test checks that the layout out of /etc/vconsole.conf
# arrives in each file; what it cannot check is whether the file parses.
# `variant ","`, the entry a non-Latin layout gets so the variant list stays
# aligned with the layout list, is exactly the sort of thing only the real
# parser has an opinion about.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require niri sway mango

WORK="$ARTIFACTS/keyboard-layout-refresh-validate"
rm -rf "$WORK"
mkdir -p "$WORK/home"

export PATH="$ROOT/bin:$PATH"
export STRAPD_PATH="$ROOT"
export XDG_RUNTIME_DIR="$WORK/runtime"
mkdir -p "$XDG_RUNTIME_DIR"

out="$WORK/home/.local/state/strapd/keyboard"

# A non-Latin layout is the case that produces the awkward output.
cat >"$WORK/ru.conf" <<'CONF'
KEYMAP=ru
XKBLAYOUT=ru
XKBVARIANT=phonetic
CONF

validate_written_files() {
  local case_name="$1"

  if ! niri validate -c "$out/niri.kdl" > "$WORK/niri.out" 2>&1; then
    fail "niri accepts the $case_name layout" \
         "$(cat "$WORK/niri.out")
written config saved at $out/niri.kdl"
  fi
  pass "niri accepts the $case_name layout"

  # Headless for the same reason the keybinding tests use it: `sway --validate`
  # brings wlroots up before it reads the config.
  if ! WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 \
         sway --validate --config "$out/sway.conf" > "$WORK/sway.out" 2>&1; then
    fail "sway accepts the $case_name layout" \
         "$(cat "$WORK/sway.out")
written config saved at $out/sway.conf"
  fi
  pass "sway accepts the $case_name layout"

  if ! mango -c "$out/mango.conf" -p > "$WORK/mango.out" 2>&1; then
    fail "mango accepts the $case_name layout" \
         "$(cat "$WORK/mango.out")
written config saved at $out/mango.conf"
  fi
  pass "mango accepts the $case_name layout"
}

if ! HOME="$WORK/home" strapd-refresh-keyboard-layout > "$WORK/refresh.out" 2>&1; then
  fail "refresh writes a layout for every backend" "$(cat "$WORK/refresh.out")"
fi
pass "refresh writes a layout for every backend"

validate_written_files "installed"

if ! HOME="$WORK/home" STRAPD_VCONSOLE_CONF="$WORK/ru.conf" \
       strapd-refresh-keyboard-layout > "$WORK/refresh-ru.out" 2>&1; then
  fail "refresh writes a layout for a non-Latin install" "$(cat "$WORK/refresh-ru.out")"
fi
pass "refresh writes a layout for a non-Latin install"

validate_written_files "non-Latin"
