#!/bin/bash
#
# Building the installation media. The build itself takes gigabytes and the
# better part of an hour, so what is checked is the profile it hands to
# mkarchiso: the two mistakes it invites are shipping the repo's bulk on the
# medium, and letting the image's name and its filesystem label disagree.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

BUILD="$ROOT/iso/build.sh"

[[ -x $BUILD ]] || fail "iso/build.sh exists and is executable"
bash -n "$BUILD" || fail "iso/build.sh parses"
pass "iso/build.sh exists, is executable, and parses"

code=$(grep -vE '^[[:space:]]*#' "$BUILD")

grep -q 'EUID == 0' <<<"$code" || fail "the build requires root"
grep -q 'command -v mkarchiso' <<<"$code" || fail "the build checks archiso is installed"
pass "the build refuses to start without root or archiso"

# Vendoring archiso's profile would mean carrying a few hundred files that go
# stale against it. Copying at build time is free as long as nothing forks it.
grep -q '/usr/share/archiso/configs/releng' <<<"$code" ||
  fail "the profile comes from archiso's own releng"
overlay_files=$(find "$ROOT/iso/overlay" -type f | wc -l)
(( overlay_files <= 10 )) ||
  fail "the overlay stays small enough to read" "$overlay_files files"
pass "the profile is archiso's releng with a small overlay, not a fork"

for excluded in .git plan-harness-workspace; do
  grep -q "$excluded" <<<"$(grep -A2 'rm -rf "\$profile/airootfs/usr/share/strapd"' "$BUILD")" ||
    fail "the tree on the medium excludes $excluded"
done
pass "the tree on the medium excludes history and the harness"

# archiso substitutes iso_label into the boot entries, which is how the kernel
# finds the medium it booted from. Renaming one without the other produces an
# image that boots to a dracut prompt.
grep -q 'iso_name=' <<<"$code" || fail "the image is named"
grep -q 'iso_label=' <<<"$code" || fail "the image is labelled"
grep -q 'STRAPD_' <<<"$code" || fail "the label is strapd's"
pass "the image is renamed and relabelled together"

[[ -x $ROOT/iso/overlay/airootfs/usr/local/bin/strapd-install ]] ||
  fail "the installer is in the overlay, executable"
grep -q 'usr/local/bin/strapd-install' <<<"$code" ||
  fail "the build sets the installer's mode in profiledef" \
    "mkarchiso applies file_permissions over the copied tree"
pass "the installer ships executable, and its mode is declared"

motd="$ROOT/iso/overlay/airootfs/etc/motd"
[[ -f $motd ]] || fail "the medium greets the user with something"
grep -q 'strapd-install' "$motd" || fail "the greeting names the installer"
grep -q 'iwctl' "$motd" ||
  fail "the greeting says how to get on wi-fi, which the install needs"
pass "the medium says how to install and how to get online first"
