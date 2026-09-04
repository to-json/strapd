#!/bin/bash
#
# Every file each compositor's config tree ships is loaded by that tree, and
# every file it says it loads is there.
#
# Both halves are silent failures otherwise: a file nothing includes is settings
# that quietly do not apply, and an include naming a file that is not there is
# an error only to niri -- sway warns and carries on, mango exits 0.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The include and source lines, whatever the config language spells them.
# Comment lines are skipped: all three of these files talk about paths in them.
includes_in() {
  sed -n \
    -e '/^[[:space:]]*[#/]/d' \
    -e 's/^[[:space:]]*include[[:space:]][[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' \
    -e 's/^[[:space:]]*source=\(.*\)$/\1/p' \
    "$1"
}

for desktop in "$ROOT"/default/wayland-sessions/*.desktop; do
  exec_line=$(grep '^Exec=' "$desktop")
  compositor=${exec_line##* }

  for tree in default config; do
    dir="$ROOT/$tree/$compositor"

    [[ -d $dir ]] || fail "$tree/$compositor exists"

    # The one file the compositor is pointed at, which pulls in the rest.
    case "$tree" in
      default) loader=$(echo "$dir"/strapd.*) ;;
      config) loader=$(echo "$dir"/config*) ;;
    esac

    [[ -f $loader ]] ||
      fail "$tree/$compositor has one file that loads the others" "looked for $loader"
    pass "$tree/$compositor has one file that loads the others"

    unloaded=()
    for file in "$dir"/*; do
      [[ $file == "$loader" ]] && continue
      grep -q -- "$(basename "$file")" "$loader" || unloaded+=("$(basename "$file")")
    done

    (( ${#unloaded[@]} == 0 )) ||
      fail "every file in $tree/$compositor is loaded by $(basename "$loader")" \
           "$(printf '  %s\n' "${unloaded[@]}")"
    pass "every file in $tree/$compositor is loaded by $(basename "$loader")"

    missing=()
    while read -r target; do
      [[ -n $target ]] || continue
      # The tildes are literal text in a config file, not a path this test is
      # expanding; niri, sway and mango each expand their own.
      # shellcheck disable=SC2088
      case "$target" in
        # The installed tree, which is this checkout while the test runs.
        /usr/share/strapd/*) resolved="$ROOT/${target#/usr/share/strapd/}" ;;
        # Generated at login into ~/.local/state; nothing in the repo to check.
        "~/.local/state/"*) continue ;;
        "~/.config/$compositor/"*) resolved="$ROOT/config/$compositor/${target##*/}" ;;
        # Anywhere else absolute is the user's own business, not strapd's.
        /*|"~"*) continue ;;
        *) resolved="$dir/$target" ;;
      esac
      [[ -f $resolved ]] || missing+=("$target")
    done < <(includes_in "$loader")

    (( ${#missing[@]} == 0 )) ||
      fail "every file $(basename "$loader") loads is shipped" \
           "$(printf '  %s\n' "${missing[@]}")"
    pass "every file $(basename "$loader") loads is shipped"
  done

  # Window rules are what decides that a file picker floats and a game opens
  # full screen. A compositor that gained a session file without them looks like
  # a compositor bug rather than a missing file.
  grep -rqE 'window-rule|for_window|windowrule' "$ROOT/default/$compositor" ||
    fail "$compositor ships window rules" "nothing in default/$compositor sets a window rule"
  pass "$compositor ships window rules"
done
