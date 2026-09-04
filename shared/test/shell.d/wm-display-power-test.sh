#!/bin/bash
#
# Turning the displays off and on, three ways.
#
# The interesting case is `on`. Doing it twice is not free: a redundant DPMS
# enable right after resume forces another modeset and flashes the panel at the
# unlock screen. sway reports whether its outputs are lit, so the second can be
# skipped; niri and mango do not report it, so there the command goes through.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

export PATH="$STUB_BIN:$ROOT/bin:$PATH"

# swaymsg both answers the get_outputs query and receives the command, so its
# stub has to tell them apart. The other two only ever receive.
cat >"$STUB_BIN/swaymsg" <<'STUB'
#!/bin/bash
if [[ $* == "-t get_outputs" ]]; then
  cat "$OUTPUTS_FILE"
else
  printf 'swaymsg %s\n' "$*" >>"$ACTION_FILE"
fi
STUB
for backend in niri mmsg; do
  cat >"$STUB_BIN/$backend" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$ACTION_FILE"
STUB
  chmod +x "$STUB_BIN/$backend"
done
chmod +x "$STUB_BIN/swaymsg"

ACTION_FILE="$STUB_BIN/actions.log"
OUTPUTS_FILE="$STUB_BIN/outputs.json"
export ACTION_FILE OUTPUTS_FILE

# A monitor that is on, unless a test says otherwise.
printf '%s\n' '[{"name":"eDP-1","active":true,"dpms":true}]' >"$OUTPUTS_FILE"

power() {
  local backend=$1 ; shift
  : >"$ACTION_FILE"

  unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
  case "$backend" in
    niri) export NIRI_SOCKET=/nonexistent ;;
    sway) export SWAYSOCK=/nonexistent ;;
    mango) export MANGO_INSTANCE_SIGNATURE=/nonexistent ;;
  esac

  strapd-wm-display-power "$@"
}

for backend in niri sway mango; do
  case "$backend" in
    niri) off='niri msg action power-off-monitors'; on='niri msg action power-on-monitors' ;;
    sway) off='swaymsg output * dpms off';         on='swaymsg output * dpms on' ;;
    mango) off='mmsg dispatch sleep_monitor';      on='mmsg dispatch wakeup_monitor' ;;
  esac

  power "$backend" off || fail "$backend turns the displays off"
  [[ $(cat "$ACTION_FILE") == "$off" ]] ||
    fail "$backend turns the displays off" "expected: $off
actual:   $(cat "$ACTION_FILE")"
  pass "$backend turns the displays off"
done

# Everything already lit: sway skips, the other two do not know and go ahead.
for backend in niri mango; do
  case "$backend" in
    niri) on='niri msg action power-on-monitors' ;;
    mango) on='mmsg dispatch wakeup_monitor' ;;
  esac
  power "$backend" on || fail "$backend turns the displays on"
  [[ $(cat "$ACTION_FILE") == "$on" ]] ||
    fail "$backend turns the displays on" "got: $(cat "$ACTION_FILE")"
  pass "$backend turns the displays on"
done

power sway on || fail "sway with everything already lit succeeds"
[[ ! -s $ACTION_FILE ]] ||
  fail "sway skips a redundant enable when every output is already lit" "got: $(cat "$ACTION_FILE")"
pass "sway skips a redundant enable when every output is already lit"

printf '%s\n' '[{"name":"eDP-1","active":true,"dpms":false}]' >"$OUTPUTS_FILE"
power sway on || fail "sway turns a dark output back on"
[[ $(cat "$ACTION_FILE") == 'swaymsg output * dpms on' ]] ||
  fail "sway turns a dark output back on" "got: $(cat "$ACTION_FILE")"
pass "sway turns a dark output back on"

# One dark output among several is still a reason to send the command.
printf '%s\n' '[{"name":"eDP-1","active":true,"dpms":true},{"name":"DP-1","active":true,"dpms":false}]' >"$OUTPUTS_FILE"
power sway on
[[ $(cat "$ACTION_FILE") == 'swaymsg output * dpms on' ]] ||
  fail "one dark output among several still gets the command" "got: $(cat "$ACTION_FILE")"
pass "one dark output among several still gets the command"

# `all` is true of an empty list, so a session sway reports no active output for
# must not read as "already lit".
printf '%s\n' '[{"name":"eDP-1","active":false,"dpms":false}]' >"$OUTPUTS_FILE"
power sway on
[[ $(cat "$ACTION_FILE") == 'swaymsg output * dpms on' ]] ||
  fail "no active output does not count as already lit" "got: $(cat "$ACTION_FILE")"
pass "no active output does not count as already lit"

unset NIRI_SOCKET SWAYSOCK MANGO_INSTANCE_SIGNATURE
output=$(strapd-wm-display-power off 2>&1)
status=$?
(( status == 2 )) || fail "no compositor at all is its own exit status" "exited $status"
[[ $output == *"no niri, sway or mango session"* ]] ||
  fail "no compositor at all says so" "got: $output"
pass "no compositor at all is its own exit status, and says so"

export SWAYSOCK=/nonexistent
for bad in "" dim --on; do
  output=$(strapd-wm-display-power $bad 2>&1)
  status=$?
  (( status == 2 )) || fail "'$bad' is a usage error" "exited $status"
  [[ $output == Usage:* ]] || fail "'$bad' prints usage" "got: $output"
done
pass "anything but on or off is a usage error"
