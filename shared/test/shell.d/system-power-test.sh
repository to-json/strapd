#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls.log"
mkdir -p "$mock_bin"

cat >"$mock_bin/systemd-run" <<'SH'
#!/bin/bash

printf 'systemd-run %s\n' "$*" >>"$CALL_LOG"
[[ ${FAIL_SYSTEMD_RUN:-false} == "true" ]] && exit 1
exit 0
SH

# strapd-osd is phase 4 and is stubbed rather than skipped: whether the toast
# goes up before or after the windows are asked to close is part of what this
# checks, and it has to be in the log to be checked.
for command in strapd-osd strapd-state strapd-wm-close-all sleep; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash

printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
chmod +x "$mock_bin"/*

run_power_command() {
  local action="$1"

  : >"$call_log"
  PATH="$mock_bin:$PATH" CALL_LOG="$call_log" "$ROOT/bin/strapd-system-$action"
}

assert_power_calls() {
  local action="$1" systemctl_action="$2" osd_icon="$3" osd_message="$4"
  local expected_log="$test_tmp/$action-expected.log"

  cat >"$expected_log" <<EOF
systemd-run --user --collect --quiet --on-active=2s --timer-property=AccuracySec=100ms systemctl $systemctl_action --no-wall
strapd-osd -i $osd_icon -m $osd_message -d 5000
strapd-state clear re*-required
strapd-wm-close-all 
sleep 1
EOF

  diff -u "$expected_log" "$call_log" || fail "$action runs after being scheduled outside the terminal scope"
  pass "$action runs after being scheduled outside the terminal scope"
}

run_power_command reboot
assert_power_calls reboot reboot reboot Rebooting

run_power_command shutdown
assert_power_calls shutdown poweroff shutdown "Shutting down"

# Closing every window is not something to do on the way to a reboot that was
# never scheduled: the session would be emptied and then stay up.
for action in reboot shutdown; do
  : >"$call_log"
  if PATH="$mock_bin:$PATH" CALL_LOG="$call_log" FAIL_SYSTEMD_RUN=true "$ROOT/bin/strapd-system-$action"; then
    fail "$action aborts when scheduling fails"
  fi

  if (( $(wc -l <"$call_log") != 1 )); then
    fail "$action leaves state and windows alone when scheduling fails" "$(cat "$call_log")"
  fi
  pass "$action leaves state and windows alone when scheduling fails"
done
