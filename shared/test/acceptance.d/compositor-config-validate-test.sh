#!/bin/bash
#
# Runs each compositor over the config a user actually gets: the seeded
# ~/.config tree, the strapd defaults it includes, and the two fragments
# generated for this machine.
#
# The other acceptance tests validate one generated file in isolation. This is
# the one that checks they compose: that include paths resolve, that generated
# fragments merge into the sections the defaults already set, and that a user
# file loading last does not have to restate anything to be valid.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require jq yq

WORK="$ARTIFACTS/compositor-config-validate"
rm -rf "$WORK"
mkdir -p "$WORK"

export PATH="$ROOT/bin:$PATH"
export STRAPD_PATH="$ROOT"
export XDG_RUNTIME_DIR="$WORK/runtime"
mkdir -p "$XDG_RUNTIME_DIR"

# `sway --validate` brings wlroots up before it reads the config, so on a box
# with no seat it dies at the DRM session without ever looking at the file.
export WLR_BACKENDS=headless
export WLR_LIBINPUT_NO_DEVICES=1

for desktop in "$ROOT"/default/wayland-sessions/*.desktop; do
  exec_line=$(grep '^Exec=' "$desktop")
  compositor=${exec_line##* }

  require "$compositor"

  home="$WORK/$compositor"
  config_dir="$home/.config/$compositor"
  mkdir -p "$config_dir"
  cp -R "$ROOT/config/$compositor/." "$config_dir/"

  # The seeded configs point at /usr/share/strapd because no config language
  # here expands a variable. This checkout is not there, so those lines are
  # pointed here -- the only difference between what this validates and what
  # ships.
  installed_includes=$(grep -rl '/usr/share/strapd/default/' "$config_dir" || true)
  [[ -n $installed_includes ]] ||
    fail "$compositor's seeded config includes strapd's defaults" \
         "nothing under config/$compositor names /usr/share/strapd/default/"
  pass "$compositor's seeded config includes strapd's defaults"

  # shellcheck disable=SC2086
  sed -i "s|/usr/share/strapd/default/|$ROOT/default/|" $installed_includes

  for refresh in strapd-refresh-keyboard-layout strapd-refresh-keybindings; do
    if ! HOME="$home" "$refresh" > "$WORK/$compositor.$refresh.out" 2>&1; then
      fail "$refresh writes what $compositor's config includes" \
           "$(cat "$WORK/$compositor.$refresh.out")"
    fi
  done
  pass "the generated fragments $compositor's config includes are written"

  # A compositor with a session file and no arm here is an unchecked config, so
  # this fails rather than skipping.
  case "$compositor" in
    niri) check=(niri validate -c "$config_dir/config.kdl") ;;
    sway) check=(sway --validate --config "$config_dir/config") ;;
    mango) check=(mango -c "$config_dir/config.conf" -p) ;;
    *)
      fail "$compositor can be validated" \
           "$(basename "$desktop") ships a session for $compositor and this test has no way to check its config"
      ;;
  esac

  # HOME, because every one of these configs reaches into ~/.local/state for its
  # generated fragments, expanded from the environment rather than the config's
  # own location.
  if ! HOME="$home" "${check[@]}" > "$WORK/$compositor.validate.out" 2>&1; then
    fail "$compositor accepts its whole seeded config" \
         "$(cat "$WORK/$compositor.validate.out")
config tree saved at $config_dir"
  fi
  pass "$compositor accepts its whole seeded config"

  # Accepting it is not the same as reading all of it: mango exits 0 for a
  # `source=` it could not open, logging the failure and carrying on without
  # everything that file was going to set. Read the output too.
  if grep -qi 'failed to open config file' "$WORK/$compositor.validate.out"; then
    fail "$compositor opens every file its config pulls in" \
         "$(cat "$WORK/$compositor.validate.out")
config tree saved at $config_dir"
  fi
  pass "$compositor opens every file its config pulls in"
done
