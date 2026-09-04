#!/bin/bash

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command yq
require_command jq

TEST_HOME=$(mktemp -d)
STUB_BIN=$(mktemp -d)
trap 'rm -rf "$TEST_HOME" "$STUB_BIN"' EXIT

# The real uwsm starts a compositor. This records the command line it was
# handed, which is the whole of what this script decides.
cat >"$STUB_BIN/uwsm" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" > "$UWSM_STUB_LOG"
STUB
chmod +x "$STUB_BIN/uwsm"

export UWSM_STUB_LOG="$TEST_HOME/uwsm.args"
export PATH="$STUB_BIN:$ROOT/bin:$PATH"
export STRAPD_PATH="$ROOT"
export HOME="$TEST_HOME"

strapd-session 2>/dev/null && fail "a session with no compositor named is an error"
pass "a session with no compositor named is an error"

strapd-session hyprland 2>/dev/null && fail "a compositor strapd does not ship is an error"
pass "a compositor strapd does not ship is an error"

# A compositor strapd renders keybindings for and cannot start is a session in
# the greeter's list that dies on selection.
while read -r backend; do
  rm -f "$UWSM_STUB_LOG"

  strapd-session "$backend" || fail "strapd-session starts $backend"
  pass "strapd-session starts $backend"

  args=$(cat "$UWSM_STUB_LOG")

  [[ $args == *" $backend" ]] || fail "$backend is started by its own binary" "uwsm got: $args"
  pass "$backend is started by its own binary"

  [[ $args == *"-D $backend"* ]] ||
    fail "$backend fills XDG_CURRENT_DESKTOP with its own name" "uwsm got: $args"
  pass "$backend fills XDG_CURRENT_DESKTOP with its own name"
done < <(strapd-keybindings-generate --list-backends)

# Every session file in the greeter's list has to name a compositor this script
# will actually start.
for desktop in "$ROOT"/default/wayland-sessions/*.desktop; do
  exec_line=$(grep '^Exec=' "$desktop")
  named=${exec_line##* }

  rm -f "$UWSM_STUB_LOG"
  strapd-session "$named" ||
    fail "$(basename "$desktop") names a session strapd-session can start" "Exec is $exec_line"
  pass "$(basename "$desktop") names a session strapd-session can start"

  [[ $exec_line == "Exec=strapd-session "* ]] ||
    fail "$(basename "$desktop") starts through strapd-session" "Exec is $exec_line"
  pass "$(basename "$desktop") starts through strapd-session"
done

# uwsm starts the compositor and then waits for it to announce itself, and none
# of strapd's three do that on their own, so a config leaving out `uwsm
# finalize` produces a session that runs for thirty seconds and gets SIGTERMed.
# A real boot is the only other thing that catches it.
for desktop in "$ROOT"/default/wayland-sessions/*.desktop; do
  exec_line=$(grep '^Exec=' "$desktop")
  named=${exec_line##* }

  [[ -d $ROOT/default/$named ]] ||
    fail "$named ships the config its session file starts" "no $ROOT/default/$named"
  pass "$named ships the config its session file starts"

  grep -rq 'uwsm.*finalize' "$ROOT/default/$named" ||
    fail "$named hands its session off to uwsm with finalize" \
         "nothing in default/$named runs uwsm finalize"
  pass "$named hands its session off to uwsm with finalize"
done

# The config the compositor is about to read is regenerated first, so a machine
# that never generated it still gets a session and an update that changed the
# shipped table does not leave the old binds behind.
[[ -f $TEST_HOME/.local/state/strapd/keybindings/niri.kdl ]] ||
  fail "starting a session refreshes the generated keybindings"
pass "starting a session refreshes the generated keybindings"

[[ -f $TEST_HOME/.local/state/strapd/keyboard/niri.kdl ]] ||
  fail "starting a session refreshes the generated keyboard layout"
pass "starting a session refreshes the generated keyboard layout"

# A keybinding table with a typo in it is a stale binding, not a login the user
# cannot complete.
cat >"$STUB_BIN/strapd-refresh-keybindings" <<'STUB'
#!/bin/bash
echo "refusing, for the test" >&2
exit 1
STUB
chmod +x "$STUB_BIN/strapd-refresh-keybindings"

rm -f "$UWSM_STUB_LOG"
strapd-session niri 2>/dev/null || fail "a failed refresh still starts the session"
pass "a failed refresh still starts the session"

[[ -f $UWSM_STUB_LOG ]] || fail "a failed refresh still reaches the compositor"
pass "a failed refresh still reaches the compositor"

# TryExec is how a greeter hides a session it cannot start. It named
# strapd-session, which is always installed, so it hid nothing -- and MangoWC is
# not in Arch's repos, so a machine installed from strapd's own media has that
# session file and not its binary.
for wm in niri sway mango; do
  entry="$ROOT/default/wayland-sessions/strapd-$wm.desktop"
  [[ -f $entry ]] || fail "a session file is shipped for $wm"
  [[ $(sed -n 's/^TryExec=//p' "$entry") == "$wm" ]] ||
    fail "the $wm session names its compositor in TryExec" \
      "got: $(sed -n 's/^TryExec=//p' "$entry")"
  [[ $(sed -n 's/^Exec=//p' "$entry") == "strapd-session $wm" ]] ||
    fail "the $wm session starts through strapd-session"
done
pass "each session names its own compositor in TryExec, and starts through strapd-session"

# A greeter that ignores TryExec offers it anyway, so the command says so too,
# after the log redirect: greetd discards what a session prints.
session_body=$(grep -vE '^[[:space:]]*#' "$ROOT/bin/strapd-session")
grep -q 'is not installed' <<<"$session_body" ||
  fail "the session says when its compositor is missing"
redirect_line=$(grep -n 'tee "\$session_log"' "$ROOT/bin/strapd-session" | head -1 | cut -d: -f1)
missing_line=$(grep -n 'is not installed' "$ROOT/bin/strapd-session" | head -1 | cut -d: -f1)
(( missing_line > redirect_line )) ||
  fail "the missing-compositor message is written where it can be read" \
    "said at line $missing_line, before the log starts at $redirect_line"
pass "a missing compositor is reported into the session log"

grep -q 'yay -S mangowc' <<<"$session_body" ||
  fail "mango's message says where to get it, since it is not in the repos"
pass "mango's message says where to get it"
