#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log="$test_tmp/log"
state="$test_tmp/running"
mkdir -p "$stub_bin"

cat >"$stub_bin/pkill" <<'SH'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$PICKER_TEST_LOG"
[[ -s $PICKER_TEST_STATE ]] || exit 1
: >"$PICKER_TEST_STATE"
SH

cat >"$stub_bin/hyprpicker" <<'SH'
#!/bin/bash
printf 'hyprpicker %s\n' "$*" >>"$PICKER_TEST_LOG"
SH

chmod +x "$stub_bin"/*

run() {
  PICKER_TEST_LOG="$log" PICKER_TEST_STATE="$state" PATH="$stub_bin:$PATH" \
    "$ROOT/bin/strapd-color-picker" "$@"
}

: >"$log"
: >"$state"
run

grep -q 'hyprpicker -a' "$log" || fail "with no picker up, one is started" "$(cat "$log")"
pass "with no picker up, one is started"

# hyprpicker freezes the screen. A second press has to take the freeze away, or
# the desktop stays frozen behind a picker with no visible way out.
: >"$log"
printf 'up\n' >"$state"
run

grep -q 'pkill' "$log" || fail "a second press dismisses the picker" "$(cat "$log")"
grep -q 'hyprpicker -a' "$log" && fail "a second press does not start another picker" "$(cat "$log")"
pass "a second press dismisses the picker instead of starting another"

# Scoped to this user: a picker in someone else's session is not this session's
# to kill, and killing it would unfreeze their screen, not ours.
grep -q -- "-u $(id -u)" "$log" || fail "the kill is scoped to this user" "$(cat "$log")"
pass "the kill is scoped to this user"
