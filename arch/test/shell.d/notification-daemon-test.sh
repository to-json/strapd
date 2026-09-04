#!/bin/bash
#
# Something has to be listening. strapd-notification-send calls Notify over the
# session bus and exits 0 whether or not anybody owns that name, which is how
# thirty-three commands came to be sending notifications into nothing. The
# command was never the problem; the missing half was a daemon.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

PACKAGES="$ROOT/install/strapd-base.packages"
UNITS="$ROOT/install/user/first-run/enable-user-units.sh"

grep -qx 'mako' "$PACKAGES" ||
  fail "a notification daemon is installed" "mako is not in $(basename "$PACKAGES")"
pass "a notification daemon is installed"

# Installed and not started is the same as not installed: mako's unit is
# Type=dbus and claims org.freedesktop.Notifications, so enabling it is what
# puts an owner on that name.
grep -q 'mako.service' "$UNITS" ||
  fail "the notification daemon is enabled at first run" "not in $(basename "$UNITS")"
pass "the notification daemon is enabled at first run"

# Everything that notifies goes through the one command, so a caller reaching
# for notify-send would bypass the argv-safety it exists for. bin-style-test.sh
# forbids it in bin/; install/ is the other half.
raw=$(grep -rlE '^[[:space:]]*[^#[:space:]].*\bnotify-send\b' "$ROOT/install" 2>/dev/null || true)
[[ -z $raw ]] || fail "install scripts notify through strapd-notification-send" "$raw"
pass "install scripts notify through strapd-notification-send"

# The daemon is spoken to by name, never by path, so any spec-compliant one can
# replace it -- which is the point, since Noctalia claims the same name later.
grep -q 'org.freedesktop.Notifications Notify' "$ROOT/bin/strapd-notification-send" ||
  fail "notifications go through the freedesktop interface"
# Comments stripped, because the file is allowed to *explain* which daemon is
# behind the name today; it is the code that must not depend on it.
code=$(grep -vE '^[[:space:]]*#' "$ROOT/bin/strapd-notification-send")
grep -qE '\b(mako|makoctl|dunst|dunstify|swaync|fnott)\b' <<<"$code" &&
  fail "the sender does not run the daemon it happens to be talking to" \
    "$(grep -nE '\b(mako|dunst|swaync|fnott)\b' <<<"$code")"
pass "the sender names the interface, not the daemon behind it"
