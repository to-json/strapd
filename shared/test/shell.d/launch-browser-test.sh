#!/bin/bash
#
# Ported from upstream with the Hyprland-shaped parts replaced: the focus call is
# strapd-wm-focus-window, given a bare name rather than upstream's ^...$, because
# the shim anchors on word boundaries itself.
#
# The decision that is easy to get backwards: opening a URL follows the browser
# to wherever it already is, and opening a bare window does not move anything.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home/.local/share/applications"

cat >"$test_home/.local/share/applications/chromium.desktop" <<'EOF'
[Desktop Entry]
Exec=chromium %U
EOF

cat >"$mock_bin/xdg-settings" <<'SH'
#!/bin/bash
[[ -z ${BROWSER:-} ]] || printf '%s\n' "$BROWSER" >"$STRAPD_TEST_XDG_SETTINGS_BROWSER"
[[ ${STRAPD_TEST_XDG_SETTINGS_EMPTY:-0} == "1" ]] || echo chromium.desktop
SH
cat >"$mock_bin/xdg-mime" <<'SH'
#!/bin/bash
if [[ $* == "query default x-scheme-handler/https" ]]; then
  echo chromium.desktop
fi
SH
cat >"$mock_bin/chromium" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/systemd-run" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$STRAPD_TEST_BROWSER_LAUNCH"
SH
cat >"$mock_bin/strapd-wm-focus-window" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >"$STRAPD_TEST_BROWSER_FOCUS"
SH
chmod +x "$mock_bin"/*

launch_log="$test_tmp/launch"
focus_log="$test_tmp/focus"
xdg_settings_browser="$test_tmp/xdg-settings-browser"

launch() {
  HOME="$test_home" PATH="$mock_bin:$PATH" \
    STRAPD_TEST_BROWSER_LAUNCH="$launch_log" STRAPD_TEST_BROWSER_FOCUS="$focus_log" \
    STRAPD_TEST_XDG_SETTINGS_EMPTY="${STRAPD_TEST_XDG_SETTINGS_EMPTY:-0}" \
    STRAPD_TEST_XDG_SETTINGS_BROWSER="$xdg_settings_browser" \
    bash "$ROOT/bin/strapd-launch-browser" "$@"
}

launch
[[ ! -e $focus_log ]] || fail "browser launcher leaves a new window on the current workspace"

launch --private
[[ ! -e $focus_log ]] || fail "private browser launcher leaves a new window on the current workspace"
pass "opening a browser window moves nothing"

launch "https://example.test/authorize"
grep -F 'https://example.test/authorize' "$launch_log" >/dev/null ||
  fail "browser launcher passes through the URL"
grep -Fx 'chromium' "$focus_log" >/dev/null ||
  fail "browser launcher focuses the default browser window" "got: $(cat "$focus_log")"
pass "opening a URL follows the browser to the window it opened in"

rm -f "$focus_log" "$xdg_settings_browser"

# BROWSER points at this script on a strapd session, so asking xdg-settings for
# the default browser without unsetting it answers "itself" and loops.
STRAPD_TEST_XDG_SETTINGS_EMPTY=1 BROWSER=strapd-launch-browser \
  launch "https://example.test/fallback"

grep -F 'https://example.test/fallback' "$launch_log" >/dev/null ||
  fail "browser launcher falls back to the HTTPS handler when xdg-settings is empty"
[[ ! -e $xdg_settings_browser ]] ||
  fail "browser launcher unsets BROWSER before reading xdg-settings"
grep -Fx 'chromium' "$focus_log" >/dev/null ||
  fail "browser launcher focuses the browser resolved from the HTTPS handler"
pass "an empty xdg-settings falls back to the HTTPS handler, with BROWSER unset"
