#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# tesseract is real here for the same reason zbarimg is in capture-qr-test.sh:
# the flags are the part worth checking, and a fixture would check none of them.
require_command tesseract
require_command magick

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
log="$test_tmp/log"
clip="$test_tmp/clipboard"
mkdir -p "$stub_bin"

# The freeze is a real background process, so "the freeze was released" can be
# checked by looking for it rather than by trusting a stub.
cat >"$stub_bin/strapd-capture-region" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEXT_TEST_LOG"
sleep 30 >/dev/null 2>&1 &
printf '%s\n' "$!" >"$TEXT_TEST_FREEZE_PID"
printf '%s\n' "$!"
cat "$TEXT_TEST_SELECTION"
SH

cat >"$stub_bin/grim" <<'SH'
#!/bin/bash
cat "$TEXT_TEST_IMAGE"
SH

cat >"$stub_bin/wl-copy" <<'SH'
#!/bin/bash
printf 'wl-copy %s\n' "$*" >>"$TEXT_TEST_LOG"
cat >"$TEXT_TEST_CLIP"
SH

cat >"$stub_bin/strapd-notification-send" <<'SH'
#!/bin/bash
printf 'notify %s\n' "$*" >>"$TEXT_TEST_LOG"
SH

chmod +x "$stub_bin"/*

printf '0,0 400x100\n' >"$test_tmp/selection"

run() {
  TEXT_TEST_LOG="$log" \
    TEXT_TEST_CLIP="$clip" \
    TEXT_TEST_IMAGE="$test_tmp/image.png" \
    TEXT_TEST_SELECTION="$test_tmp/selection" \
    TEXT_TEST_FREEZE_PID="$test_tmp/freeze-pid" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/strapd-capture-text" "$@"
}

# --psm 6 tells tesseract to read a uniform block of text, which is what a
# dragged-out rectangle of a terminal or a web page is.
magick -size 640x120 xc:white -fill black -pointsize 48 \
  -annotate +20+80 'strapd capture text' "$test_tmp/image.png"

: >"$log"
: >"$clip"
run

grep -qi 'strapd capture text' "$clip" ||
  fail "the recognised text lands on the clipboard" "$(<"$clip")"
pass "the recognised text lands on the clipboard"

grep -q 'region --keep-freeze' "$log" ||
  fail "the picker is strapd-capture-region, holding the freeze" "$(cat "$log")"
pass "the picker is strapd-capture-region, holding the freeze"

freeze_pid=$(<"$test_tmp/freeze-pid")
kill -0 "$freeze_pid" 2>/dev/null &&
  fail "the freeze is released on the way out" "pid $freeze_pid is still running"
pass "the freeze is released on the way out"

# Blank paper reads as nothing, and nothing is not something to put on the
# clipboard over whatever was already there.
: >"$log"
: >"$clip"
magick -size 640x120 xc:white "$test_tmp/image.png"
status=0
run || status=$?

(( status == 1 )) || fail "a region with no text fails" "exited $status"
[[ -z $(<"$clip") ]] || fail "a region with no text leaves the clipboard alone" "$(<"$clip")"
pass "a region with no text fails without touching the clipboard"

: >"$log"
: >"$clip"
: >"$test_tmp/selection"
status=0
run || status=$?
(( status == 0 )) || fail "a cancelled picker exits clean" "exited $status"
grep -q 'wl-copy' "$log" && fail "a cancelled picker copies nothing" "$(cat "$log")"
pass "a cancelled picker exits clean and copies nothing"
