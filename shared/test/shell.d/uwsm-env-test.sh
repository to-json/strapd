#!/bin/bash

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

ENV_FILE="$ROOT/default/uwsm/env.d/10-strapd"

# uwsm sources this with /bin/sh, not bash, so bashisms in it are a session
# that comes up with no environment at all.
sh -n "$ENV_FILE" || fail "the session environment is valid POSIX sh"
pass "the session environment is valid POSIX sh"

sh -n "$ROOT/default/uwsm/default" || fail "the session defaults are valid POSIX sh"
pass "the session defaults are valid POSIX sh"

session_env() {
  env -i \
    HOME="$TEST_HOME" \
    PATH="$ROOT/bin:/usr/local/bin:/usr/bin:/bin" \
    STRAPD_PATH="$ROOT" \
    sh -c ". '$ENV_FILE' >/dev/null 2>&1; printenv"
}

vars=$(session_env)

value_of() {
  printf '%s\n' "$vars" | sed -n "s/^$1=//p"
}

[[ $(value_of GDK_BACKEND) == "wayland,x11,*" ]] ||
  fail "the session pushes GTK onto Wayland" "GDK_BACKEND=$(value_of GDK_BACKEND)"
pass "the session pushes GTK onto Wayland"

[[ $(value_of QT_QPA_PLATFORM) == "wayland;xcb" ]] ||
  fail "the session pushes Qt onto Wayland" "QT_QPA_PLATFORM=$(value_of QT_QPA_PLATFORM)"
pass "the session pushes Qt onto Wayland"

[[ $(value_of ELECTRON_OZONE_PLATFORM_HINT) == "wayland" ]] ||
  fail "the session pushes Electron onto Wayland" "ELECTRON_OZONE_PLATFORM_HINT=$(value_of ELECTRON_OZONE_PLATFORM_HINT)"
pass "the session pushes Electron onto Wayland"

[[ $(value_of XCURSOR_SIZE) == "24" ]] ||
  fail "the session sets a cursor size" "XCURSOR_SIZE=$(value_of XCURSOR_SIZE)"
pass "the session sets a cursor size"

[[ $(value_of TERMINAL) == "strapd-cmd-terminal-exec" ]] ||
  fail "the session's defaults reach it" "TERMINAL=$(value_of TERMINAL)"
pass "the session's defaults reach it"

[[ $(value_of EDITOR) == *"strapd-launch-editor"* ]] ||
  fail "EDITOR goes through strapd's editor picker" "EDITOR=$(value_of EDITOR)"
pass "EDITOR goes through strapd's editor picker"

# BROWSER session-wide makes xdg-settings refuse to change the default
# browser, which breaks the browsers' own "set as default" buttons. It belongs
# to interactive shells, and this file must not be the thing that exports it.
[[ -z $(value_of BROWSER) ]] ||
  fail "BROWSER is left out of the session environment" "BROWSER=$(value_of BROWSER)"
pass "BROWSER is left out of the session environment"

# The documented user override.
mkdir -p "$TEST_HOME/.config/uwsm"
echo 'export TERMINAL=my-own-terminal' > "$TEST_HOME/.config/uwsm/default"

vars=$(session_env)
[[ $(value_of TERMINAL) == "my-own-terminal" ]] ||
  fail "a user's own uwsm/default wins" "TERMINAL=$(value_of TERMINAL)"
pass "a user's own uwsm/default wins"
