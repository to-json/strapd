#!/bin/bash
#
# What happens to the pixels once the picker has named a rectangle: where the
# file lands, what reaches the clipboard, and who closes the screen freeze.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

STUB_BIN=$(mktemp -d)
trap 'rm -rf "$STUB_BIN"' EXIT

export PATH="$STUB_BIN:$ROOT/bin:$PATH"

# Mocked at its own boundary; capture-region-test.sh covers what it does.
cat >"$STUB_BIN/strapd-capture-region" <<'STUB'
#!/bin/bash
printf 'capture-region %s\n' "$*" >>"$ACTION_FILE"
printf '%s\n' "${FREEZE_PID_REPLY:-}"
printf '%s\n' "${SELECTION_REPLY:-}"
STUB

cat >"$STUB_BIN/grim" <<'STUB'
#!/bin/bash
printf 'grim %s\n' "$*" >>"$ACTION_FILE"
# The last argument is either a path to write or "-" for stdout.
if [[ ${!#} == "-" ]]; then
  printf 'PNGDATA\n'
else
  printf 'PNGDATA\n' >"${!#}"
fi
STUB

cat >"$STUB_BIN/wl-copy" <<'STUB'
#!/bin/bash
printf 'wl-copy %s <%s\n' "$*" "$(cat)" >>"$ACTION_FILE"
STUB

cat >"$STUB_BIN/strapd-notification-send" <<'STUB'
#!/bin/bash
printf 'notify %s\n' "$*" >>"$ACTION_FILE"
STUB

# pkill has to be harmless here: the real script calls it to cancel a picker
# that is already open, and a test must not go hunting the machine for slurp.
cat >"$STUB_BIN/pkill" <<'STUB'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$ACTION_FILE"
exit "${PKILL_STATUS:-1}"
STUB

chmod +x "$STUB_BIN"/*

ACTION_FILE="$STUB_BIN/actions.log"
HOME_DIR="$STUB_BIN/home"
mkdir -p "$HOME_DIR/Pictures"
export ACTION_FILE

OUT_FILE="$STUB_BIN/stdout"

# ${x-default}, not ${x:-default}: an empty reply is the cancelled pick, and a
# default that swallowed it would leave that case untested while passing.
shoot() {
  : >"$ACTION_FILE"
  HOME="$HOME_DIR" XDG_PICTURES_DIR="$HOME_DIR/Pictures" \
    FREEZE_PID_REPLY="${FREEZE_PID_REPLY-}" SELECTION_REPLY="${SELECTION_REPLY-100,100 400x300}" \
    PKILL_STATUS="${PKILL_STATUS-1}" \
    "$ROOT/bin/strapd-capture-screenshot" "$@" >"$OUT_FILE"
}

# The default: save, copy, and offer an edit.
shoot || fail "a screenshot is taken"
out=$(cat "$OUT_FILE")
[[ $out == "$HOME_DIR/Pictures/screenshot-"*.png ]] ||
  fail "the path of the saved file is printed" "got: $out"
grep -q "^capture-region smart --keep-freeze$" "$ACTION_FILE" ||
  fail "the default mode is smart, and the freeze is kept" "got: $(cat "$ACTION_FILE")"
grep -q "^grim -g 100,100 400x300 " "$ACTION_FILE" ||
  fail "grim is given the picked rectangle" "got: $(cat "$ACTION_FILE")"
grep -q "^wl-copy --type image/png <PNGDATA$" "$ACTION_FILE" ||
  fail "the image reaches the clipboard" "got: $(cat "$ACTION_FILE")"
grep -q "^notify Screenshot saved to clipboard and file" "$ACTION_FILE" ||
  fail "a notification offers the edit" "got: $(cat "$ACTION_FILE")"
pass "a screenshot is saved, copied, and offered for editing"

# copy leaves no file behind; save writes one and says nothing to anyone.
before=$(ls "$HOME_DIR/Pictures" | wc -l)
SELECTION_REPLY='0,0 100x100' shoot region copy || fail "copy-only succeeds"
(( $(ls "$HOME_DIR/Pictures" | wc -l) == before )) ||
  fail "copy-only writes no file" "the directory grew"
grep -q "^wl-copy --type image/png <PNGDATA$" "$ACTION_FILE" ||
  fail "copy-only still reaches the clipboard" "got: $(cat "$ACTION_FILE")"
pass "copy-only reaches the clipboard and writes no file"

SELECTION_REPLY='0,0 100x100' shoot region save || fail "save-only succeeds"
grep -q '^wl-copy' "$ACTION_FILE" && fail "save-only leaves the clipboard alone" "got: $(cat "$ACTION_FILE")"
grep -q '^notify' "$ACTION_FILE" && fail "save-only sends no notification" "got: $(cat "$ACTION_FILE")"
pass "save-only writes the file and touches nothing else"

# --editor is read from any position and does not reach the mode arguments.
SELECTION_REPLY='0,0 100x100' shoot --editor=gimp region || fail "an editor can be named first"
grep -q "^capture-region region --keep-freeze$" "$ACTION_FILE" ||
  fail "--editor is not mistaken for a mode" "got: $(cat "$ACTION_FILE")"
grep -q -- "--exec gimp " "$ACTION_FILE" ||
  fail "the named editor is what the notification offers" "got: $(cat "$ACTION_FILE")"
pass "--editor is read from any position and names the edit command"

# A cancelled pick writes nothing and is not an error.
before=$(ls "$HOME_DIR/Pictures" | wc -l)
SELECTION_REPLY='' shoot || fail "a cancelled pick is not an error"
(( $(ls "$HOME_DIR/Pictures" | wc -l) == before )) ||
  fail "a cancelled pick writes no file" "the directory grew"
grep -q '^grim' "$ACTION_FILE" && fail "a cancelled pick does not run grim" "got: $(cat "$ACTION_FILE")"
pass "a cancelled pick writes nothing and is not an error"

# A second press while the picker is open cancels it rather than stacking a
# second one, and only this user's, because pkill searches the whole process
# table and a machine can have two people logged in.
PKILL_STATUS=0 shoot || fail "a second press while picking is not an error"
[[ $(grep '^pkill ' "$ACTION_FILE") == "pkill -u $(id -u) slurp" ]] ||
  fail "a second press closes this user's open picker" "got: $(cat "$ACTION_FILE")"
grep -q '^capture-region' "$ACTION_FILE" && fail "a second press opens no new picker" "got: $(cat "$ACTION_FILE")"
pass "a second press closes the open picker instead of opening another"

# The screenshot directory is made if missing, and the user is told; one that
# silently goes nowhere is worse than a slow one.
rm -rf "$HOME_DIR/Pictures"
SELECTION_REPLY='0,0 100x100' shoot region save || fail "a missing screenshot directory is created"
[[ -d $HOME_DIR/Pictures ]] || fail "a missing screenshot directory is created" "still missing"
grep -q "^notify Created screenshot directory" "$ACTION_FILE" ||
  fail "creating the directory is announced" "got: $(cat "$ACTION_FILE")"
pass "a missing screenshot directory is created and announced"
