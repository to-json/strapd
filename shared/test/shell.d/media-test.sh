#!/bin/bash
#
# The media keys. The table spells the verb the way upstream's shell IPC did,
# "playPause", and playerctl spells it "play-pause". Everything here is about
# that seam, plus the one behaviour a media key has that a normal command does
# not: pressing it with nothing playing is completely ordinary.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

STUB_BIN="$test_tmp/bin"
mkdir -p "$STUB_BIN"

cat >"$STUB_BIN/playerctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >"$STUB_DIR/playerctl.args"
exit "${PLAYERCTL_EXIT:-0}"
STUB
chmod +x "$STUB_BIN/playerctl"

export STUB_DIR="$test_tmp"

media() {
  rm -f "$test_tmp/playerctl.args"
  env PATH="$STUB_BIN:$ROOT/bin:$PATH" STUB_DIR="$test_tmp" \
    PLAYERCTL_EXIT="${PLAYERCTL_EXIT:-0}" \
    "$ROOT/bin/strapd-media" "$@"
}

sent() { cat "$test_tmp/playerctl.args" 2>/dev/null; }

media playPause || fail "the bound verb works" "exited $?"
[[ $(sent) == "play-pause" ]] ||
  fail "playPause reaches playerctl as play-pause" "got: $(sent)"
pass "playPause reaches playerctl as play-pause"

for spelling in play-pause toggle PLAYPAUSE; do
  media "$spelling"
  [[ $(sent) == "play-pause" ]] ||
    fail "$spelling is the same key" "got: $(sent)"
done
pass "the spellings a person would type mean the same thing"

for pair in "next:next" "forward:next" "previous:previous" "prev:previous" \
            "back:previous" "play:play" "pause:pause" "stop:stop"; do
  media "${pair%%:*}"
  [[ $(sent) == "${pair##*:}" ]] ||
    fail "${pair%%:*} is ${pair##*:}" "got: $(sent)"
done
pass "every verb maps to the playerctl command it names"

# playerctl exits 1 with "No players found". The key is on the keyboard whether
# or not anything is running, so reporting an error would make an ordinary press
# look like a broken one.
PLAYERCTL_EXIT=1 media playPause ||
  fail "pressing a media key with nothing playing is not an error" "exited $?"
pass "pressing a media key with nothing playing is not an error"

for bad in "" "rewind" "playPause next"; do
  # shellcheck disable=SC2086
  output=$(media $bad 2>&1)
  status=$?
  (( status == 2 )) || fail "a verb it does not know is a usage error" "'$bad' exited $status"
  [[ $output == *"Usage:"* ]] || fail "a bad verb says how to call it" "got: $output"
done
pass "no verb, an unknown verb, or two verbs is a usage error"

rm -f "$STUB_BIN/playerctl"
cat >"$STUB_BIN/strapd-cmd-present" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$STUB_BIN/strapd-cmd-present"
output=$(media playPause 2>&1)
status=$?
(( status == 2 )) || fail "a missing playerctl is its own exit status" "exited $status"
[[ $output == *"playerctl is not installed"* ]] ||
  fail "a missing playerctl says so" "got: $output"
pass "a missing playerctl is its own exit status, and says so"
