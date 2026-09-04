#!/bin/bash
#
# Locking the screen. What is worth testing is the arguments, because a wrong
# one is not cosmetic: this is the program standing between a walk-away and the
# session, and the protocol is fail-secure -- once it has the lock, nothing
# short of the password gives it back.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

STUB_BIN="$test_tmp/bin"
mkdir -p "$STUB_BIN"

cat >"$STUB_BIN/swaylock" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >"$STUB_DIR/swaylock.args"
STUB

# Stubbing pgrep is how the already-locked case gets to happen at all, and how a
# stub that exits once it has recorded its arguments can still stand for a locker
# that stays up. That distinction is the command's own success condition.
cat >"$STUB_BIN/pgrep" <<'STUB'
#!/bin/bash
for arg in "$@"; do
  case "$arg" in
    swaylock)
      [[ -f $STUB_DIR/locked || -f $STUB_DIR/swaylock.args ]] && exit 0
      ;;
    bitwarden) exit 1 ;;
  esac
done
exit 1
STUB
chmod +x "$STUB_BIN"/*

export STUB_DIR="$test_tmp"

home="$test_tmp/home"
mkdir -p "$home/.local/state/strapd/current/theme"

lock() {
  rm -f "$test_tmp/swaylock.args"
  env HOME="$home" PATH="$STUB_BIN:$ROOT/bin:$PATH" STUB_DIR="$test_tmp" \
    XDG_RUNTIME_DIR="$test_tmp" \
    "$ROOT/bin/strapd-system-lock"
}

lock_args() { cat "$test_tmp/swaylock.args" 2>/dev/null; }

lock || fail "the lock runs" "exited $?"

# Not --daemonize, deliberately: it forks after taking the lock but the parent
# stays, so one lock arrives as two processes still holding the caller's stdout.
[[ $(lock_args) == *"--daemonize"* ]] &&
  fail "the locker is not asked to daemonize itself" "$(lock_args)"
pass "the locker is not asked to daemonize itself"

# A held key repeats. The second request has to be a no-op rather than a failure
# reported at the moment the session is most correctly secured.
touch "$test_tmp/locked"
lock || fail "locking an already-locked session is not an error" "exited $?"
[[ -z $(lock_args) ]] ||
  fail "an already-locked session is not locked again" "$(lock_args)"
rm -f "$test_tmp/locked"
pass "locking an already-locked session is a no-op, not an error"

# Before any theme has been applied there is no colors.toml to read, and a lock
# screen that fails to draw because a colour was empty is the worst possible
# time to find out.
for flag in --ring-color --text-color --key-hl-color; do
  [[ $(lock_args) == *"$flag "* ]] || { lock; }
done
lock
args=$(lock_args)
for flag in --color --ring-color --text-color --key-hl-color --inside-color; do
  [[ $args == *"$flag "* ]] || fail "the lock screen is coloured" "missing $flag: $args"
done
# Six hex digits and no hash is what swaylock accepts, and also the shape a
# missing palette key would not have.
while read -r value; do
  [[ $value =~ ^[0-9a-fA-F]{6}$ ]] ||
    fail "every colour is a bare six-digit hex" "got: $value"
done < <(tr ' ' '\n' <<<"$args" | grep -A1 -E '^--[a-z-]*color$' | grep -v '^--' | grep -v '^--$')
pass "the lock screen is coloured, and every colour is one swaylock accepts"

# Every theme ships an unlock.png and this is the only thing that displays it.
[[ $(lock_args) == *"--image"* ]] &&
  fail "no image is passed when the theme has none" "$(lock_args)"
pass "no image is passed when the theme has none"

: >"$home/.local/state/strapd/current/theme/unlock.png"
lock
[[ $(lock_args) == *"--image $home/.local/state/strapd/current/theme/unlock.png"* ]] ||
  fail "the theme's unlock image is shown" "$(lock_args)"
pass "the theme's unlock image is shown"

[[ $(lock_args) == *"--ignore-empty-password"* ]] ||
  fail "a stray Enter is not a failed attempt" "$(lock_args)"
pass "a stray Enter is not a failed attempt"

# Deleting the stub would leave PATH reaching the real swaylock, so the test
# stops being a test and becomes an attempt to lock the screen of whoever is
# running the suite. The presence check is what the command branches on, so that
# is what gets stubbed.
cat >"$STUB_BIN/strapd-cmd-present" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$STUB_BIN/strapd-cmd-present"

output=$(lock 2>&1)
status=$?
(( status == 2 )) || fail "a missing locker is its own exit status" "exited $status"
[[ $output == *"swaylock is not installed"* ]] ||
  fail "a missing locker says so" "got: $output"
[[ -z $(lock_args) ]] ||
  fail "no locker is run when none is present" "$(lock_args)"
pass "a missing locker is its own exit status, and says so"
