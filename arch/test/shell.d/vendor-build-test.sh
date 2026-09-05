#!/bin/bash
#
# strapd vendor build is what makes the AUR half of the package set reachable
# from an install that runs as root, so the things worth pinning down are the
# ones that decide what gets built and in what order: dependency order out of
# the .SRCINFO files, and not rebuilding what is already at the vendored
# version.
#
# pacman and makepkg are stubbed. This is about the ordering and skip decisions,
# not about whether a PKGBUILD compiles.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# strapd-vendor-build keeps its manifest and its provides map in associative
# arrays, which bash 3 does not have. Arch ships bash 5 and so does the Nix
# checks' shell, so this only skips on a developer's macOS host, where /bin/bash
# is still 3.2.
if ((BASH_VERSINFO[0] < 4)); then
  pass "bash 3; skipping ${BASH_SOURCE[0]##*/}"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
vendor="$test_tmp/vendor"
mkdir -p "$mock_bin" "$vendor"

# beta is built on alpha, so alpha has to be built first; gamma stands alone.
# The names are made up on purpose: the real graph (scenefx0.5 before mangowm,
# zig0.15 before herdr) is data in vendor/, not something to assert on here.
make_pkg() {
  local name=$1 version=$2
  shift 2
  mkdir -p "$vendor/$name"
  {
    printf 'pkgbase = %s\n' "$name"
    printf '\tpkgver = %s\n' "${version%-*}"
    printf '\tpkgrel = %s\n' "${version##*-}"
    local dep
    for dep in "$@"; do printf '\tdepends = %s\n' "$dep"; done
    printf 'pkgname = %s\n' "$name"
  } >"$vendor/$name/.SRCINFO"
  echo "# $name" >"$vendor/$name/PKGBUILD"
}

make_pkg alpha 1.0-1
make_pkg beta 2.0-1 alpha 'somerepopkg>=1.2'
make_pkg gamma 3.0-1

{
  printf '# name\tversion\taur-commit\tvendored-on\n'
  printf 'alpha\t1.0-1\tdeadbeef\t2026-09-05\n'
  printf 'beta\t2.0-1\tdeadbeef\t2026-09-05\n'
  printf 'gamma\t3.0-1\tdeadbeef\t2026-09-05\n'
} >"$vendor/manifest.tsv"

# INSTALLED is a file rather than a variable so the stubs and the test agree
# across process boundaries.
installed="$test_tmp/installed"
: >"$installed"

cat >"$mock_bin/pacman" <<'SH'
#!/bin/bash
case "$1" in
  -Q) grep -E "^$2 " "$STRAPD_TEST_INSTALLED" || exit 1 ;;
  -Si) grep -qx "$2" "$STRAPD_TEST_REPO_PKGS" 2>/dev/null || exit 1 ;;
  -S) printf 'pacman -S %s\n' "${*:2}" >>"$STRAPD_TEST_CALLS" ;;
  -U) printf 'pacman -U\n' >>"$STRAPD_TEST_CALLS"
      for arg in "${@:2}"; do
        case "$arg" in
          *.pkg.tar.*) ;;
          *) continue ;;
        esac
        # <name>-<pkgver>-<pkgrel>-<arch>.pkg.tar.zst, peeled from the right so
        # a name containing dashes survives.
        base=$(basename "$arg"); base=${base%.pkg.tar.*}
        rest=${base%-*}; rel=${rest##*-}
        rest=${rest%-*}; ver=${rest##*-}; name=${rest%-*}
        grep -vE "^$name " "$STRAPD_TEST_INSTALLED" >"$STRAPD_TEST_INSTALLED.new" || true
        mv "$STRAPD_TEST_INSTALLED.new" "$STRAPD_TEST_INSTALLED"
        printf '%s %s-%s\n' "$name" "$ver" "$rel" >>"$STRAPD_TEST_INSTALLED"
      done ;;
esac
exit 0
SH

cat >"$mock_bin/makepkg" <<'SH'
#!/bin/bash
name=$(awk -F' = ' '/^pkgname = /{print $2}' .SRCINFO)
ver=$(awk -F' = ' '/^[[:space:]]*pkgver = /{print $2}' .SRCINFO)
rel=$(awk -F' = ' '/^[[:space:]]*pkgrel = /{print $2}' .SRCINFO)
printf 'build %s\n' "$name" >>"$STRAPD_TEST_CALLS"
[[ -n ${STRAPD_TEST_FAIL_BUILD:-} && $name == "$STRAPD_TEST_FAIL_BUILD" ]] && exit 1
touch "$name-$ver-$rel-any.pkg.tar.zst"
exit 0
SH

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
# Drop the -u USER form the same way real sudo would, then run the rest.
[[ $1 == -u ]] && shift 2
exec "$@"
SH

chmod +x "$mock_bin"/pacman "$mock_bin"/makepkg "$mock_bin"/sudo

: >"$test_tmp/repo-pkgs"
echo somerepopkg >"$test_tmp/repo-pkgs"

run_build() {
  : >"$test_tmp/calls"
  env \
    PATH="$mock_bin:$PATH" \
    STRAPD_VENDOR_DIR="$vendor" \
    STRAPD_TEST_CALLS="$test_tmp/calls" \
    STRAPD_TEST_INSTALLED="$installed" \
    STRAPD_TEST_REPO_PKGS="$test_tmp/repo-pkgs" \
    ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} \
    "$BASH" "$ROOT/bin/strapd-vendor-build" "$@"
}
EXTRA_ENV=()

# --- dependency order ------------------------------------------------------

output=$(run_build 2>&1) || fail "a clean vendor tree builds" "$output"

alpha_at=$(grep -n '^build alpha$' "$test_tmp/calls" | cut -d: -f1)
beta_at=$(grep -n '^build beta$' "$test_tmp/calls" | cut -d: -f1)
[[ -n $alpha_at && -n $beta_at ]] ||
  fail "every vendored package is built" "$(cat "$test_tmp/calls")"
((alpha_at < beta_at)) ||
  fail "a package is built after what it depends on" "$(cat "$test_tmp/calls")"
pass "vendored packages are built in dependency order"

# The repo dependency goes to pacman; the vendored one does not, because it has
# just been built and installed.
grep -q 'pacman -S .*somerepopkg' "$test_tmp/calls" ||
  fail "repo dependencies are installed with pacman" "$(cat "$test_tmp/calls")"
grep -q 'pacman -S .*alpha' "$test_tmp/calls" &&
  fail "a vendored dependency is not also fetched from the repos" "$(cat "$test_tmp/calls")"
pass "only non-vendored dependencies go to pacman"

# --- idempotence -----------------------------------------------------------

output=$(run_build 2>&1) || fail "a second run succeeds" "$output"
grep -q '^build ' "$test_tmp/calls" &&
  fail "a second run rebuilds nothing" "$(cat "$test_tmp/calls")"
[[ $output == *"Already at the vendored version"* ]] ||
  fail "a second run says what it skipped" "$output"
pass "packages already at the vendored version are skipped"

output=$(run_build --force 2>&1) || fail "--force runs" "$output"
grep -q '^build alpha$' "$test_tmp/calls" ||
  fail "--force rebuilds anyway" "$(cat "$test_tmp/calls")"
pass "--force rebuilds what is already installed"

# --- a newer vendored version supersedes what is installed -----------------

make_pkg alpha 1.1-1
{
  printf '# name\tversion\taur-commit\tvendored-on\n'
  printf 'alpha\t1.1-1\tdeadbeef\t2026-09-05\n'
  printf 'beta\t2.0-1\tdeadbeef\t2026-09-05\n'
  printf 'gamma\t3.0-1\tdeadbeef\t2026-09-05\n'
} >"$vendor/manifest.tsv"
output=$(run_build 2>&1) || fail "a bumped version builds" "$output"
grep -q '^build alpha$' "$test_tmp/calls" ||
  fail "a version bump in the manifest rebuilds the package" "$(cat "$test_tmp/calls")"
pass "a version bump in the manifest rebuilds the package"

# --- naming one package ----------------------------------------------------

: >"$installed"
output=$(run_build beta 2>&1) || fail "naming one package builds" "$output"
grep -q '^build alpha$' "$test_tmp/calls" ||
  fail "naming a package also builds what it is built on" "$(cat "$test_tmp/calls")"
grep -q '^build gamma$' "$test_tmp/calls" &&
  fail "naming a package builds nothing else" "$(cat "$test_tmp/calls")"
pass "naming one package pulls in its vendored dependencies and nothing else"

status=0
run_build nosuchpackage >/dev/null 2>&1 || status=$?
((status != 0)) || fail "an unknown package name is an error"
pass "an unknown package name is an error"

# --- a failing build is reported, and does not take the rest with it -------

: >"$installed"
EXTRA_ENV=(STRAPD_TEST_FAIL_BUILD=beta)
status=0
output=$(run_build 2>&1) || status=$?
EXTRA_ENV=()
((status != 0)) || fail "a failed build exits non-zero" "$output"
[[ $output == *"Failed: beta"* ]] || fail "a failed build names the package" "$output"
grep -q '^build gamma$' "$test_tmp/calls" ||
  fail "one failed build does not stop the others" "$(cat "$test_tmp/calls")"
pass "a failed build is reported without stopping the rest"

# --- --list ----------------------------------------------------------------

output=$(run_build --list 2>&1) || fail "--list runs" "$output"
[[ $output == *alpha* && $output == *beta* && $output == *gamma* ]] ||
  fail "--list names every vendored package" "$output"
grep -q '^build ' "$test_tmp/calls" && fail "--list builds nothing" "$(cat "$test_tmp/calls")"
pass "--list reports without building"
