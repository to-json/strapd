#!/bin/bash
#
# Opening a file manager. apps.file_manager names a command upstream does not
# have, so what this checks is that strapd's own pattern was followed: one line
# in state/strapd/defaults/, the same as the editor, browser and terminal
# launchers, with a fallback to what the base packages install.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

STUB_BIN="$test_tmp/bin"
mkdir -p "$STUB_BIN"

# setsid and uwsm-app stand in for the session-launch wrapper, so the argv is
# readable rather than run.
cat >"$STUB_BIN/setsid" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >"$STUB_DIR/launched"
STUB
chmod +x "$STUB_BIN/setsid"

export STUB_DIR="$test_tmp"

home="$test_tmp/home"
defaults="$home/.local/state/strapd/defaults"
mkdir -p "$defaults"

set_default() {
  if [[ -n $1 ]]; then
    printf '%s\n' "$1" >"$defaults/file-manager"
  else
    rm -f "$defaults/file-manager"
  fi
}

# Present on PATH so the availability check passes for these and fails for
# anything else.
provide() {
  rm -f "$STUB_BIN"/nautilus "$STUB_BIN"/thunar "$STUB_BIN"/dolphin
  local name
  for name in "$@"; do
    printf '#!/bin/bash\n' >"$STUB_BIN/$name"
    chmod +x "$STUB_BIN/$name"
  done
}

launch() {
  rm -f "$test_tmp/launched"
  env HOME="$home" PATH="$STUB_BIN:$ROOT/bin:$PATH" STUB_DIR="$test_tmp" \
    "$ROOT/bin/strapd-launch-file-manager" "$@"
}

launched() { cat "$test_tmp/launched" 2>/dev/null; }

provide nautilus
set_default ""
launch
[[ $(launched) == *"nautilus --new-window"* ]] ||
  fail "with no default set, the shipped file manager opens" "$(launched)"
pass "with no default set, the shipped file manager opens"

# Nautilus reuses its running instance for a bare invocation, so the key would
# raise the old window instead of opening one.
[[ $(launched) == *"--new-window"* ]] ||
  fail "nautilus is asked for a new window" "$(launched)"
pass "nautilus is asked for a new window"

provide nautilus thunar
set_default thunar
launch
[[ $(launched) == *"thunar"* ]] ||
  fail "the chosen file manager opens" "$(launched)"
[[ $(launched) == *"--new-window"* ]] &&
  fail "another manager is not handed nautilus's flag" "$(launched)"
pass "the chosen file manager opens, without nautilus's flag"

# A name left behind by a manager that has since been removed. Falling back is
# the difference between a key that opens the wrong thing and one that does
# nothing at all.
provide nautilus
set_default dolphin
launch
[[ $(launched) == *"nautilus"* ]] ||
  fail "a default that is not installed falls back" "$(launched)"
pass "a default that is not installed falls back to the shipped one"

provide nautilus
set_default ""
launch /tmp
[[ $(launched) == *"nautilus /tmp"* ]] ||
  fail "a path is handed to the file manager" "$(launched)"
pass "a path is handed to the file manager"
