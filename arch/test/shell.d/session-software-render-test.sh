#!/bin/bash
#
# Reaching a desktop on a machine with no GPU.
#
# All three compositors are wlroots, and wlroots refuses a software renderer
# unless told to allow one. The failure is the worst kind: the session exits at
# once, the greeter comes back, and nothing reaches any journal.
#
# Where the variable is set matters as much as that it is set, so each wrong
# placement is asserted against here: strapd-session cannot reach the compositor
# (`uwsm start` launches it as a systemd unit, which does not inherit the
# caller's environment), and uwsm's env.d is not sourced at this stage at all.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

GENERATOR="$ROOT/default/systemd/user-environment-generators/50-strapd-renderer"

[[ -f $GENERATOR ]] || fail "the renderer generator is shipped"
[[ -x $GENERATOR ]] ||
  fail "the generator is executable" "systemd runs these rather than reading them"
pass "the renderer generator is shipped, and executable"

# systemd runs generators with no shell of its choosing; a bashism here is a
# generator that produces nothing and a failure mode identical to not shipping.
sh -n "$GENERATOR" || fail "the generator is POSIX sh"
pass "the generator is POSIX sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

# Whether this machine has a GPU is not something a test gets to choose, so the
# generator's own logic is run against a stand-in /dev/dri.
decide() {
  sed "s|/dev/dri/renderD|$1/renderD|" "$GENERATOR" | sh
}

mkdir -p "$test_tmp/with" "$test_tmp/without"
: >"$test_tmp/with/renderD128"

[[ -z $(decide "$test_tmp/with") ]] ||
  fail "a machine with a render node is left alone" "$(decide "$test_tmp/with")"
pass "a machine with a render node is left alone"

[[ $(decide "$test_tmp/without") == "WLR_RENDERER_ALLOW_SOFTWARE=1" ]] ||
  fail "a machine with no render node allows software rendering" \
    "got: $(decide "$test_tmp/without")"
pass "a machine with no render node allows software rendering"

# systemd reads KEY=VALUE lines. Anything else, a log line, a bare word, is
# either ignored or an error, and both look like the flag never being set.
while read -r line; do
  [[ $line =~ ^[A-Z_][A-Z0-9_]*=.*$ ]] ||
    fail "the generator prints only KEY=VALUE" "got: $line"
done < <(decide "$test_tmp/without")
pass "the generator prints only what systemd will read"

session_code=$(grep -vE '^[[:space:]]*#' "$ROOT/bin/strapd-session")
grep -q 'WLR_RENDERER_ALLOW_SOFTWARE' <<<"$session_code" &&
  fail "strapd-session does not set it; a systemd unit would not inherit it"

envd_code=$(grep -vE '^[[:space:]]*#' "$ROOT/default/uwsm/env.d/10-strapd")
grep -q 'WLR_RENDERER_ALLOW_SOFTWARE' <<<"$envd_code" &&
  fail "uwsm env.d does not set it; it is not sourced at this stage"
pass "it is not set in either place that cannot reach the compositor"

# install/place-tree.sh serves both routes, so the generator goes in from there.
placer="$ROOT/install/place-tree.sh"
grep -q 'user-environment-generators' "$placer" ||
  fail "the tree placer installs the generator"
grep -q 'install -Dm755 "\$generator"' "$placer" ||
  fail "the generator is installed executable"
pass "the tree placer puts it where systemd looks, executable"

generator_code=$(grep -vE '^[[:space:]]*#' "$GENERATOR")
grep -qiE 'qemu|vmware|virtualbox|hypervisor|systemd-detect-virt' <<<"$generator_code" &&
  fail "the decision does not name particular machines"
pass "the decision is about the device, not a list of machines"
