#!/bin/bash
#
# install/hardware/* is the caller that matters here: it runs as root, and yay
# refuses to run as root, so every AUR-only quirk package -- asusctl, the
# nvidia-580xx series, the DKMS trees -- had no way to install. What is checked
# below is that the command reaches yay when it can and says something useful
# when it cannot.
#
# The privilege drop itself needs EUID 0 to exercise and so is not covered here;
# what is covered is that a non-root caller goes straight to yay.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

installed="$test_tmp/installed"
calls="$test_tmp/calls"
: >"$installed"
: >"$calls"

cat >"$mock_bin/pacman" <<'SH'
#!/bin/bash
case "$1" in
  -Q) grep -qx "$2" "$STRAPD_TEST_INSTALLED" || exit 1 ;;
esac
exit 0
SH

cat >"$mock_bin/yay" <<'SH'
#!/bin/bash
printf 'yay %s\n' "$*" >>"$STRAPD_TEST_CALLS"
for arg in "$@"; do
  [[ $arg == -* ]] && continue
  printf '%s\n' "$arg" >>"$STRAPD_TEST_INSTALLED"
done
exit 0
SH

chmod +x "$mock_bin"/pacman "$mock_bin"/yay

run_aur_add() {
  : >"$calls"
  env \
    PATH="$mock_bin:$ROOT/bin:$PATH" \
    STRAPD_TEST_INSTALLED="$installed" \
    STRAPD_TEST_CALLS="$calls" \
    bash "$ROOT/bin/strapd-pkg-aur-add" "$@"
}

# --- the ordinary path -----------------------------------------------------

output=$(run_aur_add asusctl 2>&1) || fail "an AUR package installs" "$output"
grep -q '^yay -S --noconfirm --needed asusctl$' "$calls" ||
  fail "the package is handed to yay" "$(cat "$calls")"
pass "an AUR package is handed to yay"

output=$(run_aur_add asusctl 2>&1) || fail "a second run succeeds" "$output"
[[ -s $calls ]] && fail "an already-installed package is not reinstalled" "$(cat "$calls")"
pass "an already-installed package is left alone"

# A mixed call is the caller's mistake to make, but the command should still
# pass the whole list through in one go rather than one yay run per package.
: >"$installed"
output=$(run_aur_add nvidia-580xx-dkms nvidia-580xx-utils 2>&1) ||
  fail "several packages install" "$output"
[[ $(grep -c '^yay ' "$calls") == 1 ]] ||
  fail "several packages are one yay invocation" "$(cat "$calls")"
pass "several packages go to yay in one invocation"

# --- nothing to do ---------------------------------------------------------

output=$(run_aur_add 2>&1) || fail "no arguments is not an error" "$output"
[[ -s $calls ]] && fail "no arguments calls nothing" "$(cat "$calls")"
pass "no arguments is a no-op"

# --- yay missing -----------------------------------------------------------

# The one that used to be silent: install/hardware/* would call this on a
# machine with no AUR helper and get a bare non-zero exit.
rm -f "$mock_bin/yay"
: >"$installed"
status=0
output=$(run_aur_add asusctl 2>&1) || status=$?
((status != 0)) || fail "a missing yay is an error" "$output"
[[ $output == *"yay is not installed"* ]] ||
  fail "a missing yay says so" "$output"
[[ $output == *"strapd vendor build yay"* ]] ||
  fail "a missing yay says where to get it" "$output"
pass "a missing yay is an error that says how to fix it"
