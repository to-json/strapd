#!/bin/bash
#
# Obsidian is opt-in. It is the one closed-source application the upstream list
# installed by default, and what keeps it out is a line's absence from a package
# list plus a file living in default/ rather than config/ -- both of which a
# later sweep could undo without anything else noticing.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

install_script="$ROOT/bin/strapd-install-obsidian"

if grep -qx 'obsidian' "$ROOT/install/strapd-base.packages"; then
  fail "Obsidian is not installed by default" "obsidian is back in strapd-base.packages"
fi
pass "Obsidian is not installed by default"

[[ -x $install_script ]] || fail "the Obsidian installer exists and is executable"
bash -n "$install_script" || fail "the Obsidian installer parses"
grep -q 'strapd-pkg-add obsidian' "$install_script" ||
  fail "the Obsidian installer installs the package"
pass "Obsidian is one command away"

# config/ is copied wholesale into /etc/skel/.config, so every user would get
# the Arch wrapper's flags file whether or not Obsidian is installed. default/
# is read by the installer alone.
[[ ! -e $ROOT/config/obsidian ]] ||
  fail "the Obsidian flags file is not seeded into every home" "config/obsidian exists"
[[ -f $ROOT/default/obsidian/user-flags.conf ]] ||
  fail "the Obsidian flags file is available to the installer"
grep -F '$STRAPD_PATH/default/obsidian/user-flags.conf' "$install_script" >/dev/null ||
  fail "the Obsidian installer places the flags file from the installer-only template"
pass "the Obsidian flags file is placed by the installer, not by /etc/skel"
