#!/bin/bash
#
# The installer's refusals. What it does when it proceeds is only testable by
# letting it change a machine, which the VM harness does end to end.
#
# Each guard stands in front of a failure that would otherwise happen halfway
# through, on a system that is by then already half-modified. The worst is the
# self-install: run from the installed tree, the copy step would delete the
# directory it is reading from.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

INSTALLER="$ROOT/install.sh"

[[ -x $INSTALLER ]] || fail "install.sh exists and is executable"
pass "install.sh exists and is executable"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

STUB_BIN="$test_tmp/bin"
mkdir -p "$STUB_BIN"

# sudo and pacman are recorded rather than run. An installer that got as far as
# calling either on a machine it should have refused has already done damage.
for command in sudo pacman; do
  cat >"$STUB_BIN/$command" <<'STUB'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$STUB_DIR/ran"
STUB
done
chmod +x "$STUB_BIN"/*

export STUB_DIR="$test_tmp"

run_installer() {
  rm -f "$test_tmp/ran"
  env PATH="$STUB_BIN:$PATH" STUB_DIR="$test_tmp" "$@" bash "$INSTALLER" --yes 2>&1
}

touched() { cat "$test_tmp/ran" 2>/dev/null; }

# strapd sets up a user session; root is not one, and strapd-apply-system
# refuses an install-user of root anyway. Better to say so before the packages.
if [[ $EUID -eq 0 ]]; then
  pass "running as root; skipping the not-root guard"
else
  # EUID cannot be faked, so this asserts the shape of the check rather than
  # the behaviour; the behaviour is covered by the VM run.
  grep -q 'EUID != 0' "$INSTALLER" || fail "the installer refuses to run as root"
  pass "the installer refuses to run as root"
fi

# Only where it can be observed. On an Arch machine this guard passes by design,
# and invoking the installer to watch it pass leaves records the next assertion
# would blame on the wrong invocation.
if [[ ! -f /etc/arch-release ]]; then
  output=$(run_installer)
  status=$?
  (( status != 0 )) || fail "a non-Arch machine is refused"
  [[ $output == *"not an Arch system"* ]] ||
    fail "a non-Arch machine is told why" "got: $output"
  [[ -z $(touched) ]] || fail "a refused machine is not touched" "$(touched)"
  pass "a machine that is not Arch is refused, and nothing is touched"
else
  grep -q '/etc/arch-release' "$INSTALLER" ||
    fail "the installer checks it is on an Arch machine"
  pass "this is an Arch machine; the non-Arch guard is asserted, not exercised"
fi

# The path is derived from BASH_SOURCE, so a copy of the script somewhere else
# is the case: it would otherwise read a package list that is not there.
cp "$INSTALLER" "$test_tmp/install.sh"
rm -f "$test_tmp/ran"
output=$(env PATH="$STUB_BIN:$PATH" STUB_DIR="$test_tmp" bash "$test_tmp/install.sh" --yes 2>&1)
status=$?
(( status != 0 )) || fail "a directory that is not a checkout is refused"
[[ $output == *"strapd checkout"* || $output == *"not an Arch system"* ]] ||
  fail "a directory that is not a checkout is told why" "got: $output"
[[ -z $(touched) ]] || fail "a refused directory is not touched" "$(touched)"
pass "a directory that is not a strapd checkout is refused"

# `rm -rf $TARGET` followed by `cp -a $REPO/.` empties the source when they are
# the same directory. Nobody would do it on purpose; somebody editing in
# /usr/share/strapd would.
grep -q 'already the installed tree' "$INSTALLER" ||
  fail "the installer refuses to copy the installed tree onto itself"
grep -qE '\[\[ \$REPO != "\$TARGET" \]\]' "$INSTALLER" ||
  fail "the self-install guard compares the checkout against the target"
pass "the installer refuses to copy the installed tree onto itself"

# .git is history and does not belong on an installed machine. The copy lives in
# install/place-tree.sh, shared with the ISO installer, so the exclusions do too.
placer="$ROOT/install/place-tree.sh"
for excluded in .git plan-harness-workspace; do
  grep -q "$excluded" <<<"$(grep -A2 'rm -rf "\$target"/' "$placer")" ||
    fail "the installed tree excludes $excluded"
done
grep -q 'place-tree.sh' "$INSTALLER" ||
  fail "the installer places the tree through the shared script"
pass "the installed tree excludes history and the harness"

# Everything root-owned already lives behind strapd-apply-system. An installer
# with its own copy of that sequence would be a second thing to keep in step.
grep -q 'strapd-apply-system' "$INSTALLER" ||
  fail "system setup goes through strapd-apply-system"
pass "system setup goes through the same entry point the ISO uses"

# Without it, a re-run reinstalls two hundred packages, which is most of what
# makes running this twice safe.
grep -q 'pacman -S --needed' "$INSTALLER" ||
  fail "packages are installed with --needed"
pass "a re-run does not reinstall every package"
