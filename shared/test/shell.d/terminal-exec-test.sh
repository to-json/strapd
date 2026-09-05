#!/bin/bash
#
# strapd-cmd-terminal-exec is what stands between an install with no
# xdg-terminal-exec and an install with no terminal, so the tests that matter
# are the ones where xdg-terminal-exec is absent.
#
# PATH is built from scratch for every case: the fallback branch is only
# reachable when xdg-terminal-exec is genuinely unreachable, and a developer's
# own machine may well have it. Only the handful of tools the script actually
# calls are linked in beside the mocks.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

sys_bin="$test_tmp/sys"
mkdir -p "$sys_bin"
for tool in awk grep basename; do
  require_command "$tool"
  ln -s "$(command -v "$tool")" "$sys_bin/$tool"
done

terminal_exec="$ROOT/bin/strapd-cmd-terminal-exec"

# A fresh sandbox per case: its own mock PATH entry, its own home, its own
# config and data roots. Sets the mock_bin/test_home/run_terminal_exec trio the
# cases below use.
new_sandbox() {
  local name=$1
  sandbox="$test_tmp/$name"
  mock_bin="$sandbox/bin"
  test_home="$sandbox/home"
  mkdir -p "$mock_bin" "$test_home/.config" "$test_home/.local/share/applications"
}

# A stand-in terminal that reports the argument vector it was handed, one
# argument per line, so a case can assert on argument boundaries and not just
# on a flattened string.
mock_terminal() {
  local name=$1
  cat >"$mock_bin/$name" <<'SH'
#!/bin/bash
printf '%s\n' "$@"
SH
  chmod +x "$mock_bin/$name"
}

desktop_entry() {
  local id=$1
  cat >"$test_home/.local/share/applications/$id"
}

terminals_list() {
  cat >"$test_home/.config/xdg-terminals.list"
}

run_terminal_exec() {
  env -i \
    HOME="$test_home" \
    PATH="$mock_bin:$sys_bin" \
    XDG_CONFIG_HOME="$test_home/.config" \
    XDG_DATA_HOME="$test_home/.local/share" \
    XDG_CONFIG_DIRS="$sandbox/etc/xdg" \
    XDG_DATA_DIRS="$sandbox/usr/share" \
    "$terminal_exec" "$@"
}

assert_equal() {
  local description=$1 expected=$2 actual=$3
  [[ $actual == "$expected" ]] ||
    fail "$description" "expected:"$'\n'"$expected"$'\n'"actual:"$'\n'"$actual"
  pass "$description"
}

# --- the passthrough -------------------------------------------------------

new_sandbox delegates
cat >"$mock_bin/xdg-terminal-exec" <<'SH'
#!/bin/bash
printf '%s\n' "$@"
SH
chmod +x "$mock_bin/xdg-terminal-exec"
mock_terminal foot

# Nothing is configured in this sandbox at all: if the wrapper did any
# resolution of its own it would have nothing to resolve and would fail.
output=$(run_terminal_exec --app-id=org.strapd.terminal --title=strapd -e bash -c "echo hi")
assert_equal "the real xdg-terminal-exec gets the arguments untouched" \
  "--app-id=org.strapd.terminal
--title=strapd
-e
bash
-c
echo hi" "$output"

# --- the fallback ----------------------------------------------------------

new_sandbox from_desktop_entry
mock_terminal foot
terminals_list <<'EOF'
# Terminal emulator preference order for xdg-terminal-exec
foot.desktop
EOF
desktop_entry foot.desktop <<'EOF'
[Desktop Entry]
Type=Application
TryExec=foot
Exec=foot
Name=Foot
X-TerminalArgExec=-e
X-TerminalArgAppId=--app-id=
X-TerminalArgTitle=--title=
X-TerminalArgDir=--working-directory=

[Desktop Action New]
Name=New Terminal
Exec=foot --this-is-not-the-exec-line
EOF

output=$(run_terminal_exec --app-id=TUI.tile --title=strapd --dir=/tmp -e bash -c "echo hi there")
assert_equal "the entry's own X-TerminalArg keys build the command line" \
  "--app-id=TUI.tile
--title=strapd
--working-directory=/tmp
-e
bash
-c
echo hi there" "$output"

output=$(run_terminal_exec)
assert_equal "a terminal with no command is opened bare" "" "$output"

output=$(run_terminal_exec --print-id)
assert_equal "--print-id names the entry that would be launched" "foot.desktop" "$output"

# --- preference order ------------------------------------------------------

new_sandbox skips_uninstalled
mock_terminal foot
terminals_list <<'EOF'
com.mitchellh.ghostty.desktop
foot.desktop
EOF
desktop_entry com.mitchellh.ghostty.desktop <<'EOF'
[Desktop Entry]
Type=Application
TryExec=ghostty
Exec=ghostty
Name=Ghostty
EOF
desktop_entry foot.desktop <<'EOF'
[Desktop Entry]
Type=Application
TryExec=foot
Exec=foot
Name=Foot
X-TerminalArgAppId=--app-id=
EOF

output=$(run_terminal_exec --print-id)
assert_equal "an entry whose terminal is not installed is passed over" "foot.desktop" "$output"

new_sandbox user_list_wins
mock_terminal foot
mock_terminal kitty
mkdir -p "$sandbox/etc/xdg"
cat >"$sandbox/etc/xdg/xdg-terminals.list" <<'EOF'
kitty.desktop
EOF
terminals_list <<'EOF'
foot.desktop
EOF
desktop_entry foot.desktop <<'EOF'
[Desktop Entry]
TryExec=foot
Exec=foot
EOF
desktop_entry kitty.desktop <<'EOF'
[Desktop Entry]
TryExec=kitty
Exec=kitty
EOF

output=$(run_terminal_exec --print-id)
assert_equal "the user's list is read before the system's" "foot.desktop" "$output"

# --- entries that carry no X-TerminalArg keys ------------------------------

# kitty's upstream entry has none, and kitty has no -e: its command is trailing
# arguments. Getting this wrong is a terminal that opens and ignores the
# command it was asked to run.
new_sandbox builtin_arguments
mock_terminal kitty
terminals_list <<'EOF'
kitty.desktop
EOF
desktop_entry kitty.desktop <<'EOF'
[Desktop Entry]
Type=Application
TryExec=kitty
Exec=kitty
Name=kitty
EOF

output=$(run_terminal_exec --app-id=TUI.float --dir=/tmp -e bash -c "echo hi")
assert_equal "an entry with no X-TerminalArg keys gets strapd's built-in style" \
  "--class=TUI.float
--directory=/tmp
bash
-c
echo hi" "$output"

# --- no terminal at all ----------------------------------------------------

new_sandbox no_terminal
terminals_list <<'EOF'
foot.desktop
EOF

status=0
output=$(run_terminal_exec -e true 2>&1) || status=$?
(( status == 3 )) || fail "no terminal anywhere is an error, not a silent success" \
  "exit status: $status"$'\n'"output: $output"
[[ $output == *"no terminal emulator found"* ]] ||
  fail "no terminal anywhere says so" "$output"
pass "no terminal anywhere is an error that says so"

status=0
run_terminal_exec --print-id >/dev/null 2>&1 || status=$?
(( status != 0 )) || fail "--print-id with nothing to name fails" "exit status: $status"
pass "--print-id with nothing to name fails"
