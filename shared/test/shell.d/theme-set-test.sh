#!/bin/bash
#
# Applying a theme. The half worth watching is the boundary a theme installed
# from a git repo does not cross: that directory is a stranger's, and a theme is
# colour, so anything in one that runs code is left on the floor.
#
# Everything runs headless. The post-theme commands retint running applications,
# which is a live session's business.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command flock

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

STUB_BIN="$test_tmp/bin"
mkdir -p "$STUB_BIN"

# Every command strapd-theme-set fans out to at the end, recorded rather than
# run. Stubbed by name, so a command that grows a new caller shows up here as a
# missing stub rather than a real retint in the test's session.
for command in \
  strapd-restart-terminal strapd-restart-btop strapd-restart-opencode \
  strapd-restart-helix strapd-theme-set-foot strapd-theme-set-tmux \
  strapd-theme-set-gnome strapd-theme-set-pi strapd-theme-set-claude \
  strapd-theme-set-browser strapd-theme-set-vscode strapd-theme-set-obsidian \
  strapd-theme-set-keyboard strapd-theme-switcher strapd-theme-bg-cache; do
  cat >"$STUB_BIN/$command" <<'STUB'
#!/bin/bash
printf '%s\n' "$(basename "$0")" >>"$STRAPD_THEME_TEST_LOG"
STUB
done
chmod +x "$STUB_BIN"/*

export STRAPD_THEME_TEST_LOG="$test_tmp/post.log"

home="$test_tmp/home"

set_theme() {
  rm -rf "$home"
  mkdir -p "$home/.local/state/strapd/current" "$home/.config/strapd/themes"
  : >"$STRAPD_THEME_TEST_LOG"
  seed_home "$home"
  run_theme_set "$@"
}

# Overridden per case; most cases want a plain home.
seed_home() { :; }

run_theme_set() {
  env HOME="$home" \
    STRAPD_PATH="$ROOT" \
    XDG_RUNTIME_DIR="$test_tmp" \
    STRAPD_THEME_TEST_LOG="$STRAPD_THEME_TEST_LOG" \
    PATH="$STUB_BIN:$ROOT/bin:$PATH" \
    "$ROOT/bin/strapd-theme-set" "$@"
}

current="$home/.local/state/strapd/current"

for bad in "../etc" "a/b" ".hidden"; do
  output=$(set_theme "$bad" 2>&1)
  status=$?
  (( status != 0 )) || fail "a theme name that is a path is refused" "accepted: $bad"
  [[ $output == *"Invalid theme name"* || $output == *"does not exist"* ]] ||
    fail "a theme name that is a path is refused" "$bad said: $output"
done
pass "a theme name that is a path is refused"

output=$(set_theme "no-such-theme" 2>&1)
(( $? != 0 )) || fail "an unknown theme is refused"
[[ $output == *"does not exist"* ]] || fail "an unknown theme says so" "got: $output"
pass "an unknown theme is refused, and says so"

STRAPD_THEME_HEADLESS=1 set_theme "Everforest" >/dev/null 2>&1 ||
  fail "a shipped theme applies"

# Display name in, directory name out.
[[ $(cat "$current/theme.name") == everforest ]] ||
  fail "the theme name is normalized" "got: $(cat "$current/theme.name" 2>&1)"
pass "the theme name is normalized"

[[ -f $current/theme/colors.toml ]] ||
  fail "the theme's palette is staged" "$(ls "$current/theme" 2>&1)"
pass "the theme's palette is staged"

# The generated file whose absence every foot window used to log.
[[ -f $current/theme/foot.ini ]] ||
  fail "the templates are rendered into the current theme" "$(ls "$current/theme" 2>&1)"
# Rendered, not copied: an unsubstituted {{ token }} is what a template that
# never saw a palette leaves behind, and foot would take it literally.
grep -q '{{' "$current/theme/foot.ini" &&
  fail "the rendered template has no placeholders left" "$(cat "$current/theme/foot.ini")"
grep -qi 'd3c6aa' "$current/theme/foot.ini" ||
  fail "the rendered template carries the theme's colors" "$(cat "$current/theme/foot.ini")"
pass "the templates are rendered into the current theme"

# Staging is atomic: next-theme is built, then moved. Finding one left behind
# means a run stopped halfway.
[[ ! -e $current/next-theme ]] ||
  fail "the staging directory does not survive a successful run"
pass "the staging directory does not survive a successful run"

[[ -L $current/background && -f $current/background ]] ||
  fail "a background is chosen" "$(readlink "$current/background" 2>&1)"
pass "a background is chosen"

[[ ! -s $STRAPD_THEME_TEST_LOG ]] ||
  fail "headless retints nothing" "$(cat "$STRAPD_THEME_TEST_LOG")"
pass "headless retints nothing"

seed_home() {
  mkdir -p "$1/.config/strapd/themes/everforest"
  printf 'mine\n' >"$1/.config/strapd/themes/everforest/icons.theme"
}
STRAPD_THEME_HEADLESS=1 set_theme "Everforest" >/dev/null 2>&1 ||
  fail "a user theme applies"
[[ $(cat "$current/theme/icons.theme") == mine ]] ||
  fail "a user's own theme overlays the shipped one" "$(cat "$current/theme/icons.theme")"
pass "a user's own theme overlays the shipped one"

# The .git directory is the whole distinction: `strapd theme install` clones
# into this path, so one that has it came from somewhere else.
seed_home() {
  local theme="$1/.config/strapd/themes/everforest"
  mkdir -p "$theme/.git"
  printf 'os.execute("touch %s/pwned")\n' "$test_tmp" >"$theme/neovim.lua"
  printf 'font=comic sans\n' >"$theme/foot.ini"
  printf '{"extension":"anything"}\n' >"$theme/vscode.json"
  printf 'kept\n' >"$theme/icons.theme"
}
output=$(STRAPD_THEME_HEADLESS=1 set_theme "Everforest" 2>&1)

[[ $(cat "$current/theme/icons.theme") == kept ]] ||
  fail "colour from an installed theme is still kept" "$(cat "$current/theme/icons.theme")"
pass "colour from an installed theme is still kept"

# Each of these runs code, and is therefore the shipped theme's copy or nothing
# at all, never the repo's.
grep -q 'os.execute' "$current/theme/neovim.lua" 2>/dev/null &&
  fail "an installed theme cannot supply Lua" "$(cat "$current/theme/neovim.lua")"
grep -q 'comic sans' "$current/theme/foot.ini" 2>/dev/null &&
  fail "an installed theme cannot supply a terminal config" "$(cat "$current/theme/foot.ini")"
grep -q 'anything' "$current/theme/vscode.json" 2>/dev/null &&
  fail "an installed theme cannot supply vscode.json" "$(cat "$current/theme/vscode.json")"
pass "an installed theme supplies no file that runs code"

[[ $output == *"Ignored in"* ]] ||
  fail "the files left on the floor are named" "got: $output"
pass "the files left on the floor are named"

# Somebody working on a theme symlinks their checkout in. That is their own
# directory however it got there, so the deny list does not apply.
seed_home() {
  local source="$test_tmp/my-theme"
  mkdir -p "$source"
  printf 'font=mine\n' >"$source/foot.ini"
  ln -snf "$source" "$1/.config/strapd/themes/everforest"
}
STRAPD_THEME_HEADLESS=1 set_theme "Everforest" >/dev/null 2>&1
[[ $(cat "$current/theme/foot.ini") == "font=mine" ]] ||
  fail "a symlinked theme is the user's own" "$(cat "$current/theme/foot.ini")"
pass "a symlinked theme is the user's own"

# Everforest ships one background, so the rotation only has somewhere to go once
# the user has added their own.
seed_home() {
  mkdir -p "$1/.config/strapd/backgrounds/everforest"
  : >"$1/.config/strapd/backgrounds/everforest/2-mine.png"
}
STRAPD_THEME_HEADLESS=1 set_theme "Everforest" >/dev/null 2>&1
first=$(readlink "$current/background")
STRAPD_THEME_HEADLESS=1 run_theme_set "Everforest" >/dev/null 2>&1
second=$(readlink "$current/background")
[[ $first != "$second" ]] ||
  fail "applying the same theme again advances the background" "stayed on $first"
pass "applying the same theme again advances the background"

# strapd-theme-refresh re-renders templates after a font or template changes.
# Advancing the wallpaper is not what it was asked to do.
STRAPD_THEME_SKIP_BACKGROUND=1 run_theme_set "Everforest" >/dev/null 2>&1
[[ $(readlink "$current/background") == "$second" ]] ||
  fail "--skip-background leaves the background where it was" \
    "moved from $second to $(readlink "$current/background")"
pass "STRAPD_THEME_SKIP_BACKGROUND leaves the background where it was"

seed_home() { :; }
set_theme "Everforest" >/dev/null 2>&1
for command in strapd-theme-set-foot strapd-restart-btop strapd-theme-set-keyboard; do
  grep -qx "$command" "$STRAPD_THEME_TEST_LOG" ||
    fail "a live theme change retints running applications" \
      "$command was not called; log: $(cat "$STRAPD_THEME_TEST_LOG")"
done
pass "a live theme change retints running applications"
