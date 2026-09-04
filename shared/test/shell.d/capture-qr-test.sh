#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# zbarimg and qrencode are both real here. The interesting half is the zbarimg
# invocation, specifically `-Sdisable -Sqrcode.enable`, which a fixture of its
# output could not check at all.
require_command zbarimg
require_command qrencode

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
printf '%s\n' "$*" >>"$QR_TEST_LOG"
sleep 30 >/dev/null 2>&1 &
printf '%s\n' "$!" >"$QR_TEST_FREEZE_PID"
printf '%s\n' "$!"
cat "$QR_TEST_SELECTION"
SH

# grim hands back whatever image the case put in front of it, so the geometry
# never has to be real.
cat >"$stub_bin/grim" <<'SH'
#!/bin/bash
cat "$QR_TEST_IMAGE"
SH

cat >"$stub_bin/wl-copy" <<'SH'
#!/bin/bash
printf 'wl-copy %s\n' "$*" >>"$QR_TEST_LOG"
cat >"$QR_TEST_CLIP"
SH

cat >"$stub_bin/strapd-notification-send" <<'SH'
#!/bin/bash
printf 'notify %s\n' "$*" >>"$QR_TEST_LOG"
SH

chmod +x "$stub_bin"/*

printf '0,0 200x200\n' >"$test_tmp/selection"

run() {
  QR_TEST_LOG="$log" \
    QR_TEST_CLIP="$clip" \
    QR_TEST_IMAGE="$test_tmp/image.png" \
    QR_TEST_SELECTION="$test_tmp/selection" \
    QR_TEST_FREEZE_PID="$test_tmp/freeze-pid" \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/strapd-capture-qr" "$@"
}

secret='otpauth://totp/strapd:test?secret=JBSWY3DPEHPK3PXP&issuer=strapd'
qrencode -o "$test_tmp/image.png" -s 6 -m 4 "$secret"

: >"$log"
: >"$clip"
run

[[ $(<"$clip") == "$secret" ]] || fail "a QR code lands on the clipboard decoded" "$(<"$clip")"
pass "a QR code lands on the clipboard decoded"

# A 2FA setup code is the ordinary case. Printing it or putting it in the
# notification body would put it in the journal and in notification history.
grep -q "$secret" <(grep -v '^wl-copy' "$log") &&
  fail "the decoded value stays out of the log and the notification" "$(cat "$log")"
pass "the decoded value stays out of the log and the notification"

grep -q 'wl-copy --sensitive' "$log" ||
  fail "the copy is marked sensitive so clipboard history skips it" "$(cat "$log")"
pass "the copy is marked sensitive so clipboard history skips it"

grep -q 'region --keep-freeze' "$log" ||
  fail "the picker is strapd-capture-region, holding the freeze" "$(cat "$log")"
pass "the picker is strapd-capture-region, holding the freeze"

freeze_pid=$(<"$test_tmp/freeze-pid")
kill -0 "$freeze_pid" 2>/dev/null &&
  fail "the freeze is released on the way out" "pid $freeze_pid is still running"
pass "the freeze is released on the way out"

# Dense screen content reads as a Code 39 or EAN barcode to a zbarimg with every
# symbology on, and that decode would take the clipboard.
: >"$log"
: >"$clip"
magick -size 300x120 xc:white -fill black \
  -draw "rectangle 10,10 14,110 rectangle 20,10 22,110 rectangle 28,10 34,110 rectangle 40,10 42,110 rectangle 48,10 54,110 rectangle 60,10 62,110 rectangle 68,10 74,110 rectangle 80,10 82,110" \
  "$test_tmp/image.png"
status=0
run || status=$?

(( status == 1 )) || fail "an image with no QR code fails" "exited $status"
[[ -z $(<"$clip") ]] || fail "an image with no QR code leaves the clipboard alone" "$(<"$clip")"
grep -q 'No QR code found' "$log" || fail "an image with no QR code says so" "$(cat "$log")"
pass "an image with no QR code fails without touching the clipboard"

# A cancelled picker is not an error: the user pressed escape.
: >"$log"
: >"$clip"
: >"$test_tmp/selection"
status=0
run || status=$?
(( status == 0 )) || fail "a cancelled picker exits clean" "exited $status"
grep -q 'wl-copy' "$log" && fail "a cancelled picker copies nothing" "$(cat "$log")"
pass "a cancelled picker exits clean and copies nothing"
