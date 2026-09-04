#!/bin/bash
#
# Asks the compositor that is actually running. The shell test replays captured
# replies, which proves the parsing and nothing about whether the query still
# works: a renamed field, a subcommand that grew a flag, or an IPC socket that
# moved all look identical to a fixture.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require jq

export PATH="$ROOT/bin:$PATH"

session=""
for backend in NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE; do
  [[ -n ${!backend:-} ]] && session=$backend
done

if [[ -z $session ]]; then
  pass "no compositor session; skipping the live focused-window query"
  exit 0
fi

# A terminal of our own, so the query has something to find that this test knows
# the pid of. The window rules float this one rather than tiling it.
require foot

foot --app-id=TUI.float -e sleep 30 >/dev/null 2>&1 &
launched=$!
trap 'kill "$launched" 2>/dev/null' EXIT

# The window has to map and take focus before there is anything to report.
for _ in {1..20}; do
  window=$(strapd-wm-focused-window 2>/dev/null) && [[ -n $window ]] && break
  sleep 0.5
done

[[ -n ${window:-} ]] ||
  fail "the running compositor reports a focused window" \
       "nothing focused 10s after launching a terminal under $session"
pass "the running compositor reports a focused window"

for field in pid app_id title; do
  value=$(jq -r ".$field // empty" <<<"$window")
  [[ -n $value ]] || fail "the answer carries $field" "got: $window"
done
pass "the answer carries a pid, an app-id and a title"

pid=$(jq -r '.pid' <<<"$window")
[[ -d /proc/$pid ]] ||
  fail "the pid it reports is a process that exists" "pid $pid has no /proc entry"
pass "the pid it reports is a process that exists"

app_id=$(jq -r '.app_id' <<<"$window")
[[ $app_id == TUI.float ]] ||
  fail "the app-id it reports is the one the window was given" \
       "launched foot as TUI.float; got $app_id"
pass "the app-id it reports is the one the window was given"

# What strapd-cmd-terminal-cwd is for. Ours runs `sleep`, not a shell, so the
# answer is $HOME -- which is what every caller of it falls back to.
cwd=$(strapd-cmd-terminal-cwd)
[[ -d $cwd ]] ||
  fail "the terminal's working directory is a directory" "got: $cwd"
pass "the terminal's working directory is a directory"
