#!/bin/bash
#
# Putting the wallpaper on the screen. What is worth testing is mostly what it
# must not do: leave two swaybgs stacked after a theme switch, kill the one sway
# started for its own `output * bg` line, or leave the previous theme's
# wallpaper up when the new theme ships none.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"; pkill -f "$test_tmp/bin/swaybg" 2>/dev/null' EXIT

STUB_BIN="$test_tmp/bin"
mkdir -p "$STUB_BIN"

# Stays up, so "is the old one still running" is a question with an answer.
cat >"$STUB_BIN/swaybg" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_DIR/swaybg.calls"
sleep 300 &
child=$!
trap 'kill "$child" 2>/dev/null' TERM EXIT
wait "$child"
STUB
chmod +x "$STUB_BIN/swaybg"

export STUB_DIR="$test_tmp"

home="$test_tmp/home"
state="$home/.local/state/strapd/current"
mkdir -p "$state"

pidfile="$test_tmp/strapd-background.pid"

apply() {
  env HOME="$home" PATH="$STUB_BIN:$ROOT/bin:$PATH" STUB_DIR="$test_tmp" \
    XDG_RUNTIME_DIR="$test_tmp" WAYLAND_DISPLAY="${WAYLAND_DISPLAY-wayland-0}" \
    "$ROOT/bin/strapd-theme-bg-apply"
}

# pgrep -c prints 0 *and* exits 1 when it matches nothing, so the obvious
# `|| echo 0` yields two lines and every count after it is a syntax error.
running_backgrounds() {
  local count
  count=$(pgrep -fc "$STUB_BIN/swaybg" 2>/dev/null) || count=0
  printf '%s\n' "${count:-0}"
}
calls() { cat "$test_tmp/swaybg.calls" 2>/dev/null; }

# The background is started in the background, so it has not necessarily
# written its arguments by the time the starting command returned.
wait_for_call() {
  local waited
  for waited in $(seq 1 40); do
    [[ $(calls | wc -l) -ge $1 ]] && return 0
    sleep 0.1
  done
  return 1
}

apply || fail "no background chosen is not an error" "exited $?"
[[ -z $(calls) ]] || fail "nothing is drawn when nothing is chosen" "$(calls)"
pass "no background chosen draws nothing, and is not an error"

image="$test_tmp/first.png"
: >"$image"
ln -snf "$image" "$state/background"

apply || fail "a chosen background is drawn" "exited $?"
wait_for_call 1 || fail "the background records what it was asked to draw"
[[ $(calls) == *"--image $image"* ]] ||
  fail "the current background is the one drawn" "$(calls)"

# `fill`, so a wallpaper is cropped rather than distorted.
[[ $(calls) == *"--mode fill"* ]] || fail "the image is filled, not stretched" "$(calls)"
pass "the current background is drawn, filled"

[[ -s $pidfile ]] || fail "the drawing process is recorded"
(( $(running_backgrounds) == 1 )) || fail "one background is running" "$(running_backgrounds)"
pass "one background process is running, and recorded"

# The failure this prevents: every theme switch leaving another swaybg alive,
# stacked over the last.
second="$test_tmp/second.png"
: >"$second"
ln -snf "$second" "$state/background"
apply
wait_for_call 2 || fail "the replacement background records what it draws"

(( $(running_backgrounds) == 1 )) ||
  fail "switching replaces the background rather than stacking one on it" \
    "$(running_backgrounds) running"
[[ $(calls | tail -1) == *"--image $second"* ]] ||
  fail "the new background is the one drawn" "$(calls | tail -1)"
pass "switching replaces the background rather than stacking"

# Leaving the last one up would show the previous theme's wallpaper under the
# new theme's colours.
rm -f "$state/background"
apply
(( $(running_backgrounds) == 0 )) ||
  fail "a theme with no background leaves none on screen" "$(running_backgrounds) running"
pass "a theme with no background leaves none on screen"

# Sway starts one for its own `output * bg` line. Killing every swaybg would
# take the solid colour with it, so only the recorded pid is replaced.
"$STUB_BIN/swaybg" --someone-elses >/dev/null 2>&1 &
theirs=$!
ln -snf "$image" "$state/background"
apply
kill -0 "$theirs" 2>/dev/null || fail "another swaybg is left alone"
pass "a swaybg this did not start is left alone"
kill "$theirs" 2>/dev/null

# A pid file outlives a reboot and the number gets handed to somebody else.
# Killing it blind would kill whatever now holds it.
printf '%s\n' "$$" >"$pidfile"
apply || fail "a stale pid file is not an error" "exited $?"
kill -0 "$$" 2>/dev/null || fail "the test's own process survived"
pass "a pid that now belongs to something else is not killed"

# Noctalia owns the wallpaper while it is running, so a swaybg underneath would
# be a second thing painting the same pixels.
cat >"$STUB_BIN/noctalia" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_DIR/noctalia.calls"
STUB
chmod +x "$STUB_BIN/noctalia"

socket="$test_tmp/noctalia-wayland-0.sock"
# A socket, not a regular file: only the socket type tells a live instance from
# a leftover of the same name, which is exactly the shape being tested for.
python3 -c 'import socket, sys
s = socket.socket(socket.AF_UNIX)
s.bind(sys.argv[1])
s.listen(1)' "$socket"
[[ -S $socket ]] || fail "the test could not make a socket to stand in for the shell"

ln -snf "$image" "$state/background"
rm -f "$test_tmp/noctalia.calls"
before=$(running_backgrounds)
WAYLAND_DISPLAY=wayland-0 apply || fail "the shell path is not an error" "exited $?"

[[ $(cat "$test_tmp/noctalia.calls" 2>/dev/null) == "msg wallpaper-set $image" ]] ||
  fail "the shell is handed the wallpaper" "$(cat "$test_tmp/noctalia.calls" 2>/dev/null)"
pass "the running shell is handed the wallpaper"

(( $(running_backgrounds) <= before )) ||
  fail "no swaybg is started when the shell is drawing" "$(running_backgrounds) running"
pass "no swaybg is started when the shell is drawing"

# Installed but not running is the case that matters: handing the wallpaper to a
# shell that is not there would silently draw nothing.
rm -f "$socket"
rm -f "$test_tmp/noctalia.calls"
# Counted from where it stands, not from zero: earlier cases already drew, so
# `at least one call` would be satisfied before this ran and assert nothing.
drawn_before=$(calls | wc -l)
WAYLAND_DISPLAY=wayland-0 apply
[[ -z $(cat "$test_tmp/noctalia.calls" 2>/dev/null) ]] ||
  fail "a shell that is installed but not running is not asked" \
    "$(cat "$test_tmp/noctalia.calls")"
wait_for_call $((drawn_before + 1)) || fail "swaybg draws it instead"
pass "a shell that is installed but not running falls back to swaybg"

rm -f "$STUB_BIN/noctalia"

# The autostart runs this before much else exists, and a person may run it from
# a plain shell. Neither is an error.
# Its own record rather than the shared one: every apply above started a
# background process that writes asynchronously, so a file emptied here can
# still be written to afterwards.
fresh=$(mktemp -d)
env HOME="$home" PATH="$STUB_BIN:$ROOT/bin:$PATH" STUB_DIR="$fresh" \
  XDG_RUNTIME_DIR="$test_tmp" WAYLAND_DISPLAY="" \
  "$ROOT/bin/strapd-theme-bg-apply" ||
  fail "no session is not an error" "exited $?"
[[ ! -s $fresh/swaybg.calls ]] ||
  fail "nothing is drawn without a session" "$(cat "$fresh/swaybg.calls")"
rm -rf "$fresh"
pass "no session draws nothing, and is not an error"
