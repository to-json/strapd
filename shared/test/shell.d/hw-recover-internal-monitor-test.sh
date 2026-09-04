#!/bin/bash
#
# The safety net under turning the laptop's own display off.
#
# The failure it prevents is a session with no output and no visible way back:
# the toggle says "internal display off", the external monitor it was set for is
# gone, and the compositor has not started yet. So every assertion asks which of
# those conditions the command insists on before it clears anything.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
TOGGLE="$home/.local/state/strapd/toggles/internal-monitor-disable"

# A stand-in /sys/class/drm: what a laptop has plugged in is not something a
# test can arrange.
drm="$test_tmp/drm"

seed_displays() {
  rm -rf "$drm"
  mkdir -p "$drm/card1-eDP-1"
  printf 'connected\n' >"$drm/card1-eDP-1/status"

  mkdir -p "$drm/card1-DP-1"
  printf '%s\n' "$1" >"$drm/card1-DP-1/status"
}

set_toggle() {
  if [[ $1 == on ]]; then
    mkdir -p "$(dirname "$TOGGLE")"
    touch "$TOGGLE"
  else
    rm -f "$TOGGLE"
  fi
}

recover() {
  env HOME="$home" STRAPD_DRM_PATH="$drm" PATH="$ROOT/bin:$PATH" \
    "$ROOT/bin/strapd-hw-recover-internal-monitor"
}

seed_displays disconnected
set_toggle on
recover
[[ ! -f $TOGGLE ]] ||
  fail "the toggle is cleared when the external monitor is gone"
pass "the toggle is cleared when the external monitor is gone"

# The external monitor is still there, so the setting is still the one they
# chose.
seed_displays connected
set_toggle on
recover
[[ -f $TOGGLE ]] ||
  fail "the toggle survives while an external monitor is connected"
pass "the toggle survives while an external monitor is connected"

# The laptop's own panel is always connected and is never the reason to keep the
# toggle; reading it as one would make this a no-op on every machine it matters
# on.
rm -rf "$drm"
mkdir -p "$drm/card1-eDP-1"
printf 'connected\n' >"$drm/card1-eDP-1/status"
set_toggle on
recover
[[ ! -f $TOGGLE ]] ||
  fail "the internal panel does not count as an external monitor"
pass "the internal panel does not count as an external monitor"

seed_displays disconnected
set_toggle off
recover ||
  fail "an unset toggle is not an error" "exited $?"
pass "an unset toggle is not an error"

# The path above is the contract between three parties: whatever sets the flag,
# this command that clears it, and the unit that decides whether to run. A
# ConditionPathExists that has drifted does not fail loudly, it just silently
# never runs -- which is the black screen again.
unit="$ROOT/default/systemd/user/strapd-recover-internal-monitor.service"
condition=$(sed -n 's/^ConditionPathExists=//p' "$unit")
[[ $condition == "%h/${TOGGLE#"$home/"}" ]] ||
  fail "the unit waits on the same file the command clears" \
    "unit: $condition
command: ${TOGGLE#"$home/"}"
pass "the unit waits on the same file the command clears"
