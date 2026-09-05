#!/bin/bash
#
# The greeter starts on the first session in its list, so what is in that list
# decides what a first boot lands on. This is the check that it only holds
# sessions whose compositor is actually installed -- the thing that made a fresh
# machine boot into MangoWC, which nothing could install, and stop there.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
fake_root="$test_tmp/strapd"
sessions_out="$test_tmp/wayland-sessions"
mkdir -p "$mock_bin" "$fake_root/default/wayland-sessions"

for wm in niri sway mango; do
  cat >"$fake_root/default/wayland-sessions/strapd-$wm.desktop" <<EOF
[Desktop Entry]
Name=strapd ($wm)
Exec=strapd-session $wm
TryExec=$wm
Type=Application
EOF
done

install_compositor() {
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$1"
  chmod +x "$mock_bin/$1"
}

run_refresh() {
  rm -rf "$sessions_out"
  env -i \
    PATH="$mock_bin:$ROOT/bin:/usr/bin:/bin" \
    STRAPD_PATH="$fake_root" \
    STRAPD_SESSIONS_DIR="$sessions_out" \
    bash "$ROOT/bin/strapd-refresh-sessions"
}

listed() {
  (cd "$sessions_out" 2>/dev/null && ls *.desktop 2>/dev/null | sort | tr '\n' ' ') || true
}

# --- only what is installed ------------------------------------------------

install_compositor sway
output=$(run_refresh 2>&1) || fail "a refresh with one compositor succeeds" "$output"

[[ $(listed) == "strapd-sway.desktop " ]] ||
  fail "only the installed compositor's session is offered" "listed: $(listed)"
pass "only installed compositors are offered"

[[ $output == *"strapd-mango"* && $output == *"not installed"* ]] ||
  fail "the sessions left out are named" "$output"
pass "the sessions left out are named"

# The greeter takes the first entry, so what matters is not just that mango is
# absent but that something startable is first.
first=$(cd "$sessions_out" && ls *.desktop | sort | head -1)
[[ $first == strapd-sway.desktop ]] ||
  fail "the session the greeter would start is one that can start" "first: $first"
pass "the first session offered is one that can start"

# --- a compositor built later comes back -----------------------------------

install_compositor niri
output=$(run_refresh 2>&1) || fail "a re-run succeeds" "$output"
[[ $(listed) == "strapd-niri.desktop strapd-sway.desktop " ]] ||
  fail "a compositor installed later is offered again" "listed: $(listed)"
pass "a compositor installed later is offered again on the next run"

# --- nothing installed at all ----------------------------------------------

# A greeter with an empty list offers the user no way in at all, which is worse
# than offering a session that then reports what is missing.
rm -f "$mock_bin/sway" "$mock_bin/niri"
output=$(run_refresh 2>&1) || fail "a refresh with no compositors succeeds" "$output"
[[ $(listed) == "strapd-mango.desktop strapd-niri.desktop strapd-sway.desktop " ]] ||
  fail "with no compositor installed every session is offered" "listed: $(listed)"
pass "with no compositor installed at all, every session is offered rather than none"
