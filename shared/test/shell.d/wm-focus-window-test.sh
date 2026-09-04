#!/bin/bash
#
# Finding a window by name, and focusing it, on three compositors.
#
# The matching is deliberately not delegated: niri and mango cannot select
# windows themselves, and sway's criteria are AND-ed, so "app-id or title" is
# not sayable there anyway. Doing it in jq is what lets a caller pass one
# pattern and not care what is running.
#
# The window lists were captured in the VM. The XWayland node is constructed:
# no X client on the VM survives its software renderer.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

export PATH="$STUB_BIN:$ROOT/bin:$PATH"

# Each stub answers the list query out of $REPLY_FILE and writes anything else,
# only ever the focus command, to $ACTION_FILE.
for backend in niri swaymsg mmsg; do
  cat >"$STUB_BIN/$backend" <<'STUB'
#!/bin/bash
case "$*" in
  "msg -j windows"|"-t get_tree"|"get all-clients") cat "$REPLY_FILE" ;;
  *) printf '%s %s\n' "${0##*/}" "$*" >>"$ACTION_FILE" ;;
esac
STUB
  chmod +x "$STUB_BIN/$backend"
done

REPLY_FILE="$STUB_BIN/reply.json"
ACTION_FILE="$STUB_BIN/actions.log"
export REPLY_FILE ACTION_FILE

# Two windows each: a floating terminal, and a Chromium webapp whose app-id and
# title disagree -- the case the title half of the match exists for.
niri_windows='[{"id":3,"title":"foot","app_id":"TUI.float","pid":971,"workspace_id":2,"is_focused":true},
               {"id":2,"title":"ChatGPT - Chromium","app_id":"chrome-chatgpt.com__-Default","pid":972,"workspace_id":1,"is_focused":false}]'
sway_windows='{"type":"root","nodes":[{"type":"output","nodes":[
                 {"type":"workspace","nodes":[
                   {"type":"con","id":5,"pid":779,"app_id":"TUI.float","name":"foot","nodes":[],"floating_nodes":[]},
                   {"type":"con","id":6,"pid":780,"app_id":"chrome-chatgpt.com__-Default","name":"ChatGPT - Chromium","nodes":[],"floating_nodes":[]}],
                  "floating_nodes":[]}],
                "floating_nodes":[]}],"floating_nodes":[]}'
mango_windows='{"clients":[{"id":1,"pid":1207,"title":"foot","appid":"TUI.float","tags":[2],"is_focused":false},
                           {"id":2,"pid":1208,"title":"ChatGPT - Chromium","appid":"chrome-chatgpt.com__-Default","tags":[1],"is_focused":true}]}'

focus() {
  local backend=$1 pattern=$2

  case "$backend" in
    niri) printf '%s\n' "$niri_windows" ;;
    sway) printf '%s\n' "$sway_windows" ;;
    mango) printf '%s\n' "$mango_windows" ;;
  esac >"$REPLY_FILE"
  : >"$ACTION_FILE"

  unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
  case "$backend" in
    niri) export NIRI_SOCKET=/nonexistent ;;
    sway) export SWAYSOCK=/nonexistent ;;
    mango) export MANGO_INSTANCE_SIGNATURE=/nonexistent ;;
  esac

  strapd-wm-focus-window "$pattern"
}

# mango's focus command is the one worth reading twice: `focusid` alone is a
# no-op that still answers success, and `client,<id>` is what aims it.
for backend in niri sway mango; do
  case "$backend" in
    niri) tui='niri msg action focus-window --id 3'; web='niri msg action focus-window --id 2' ;;
    sway) tui='swaymsg [con_id=5] focus';           web='swaymsg [con_id=6] focus' ;;
    mango) tui='mmsg dispatch focusid client,1';    web='mmsg dispatch focusid client,2' ;;
  esac

  focus "$backend" 'TUI\.float' || fail "$backend focuses a window by app-id"
  [[ $(cat "$ACTION_FILE") == "$tui" ]] ||
    fail "$backend focuses a window by app-id" "expected: $tui
actual:   $(cat "$ACTION_FILE")"
  pass "$backend focuses a window by app-id"

  focus "$backend" ChatGPT || fail "$backend focuses a window by title"
  [[ $(cat "$ACTION_FILE") == "$web" ]] ||
    fail "$backend focuses a window by title" "expected: $web
actual:   $(cat "$ACTION_FILE")"
  pass "$backend focuses a window by title"

  focus "$backend" chatgpt || fail "$backend matches case-insensitively"
  [[ $(cat "$ACTION_FILE") == "$web" ]] ||
    fail "$backend matches case-insensitively" "got: $(cat "$ACTION_FILE")"
  pass "$backend matches case-insensitively"
done

# The word boundaries are load-bearing in both directions: a pattern has to
# reach inside a title to find "ChatGPT" in "ChatGPT - Chromium", but drop the
# \b and `strapd-launch-or-focus-webapp Chat` starts stealing that window.
focus niri Chat && fail "a prefix of a word is not a match" "focused: $(cat "$ACTION_FILE")"
[[ ! -s $ACTION_FILE ]] || fail "a prefix of a word focuses nothing" "got: $(cat "$ACTION_FILE")"
pass "a prefix of a word is not a match"

# Punctuation is a boundary, which is what lets a bare app-id find
# chrome-chatgpt.com__-Default without the caller writing the whole thing.
focus niri Default || fail "punctuation counts as a word boundary"
pass "punctuation counts as a word boundary"

# Nothing matched is an ordinary answer, not an error to report.
focus sway nosuchwindow && fail "no match is not a success"
[[ ! -s $ACTION_FILE ]] || fail "no match focuses nothing" "got: $(cat "$ACTION_FILE")"
pass "no match exits non-zero and focuses nothing"

# Sway leaves app_id null on an XWayland window and puts the class where X11
# put it. Constructed, not captured: see the note at the top.
sway_windows='{"type":"root","nodes":[{"type":"con","id":8,"pid":42,"app_id":null,"name":"Files","window_properties":{"class":"Nautilus"},"nodes":[],"floating_nodes":[]}],"floating_nodes":[]}'
focus sway Nautilus || fail "an XWayland window is findable by its class"
[[ $(cat "$ACTION_FILE") == 'swaymsg [con_id=8] focus' ]] ||
  fail "an XWayland window is findable by its class" "got: $(cat "$ACTION_FILE")"
pass "an XWayland window is findable by its class"

# Run outside a session and the answer is "nobody to ask", not "no match".
unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
output=$(strapd-wm-focus-window foot 2>&1)
status=$?
(( status == 2 )) || fail "no compositor at all is its own exit status" "exited $status"
[[ $output == *"no niri, sway or mango session"* ]] ||
  fail "no compositor at all says so" "got: $output"
pass "no compositor at all is its own exit status, and says so"

output=$(strapd-wm-focus-window 2>&1)
status=$?
(( status == 2 )) || fail "a missing pattern is a usage error" "exited $status"
[[ $output == Usage:* ]] || fail "a missing pattern prints usage" "got: $output"
pass "a missing pattern is a usage error"
