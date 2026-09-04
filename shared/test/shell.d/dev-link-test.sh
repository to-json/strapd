#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# strapd-dev-link stages its sudoers drop-in and refuses to install one visudo
# will not parse, so the check itself has to be real here.
require_command visudo

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log_file="$test_tmp/dev-link.log"
conf_file="$test_tmp/strapd.conf"
sudoers_file="$test_tmp/strapd-dev-path"
mkdir -p "$stub_bin" "$test_tmp/home"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$STRAPD_DEV_LINK_TEST_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$STRAPD_DEV_LINK_TEST_LOG"
done
printf '\n' >>"$STRAPD_DEV_LINK_TEST_LOG"

case "$1" in
  tee)
    cat >"$STRAPD_DEV_LINK_TEST_CONF"
    ;;
  install)
    # The staged file is the second-to-last argument.
    cp "${@: -2:1}" "$STRAPD_DEV_LINK_TEST_SUDOERS"
    ;;
esac
SH
chmod +x "$stub_bin/sudo"

cat >"$stub_bin/gum" <<'SH'
#!/bin/bash

printf 'gum' >>"$STRAPD_DEV_LINK_TEST_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$STRAPD_DEV_LINK_TEST_LOG"
done
printf '\n' >>"$STRAPD_DEV_LINK_TEST_LOG"
SH
chmod +x "$stub_bin/gum"

cat >"$stub_bin/strapd-system-reboot" <<'SH'
#!/bin/bash

printf 'reboot\n' >>"$STRAPD_DEV_LINK_TEST_LOG"
SH
chmod +x "$stub_bin/strapd-system-reboot"

run_link() {
  HOME="$test_tmp/home" \
    STRAPD_DEV_LINK_TEST_LOG="$log_file" \
    STRAPD_DEV_LINK_TEST_CONF="$conf_file" \
    STRAPD_DEV_LINK_TEST_SUDOERS="$sudoers_file" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/strapd-dev-link" "$@"
}

# A checkout is split by distro; dev-link assembles a flat symlink tree
# from shared/ + arch/ and points strapd at that, not the checkout.
make_checkout() {
  local checkout="$test_tmp/$1"

  mkdir -p "$checkout/shared/bin" "$checkout/shared/default" \
    "$checkout/shared/themes" "$checkout/arch/bin"
  printf '%s' "$checkout"
}

devtree="$test_tmp/home/.local/state/strapd/dev-tree"

checkout=$(make_checkout checkout)

: >"$log_file"
: >"$sudoers_file"
run_link "$checkout" --no-reboot >"$test_tmp/link.out" 2>"$test_tmp/link.err"

[[ $(<"$conf_file") == "export STRAPD_PATH=\"$devtree\"" ]] ||
  fail "dev link points STRAPD_PATH at the assembled tree" "$(<"$conf_file")"
pass "dev link points STRAPD_PATH at the assembled tree"

# The assembled tree is symlinks into the checkout, so an edit is live.
[[ -d $devtree/bin && -d $devtree/default ]] ||
  fail "dev link assembles the flat tree from shared/ + arch/" "$(ls "$devtree" 2>&1)"
pass "dev link assembles the flat tree from shared/ + arch/"

# sudo reads secure_path, not the caller's PATH, so the tree has to come first
# there too or `sudo strapd-*` runs the packaged copy.
[[ $(<"$sudoers_file") == "Defaults secure_path=\"$devtree/bin:/usr/local/sbin:/usr/local/bin:/usr/bin\"" ]] ||
  fail "dev link prepends the assembled tree to sudo's secure_path" "$(<"$sudoers_file")"
pass "dev link prepends the assembled tree to sudo's secure_path"

grep -Eq $'^sudo\tinstall\t-Dm440\t-o\troot\t-g\troot\t[^\t]+\t/etc/sudoers\\.d/strapd-dev-path$' "$log_file" ||
  fail "dev link installs the drop-in root-owned and read-only" "$(cat "$log_file")"
pass "dev link installs the drop-in root-owned and read-only"

visudo -cf "$sudoers_file" >/dev/null ||
  fail "dev link writes a sudoers drop-in sudo can parse" "$(<"$sudoers_file")"
pass "dev link writes a sudoers drop-in sudo can parse"

grep -F "sudo now resolves strapd-* from $devtree/bin" "$test_tmp/link.out" >/dev/null ||
  fail "dev link reports the sudo change" "$(cat "$test_tmp/link.out")"
pass "dev link reports the sudo change"

# shell/ is phase 4's Noctalia tree. A checkout without it is a correct
# checkout today, and warning about it would cry wolf on every single link.
if grep -q 'shell not found' "$test_tmp/link.err"; then
  fail "dev link does not warn about the phase-4 shell tree" "$(cat "$test_tmp/link.err")"
fi
pass "dev link does not warn about the phase-4 shell tree"

if grep -Eq '^(gum|reboot)' "$log_file"; then
  fail "dev link --no-reboot skips the reboot prompt" "$(cat "$log_file")"
fi
pass "dev link --no-reboot skips the reboot prompt"

: >"$log_file"
run_link "$checkout" >/dev/null

grep -Fx $'gum\tconfirm\tReboot now to activate?' "$log_file" >/dev/null ||
  fail "interactive dev link still prompts for reboot" "$(cat "$log_file")"
grep -Fx 'reboot' "$log_file" >/dev/null ||
  fail "interactive dev link reboots through strapd-system-reboot" "$(cat "$log_file")"
pass "interactive dev link reboots through strapd-system-reboot"

# A path sudoers would have to escape, not one the shell alone handles.
quoted_checkout=$(make_checkout 'check "out"')

: >"$log_file"
: >"$sudoers_file"
run_link "$quoted_checkout" --no-reboot >/dev/null

visudo -cf "$sudoers_file" >/dev/null ||
  fail "dev link escapes a checkout path for sudoers" "$(<"$sudoers_file")"
pass "dev link escapes a checkout path for sudoers"

: >"$log_file"
if run_link "$test_tmp/missing" --no-reboot >/dev/null 2>"$test_tmp/missing.err"; then
  fail "dev link rejects a path that does not exist"
fi
grep -F "Error: path does not exist: $test_tmp/missing" "$test_tmp/missing.err" >/dev/null ||
  fail "dev link explains a path that does not exist" "$(cat "$test_tmp/missing.err")"
if grep -q 'sudo' "$log_file"; then
  fail "dev link touches nothing when the path does not exist" "$(cat "$log_file")"
fi
pass "dev link rejects a path that does not exist"
