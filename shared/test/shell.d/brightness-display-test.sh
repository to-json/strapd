#!/bin/bash
#
# Which monitor is focused and what make it is come from strapd-wm-monitors;
# off/on go through strapd-wm-display-power. Below that sit the DDC bus cache,
# the VCP range arithmetic and the one-percent step near zero.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls"
runtime_dir="$test_tmp/runtime"
monitors_file="$test_tmp/monitors.json"
mkdir -p "$mock_bin" "$runtime_dir"

# Mocked at its own boundary: this is about what strapd-brightness-display does
# with the answer, not how the compositors are asked. wm-monitors-test.sh covers
# that half.
cat >"$mock_bin/strapd-wm-monitors" <<'SH'
#!/bin/bash
if [[ ${1:-} == --focused ]]; then
  jq -c 'first(.[] | select(.focused)) // empty' <"$MONITORS_FILE"
else
  cat "$MONITORS_FILE"
fi
SH

cat >"$mock_bin/strapd-wm-display-power" <<'SH'
#!/bin/bash
printf 'display-power %s\n' "$*" >>"$CALL_LOG"
SH

cat >"$mock_bin/strapd-brightness-display-apple" <<'SH'
#!/bin/bash
printf 'apple %s\n' "$*" >>"$CALL_LOG"
SH

cat >"$mock_bin/strapd-hw-display" <<'SH'
#!/bin/bash
printf 'mock_backlight\n'
SH

cat >"$mock_bin/brightnessctl" <<'SH'
#!/bin/bash
printf 'brightnessctl %s\n' "$*" >>"$CALL_LOG"
if [[ $* == *" -m"* ]]; then
  printf 'mock_backlight,backlight,40,40%%\n'
fi
SH

cat >"$mock_bin/ddcutil" <<'SH'
#!/bin/bash
printf 'ddcutil %s\n' "$*" >>"$CALL_LOG"

if [[ $* == *" detect --brief"* ]]; then
  cat <<EOF
Display 1
   I2C bus:             /dev/i2c-${DDC_BUS:-7}
   DRM connector:       card1-${DDC_CONNECTOR:-DP-1}
EOF
elif [[ $* == *" getvcp 10 "* ]]; then
  [[ ${DDC_READ_FAIL:-0} == "1" ]] && exit 1
  printf 'VCP 10 C %s %s\n' "${DDC_CURRENT:-40}" "${DDC_MAXIMUM:-80}"
fi
SH

chmod +x "$mock_bin"/*

set_monitors() {
  printf '%s\n' "$1" >"$monitors_file"
}

# One internal panel, focused, no external display: the laptop case, and the
# default for everything below that does not say otherwise.
set_monitors '[{"name":"eDP-1","make":"Unknown","model":"Unknown","focused":true,"dpms":null,"x":0,"y":0,"width":1920,"height":1080,"scale":1}]'

run_brightness() {
  CALL_LOG="$call_log" MONITORS_FILE="$monitors_file" XDG_RUNTIME_DIR="$runtime_dir" \
    PATH="$mock_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/strapd-brightness-display" "$@"
}

brightness=$(run_brightness --monitor DP-1)
[[ $brightness == "50" ]] || fail "external brightness is converted to a percentage" "actual: $brightness"
pass "external brightness is converted to a percentage"

(( $(grep -c '^ddcutil --skip-ddc-checks detect --brief$' "$call_log") == 1 )) || fail "DDC bus is detected once"
run_brightness --monitor DP-1 >/dev/null
(( $(grep -c '^ddcutil --skip-ddc-checks detect --brief$' "$call_log") == 1 )) || fail "DDC bus mapping is cached"
pass "DDC bus mapping is cached"

run_brightness --no-osd --monitor DP-1 25%
grep -F 'ddcutil --bus 7 --skip-ddc-checks --noverify setvcp 10 20' "$call_log" >/dev/null || \
  fail "external percentage is converted to the monitor VCP range"
pass "external percentage is converted to the monitor VCP range"

get_count=$(grep -c ' getvcp 10 ' "$call_log")
run_brightness --no-osd --monitor DP-1 30%
(( $(grep -c ' getvcp 10 ' "$call_log") == get_count )) || \
  fail "absolute external brightness reuses the cached VCP range"
grep -F 'ddcutil --bus 7 --skip-ddc-checks --noverify setvcp 10 24' "$call_log" >/dev/null || \
  fail "absolute external brightness skips write verification"
pass "absolute external brightness reuses the cached VCP range"

brightness=$(run_brightness --monitor eDP-1)
[[ $brightness == "40" ]] || fail "internal monitor uses the kernel backlight" "actual: $brightness"
grep -F 'brightnessctl -d mock_backlight -m' "$call_log" >/dev/null || \
  fail "internal monitor queries brightnessctl"
pass "internal monitor uses the kernel backlight"

# With no --monitor the focused one is the subject.
set_monitors '[{"name":"DP-1","make":"HPN","model":"OMEN X 25f","focused":true,"dpms":null,"x":0,"y":0,"width":1920,"height":1080,"scale":1}]'
brightness=$(run_brightness)
[[ $brightness == "50" ]] || fail "brightness follows the focused external monitor" "actual: $brightness"
pass "brightness follows the focused external monitor"
set_monitors '[{"name":"eDP-1","make":"Unknown","model":"Unknown","focused":true,"dpms":null,"x":0,"y":0,"width":1920,"height":1080,"scale":1}]'

detect_count=$(grep -c ' detect --brief' "$call_log")
if DDC_CONNECTOR=DP-1 run_brightness --monitor DP-2 >/dev/null 2>&1; then
  fail "unsupported external monitor has no brightness backend"
fi
if DDC_CONNECTOR=DP-1 run_brightness --monitor DP-2 >/dev/null 2>&1; then
  fail "cached unsupported external monitor has no brightness backend"
fi
(( $(grep -c ' detect --brief' "$call_log") == detect_count + 1 )) || \
  fail "unsupported external monitor detection is temporarily cached"
pass "unsupported external monitor has no brightness backend"

rm -f "$runtime_dir/strapd-brightness-display-ddc/DP-1.bus"
detect_count=$(grep -c ' detect --brief' "$call_log")
if DDC_READ_FAIL=1 run_brightness --monitor DP-1 >/dev/null 2>&1; then
  fail "transient DDC read failure is reported"
fi
(( $(grep -c ' detect --brief' "$call_log") == detect_count + 1 )) || \
  fail "transient DDC read failure is not retried immediately"
brightness=$(run_brightness --monitor DP-1)
[[ $brightness == "50" ]] || fail "transient DDC read failure is retried on the next invocation" "actual: $brightness"
(( $(grep -c ' detect --brief' "$call_log") == detect_count + 2 )) || \
  fail "transient DDC read failure does not create a negative cache entry"
pass "transient DDC read failure is retried on the next invocation"

printf '7 80 0\n' >"$runtime_dir/strapd-brightness-display-ddc/DP-1.bus"
get_count=$(grep -c ' getvcp 10 ' "$call_log")
DDC_MAXIMUM=100 run_brightness --no-osd --monitor DP-1 50%
(( $(grep -c ' getvcp 10 ' "$call_log") == get_count + 1 )) || \
  fail "expired external brightness range is refreshed"
grep -F 'ddcutil --bus 7 --skip-ddc-checks --noverify setvcp 10 50' "$call_log" >/dev/null || \
  fail "expired external brightness range uses the refreshed maximum"
pass "expired external brightness range is refreshed"

rm -f "$runtime_dir/strapd-brightness-display-ddc/DP-1.bus"
DDC_CURRENT=4 DDC_MAXIMUM=100 run_brightness --no-osd --monitor DP-1 +5%
grep -F 'ddcutil --bus 7 --skip-ddc-checks --noverify setvcp 10 5' "$call_log" >/dev/null || \
  fail "external low brightness writes the one-percent target"
pass "external low brightness uses a one-percent step"

# Apple's Studio Display and XDR speak their own HID protocol, not DDC, so they
# have to be recognised by make and model before the DDC path claims them.
set_monitors '[
  {"name":"DP-1","make":"HPN","model":"OMEN X 25f","focused":true,"dpms":null,"x":0,"y":0,"width":1920,"height":1080,"scale":1},
  {"name":"DP-2","make":"Apple Computer Inc","model":"StudioDisplay","focused":false,"dpms":null,"x":1920,"y":0,"width":5120,"height":2880,"scale":2}
]'

: >"$call_log"
run_brightness --no-osd --monitor DP-2 50%
grep -F 'apple --no-osd 50%' "$call_log" >/dev/null ||
  fail "a named Apple display is recognised independently of focus" "got: $(cat "$call_log")"
pass "a named Apple display is recognised independently of focus"

: >"$call_log"
run_brightness --no-osd 50% || true
if grep -q '^apple' "$call_log"; then
  fail "the focused non-Apple display does not take the Apple path" "got: $(cat "$call_log")"
fi
pass "the focused non-Apple display does not take the Apple path"

# mango reports no make or model, so every monitor there looks generic. An Apple
# display on mango must fall through rather than crash on a null.
set_monitors '[{"name":"DP-2","make":null,"model":null,"focused":true,"dpms":null,"x":0,"y":0,"width":5120,"height":2880,"scale":2}]'
: >"$call_log"
run_brightness --no-osd 50% || true
if grep -q '^apple' "$call_log"; then
  fail "a monitor with no make reported is not guessed to be Apple" "got: $(cat "$call_log")"
fi
pass "a compositor that reports no make falls through the Apple check"

# off and on are the compositor's business, not brightnessctl's.
set_monitors '[{"name":"eDP-1","make":"Unknown","model":"Unknown","focused":true,"dpms":null,"x":0,"y":0,"width":1920,"height":1080,"scale":1}]'
: >"$call_log"
run_brightness off
run_brightness on
[[ $(cat "$call_log") == "display-power off
display-power on" ]] ||
  fail "off and on go to the compositor" "got: $(cat "$call_log")"
pass "off and on go to the compositor, not the backlight"
