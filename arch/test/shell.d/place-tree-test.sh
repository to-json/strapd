#!/bin/bash
#
# Putting strapd's files where the system expects them.
#
# Two callers, two directions: install.sh onto the running machine, and the ISO
# installer into a mounted chroot. The bug that shape invites is writing the
# chroot's own paths into the installed system -- a symlink farm in /usr/bin
# pointing at /mnt/usr/share/strapd, dangling the moment the target is booted
# and invisible from the installer.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

PLACER="$ROOT/install/place-tree.sh"

[[ -x $PLACER ]] || fail "place-tree.sh exists and is executable"
pass "place-tree.sh exists and is executable"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

output=$(bash "$PLACER" 2>&1); status=$?
(( status != 0 )) || fail "no arguments is a usage error"
output=$(bash "$PLACER" --root "$test_tmp" 2>&1); status=$?
(( status != 0 )) || fail "a target with no source is a usage error"
output=$(bash "$PLACER" --root /nonexistent --from "$ROOT" 2>&1); status=$?
(( status != 0 )) || fail "a target that does not exist is a usage error"
pass "it refuses a missing target or a missing source"

# fakeroot so the suite can run it as a normal user: the real thing needs root
# for /usr, and paths and link targets are what matter here.
if ! command -v fakeroot >/dev/null; then
  pass "no fakeroot; skipping the placement itself"
  exit 0
fi

target="$test_tmp/target"
mkdir -p "$target"
fakeroot bash "$PLACER" --root "$target" --from "$ROOT" >/dev/null 2>&1 ||
  fail "placing the tree into an empty target succeeds"
pass "placing the tree into an empty target succeeds"

[[ -f $target/usr/share/strapd/install/strapd-base.packages ]] ||
  fail "the tree is placed"
pass "the tree is placed"

# The exclusions, which are most of the size and none of the use.
for excluded in .git plan-harness-workspace; do
  [[ ! -e $target/usr/share/strapd/$excluded ]] ||
    fail "the placed tree excludes $excluded"
done
pass "the placed tree excludes history and the harness"

# mkarchiso copies its airootfs with --no-preserve=mode, so the tree on the
# media arrives with every file at 0644. Trusting the source's modes meant the
# install ran for twenty minutes and died on `strapd-apply-system: Permission
# denied` at the last step. The source here is stripped the same way.
stripped="$test_tmp/stripped-source"
mkdir -p "$stripped"
cp -a "$ROOT/." "$stripped/"
# Files only: `chmod -R a-x` would take the directories' search bit with them,
# which is a different problem than the one being reproduced.
find "$stripped/bin" -type f -exec chmod a-x {} +

stripped_target="$test_tmp/stripped-target"
mkdir -p "$stripped_target"
fakeroot bash "$PLACER" --root "$stripped_target" --from "$stripped" >/dev/null 2>&1 ||
  fail "placing a tree whose modes were stripped succeeds"

[[ -x $stripped_target/usr/share/strapd/bin/strapd-apply-system ]] ||
  fail "commands are executable even when the source's modes were lost" \
    "$(ls -l "$stripped_target/usr/share/strapd/bin/strapd-apply-system")"
[[ -x $stripped_target/usr/share/strapd/bin/strapd-menu ]] ||
  fail "every command is executable, not just the one that failed first"
pass "commands are made executable even when the source's modes were lost"

link=$(readlink "$target/usr/bin/strapd-menu")
[[ $link == "/usr/share/strapd/bin/strapd-menu" ]] ||
  fail "a command links to its path inside the installed system" "got: $link"
pass "a command links to its path inside the installed system, not the target's"

# Nothing may carry the mount prefix, or it dangles once the target is booted.
dangling=$(find "$target/usr/bin" -type l -lname "$target/*" 2>/dev/null | head -3)
[[ -z $dangling ]] ||
  fail "no link points back through the target prefix" "$dangling"
pass "no link points back through the target prefix"

# $STRAPD_PATH cannot reach these: whatever reads them runs before anything has
# said where strapd is.
for fixed in \
  usr/share/uwsm/env.d/10-strapd \
  etc/profile.d/strapd.sh \
  usr/lib/systemd/user/strapd-crash-watch.service; do
  [[ -f $target/$fixed ]] || fail "$fixed is installed"
done
pass "the files that live at fixed system paths are installed"

generator="$target/usr/lib/systemd/user-environment-generators/50-strapd-renderer"
[[ -x $generator ]] ||
  fail "the environment generator is executable" "systemd runs these, it does not read them"
pass "the environment generator is installed executable"

# The step whose absence made a complete install useless. `useradd -m` seeds a
# home from /etc/skel; with nothing there, a fresh machine had no compositor
# config, niri wrote its own default, and the session was killed waiting for a
# `uwsm finalize` that default never calls.
for wm in niri sway mango; do
  [[ -d $target/etc/skel/.config/$wm ]] ||
    fail "a new user gets strapd's $wm config" "missing /etc/skel/.config/$wm"
done
pass "a new user gets a compositor config for each of the three"

# The shipped config's first include is strapd's own defaults, where `uwsm
# finalize` lives. niri's fallback config has neither.
grep -q 'include "/usr/share/strapd/default/niri/strapd.kdl"' \
  "$target/etc/skel/.config/niri/config.kdl" ||
  fail "the shipped niri config pulls in strapd's defaults" \
    "$(head -20 "$target/etc/skel/.config/niri/config.kdl")"
grep -q 'uwsm' "$target/usr/share/strapd/default/niri/autostart.kdl" ||
  fail "strapd's niri defaults are what finalize the session"
pass "the shipped config pulls in the defaults that finalize the session"

[[ -f $target/etc/skel/.bashrc ]] ||
  fail "a new user gets a .bashrc that finds strapd"
grep -q 'env-bootstrap' "$target/etc/skel/.bashrc" ||
  fail "the shipped .bashrc sources strapd's environment"
pass "a new user gets a .bashrc that finds strapd"

shared=$(ls "$target/usr/share/wayland-sessions"/*.desktop 2>/dev/null | wc -l)
own=$(ls "$target/usr/share/strapd/wayland-sessions"/*.desktop 2>/dev/null | wc -l)
(( shared == 3 )) || fail "the shared session directory gets all three" "found $shared"
(( own == 3 )) || fail "strapd's own session directory gets all three" "found $own"
pass "sessions are installed for strapd's greeter and for any other"
