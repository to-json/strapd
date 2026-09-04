#!/bin/bash
#
# The menu key. There is no upstream behaviour to match -- upstream's tree lives
# in QML inside its shell -- only a file describing a tree and a command that has
# to walk it. The two ways that goes wrong are a route showing rows from another
# depth, and a picked label resolving to the wrong row.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

STUB_BIN="$test_tmp/bin"
mkdir -p "$STUB_BIN"

# Stands in for fuzzel: records the rows it was offered and picks MENU_PICK.
cat >"$STUB_BIN/strapd-menu-select" <<'STUB'
#!/bin/bash
printf '%s\n' "$1" >"$STUB_DIR/menu.prompt"
cat >"$STUB_DIR/menu.rows"
if [[ -n ${MENU_PICK:-} ]]; then
  printf '%s\n' "$MENU_PICK"
else
  exit 1
fi
STUB
chmod +x "$STUB_BIN/strapd-menu-select"

export STUB_DIR="$test_tmp"

menu() {
  env STRAPD_PATH="$ROOT" PATH="$STUB_BIN:$ROOT/bin:$PATH" STUB_DIR="$test_tmp" \
    MENU_PICK="${MENU_PICK:-}" \
    "$ROOT/bin/strapd-menu" "$@"
}

rows() { cat "$test_tmp/menu.rows" 2>/dev/null; }

TREE="$ROOT/default/menu/tree.tsv"

# A row is picked by its label and resolved by it, so two rows in one submenu
# that read the same are two rows one of which can never be chosen.
collisions=$(awk -F'\t' '
  !/^#/ && NF {
    id = $1
    parent = (index(id, ".") > 0) ? substr(id, 1, length(id) - length(gensub(/.*\./, "", 1, id)) - 1) : "root"
    key = parent "\t" $2
    if (seen[key]++) print parent ": " $2
  }' "$TREE")
[[ -z $collisions ]] ||
  fail "no two rows in one submenu share a label" "$collisions"
pass "no two rows in one submenu share a label"

# An action's command has to exist; a row that runs nothing is a menu entry
# that does nothing when picked.
missing=()
while IFS=$'\t' read -r id label action; do
  [[ -n $action ]] || continue
  command=${action%% *}
  [[ $command == strapd-* ]] || continue
  [[ -x $ROOT/bin/$command ]] || missing+=("$id: $command")
done < <(grep -v '^#' "$TREE" | grep -v '^$')
(( ${#missing[@]} == 0 )) ||
  fail "every row runs a command that exists" "$(printf '%s\n' "${missing[@]}")"
pass "every row runs a command that exists"

# A submenu with nothing under it is a row that opens an empty menu.
empty=()
while IFS=$'\t' read -r id label action; do
  [[ -z $action ]] || continue
  grep -q "^$id\." "$TREE" || empty+=("$id")
done < <(grep -v '^#' "$TREE" | grep -v '^$')
(( ${#empty[@]} == 0 )) ||
  fail "no submenu is empty" "$(printf '%s\n' "${empty[@]}")"
pass "no submenu is empty"

menu toggle root
[[ $(rows) == *"Apps"* && $(rows) == *"System"* ]] ||
  fail "the root menu shows the top-level rows" "$(rows)"

# The rows under a submenu belong to that submenu and not to the root: finding
# "Terminal" on the root menu would mean the dots were not being read as depth.
grep -qx 'Terminal' <<<"$(rows)" &&
  fail "the root menu does not show a submenu's rows" "$(rows)"
grep -qx '← Back' <<<"$(rows)" &&
  fail "the root menu has nothing to go back to" "$(rows)"
pass "the root menu shows the top-level rows and only those"

menu toggle apps
[[ $(rows) == *"Terminal"* && $(rows) == *"Files"* ]] ||
  fail "a submenu shows its own rows" "$(rows)"
grep -qx 'Apps' <<<"$(rows)" &&
  fail "a submenu does not show its own parent" "$(rows)"
grep -qx '← Back' <<<"$(rows)" ||
  fail "a submenu offers a way back" "$(rows)"
pass "a submenu shows its own rows, and a way back"

[[ $(cat "$test_tmp/menu.prompt") == "Apps" ]] ||
  fail "the menu is prompted with where it is" "$(cat "$test_tmp/menu.prompt")"
pass "the menu is prompted with where it is"

# A picked submenu opens it rather than running anything.
MENU_PICK="Apps" menu toggle root
[[ $(rows) == *"Terminal"* ]] ||
  fail "picking a submenu opens it" "$(rows)"
pass "picking a submenu opens it"

# Back from a submenu returns to the root, not to the submenu again.
MENU_PICK="← Back" menu toggle apps
[[ $(rows) == *"Apps"* && $(rows) != *"Terminal"* ]] ||
  fail "back from a submenu returns to the menu above it" "$(rows)"
pass "back from a submenu returns to the menu above it"

# strapd-launch-terminal is stubbed so the row's command is observable.
cat >"$STUB_BIN/strapd-launch-terminal" <<'STUB'
#!/bin/bash
printf 'launched\n' >"$STUB_DIR/ran"
STUB
chmod +x "$STUB_BIN/strapd-launch-terminal"
rm -f "$test_tmp/ran"
MENU_PICK="Terminal" menu toggle apps
[[ -f $test_tmp/ran ]] || fail "picking a row runs its command"
pass "picking a row runs its command"

# Escaping the menu is not an error; it is the most common thing to do with one.
MENU_PICK="" menu toggle root
status=$?
(( status != 0 )) || fail "a dismissed menu does not report success"
pass "a dismissed menu does not run anything"

menu summon system
[[ $(rows) == *"Lock"* ]] || fail "summon opens the same menu toggle does" "$(rows)"
pass "summon opens the same menu toggle does"

output=$(menu toggle nosuchroute 2>&1)
status=$?
(( status == 2 )) || fail "an unknown route is its own exit status" "exited $status"
[[ $output == *"no such route"* ]] || fail "an unknown route says so" "got: $output"
pass "an unknown route is its own exit status, and says so"

output=$(menu explode 2>&1)
status=$?
(( status == 2 )) || fail "an unknown verb is its own exit status" "exited $status"
pass "an unknown verb is its own exit status"

# actions.toml binds `strapd-menu toggle`, `... toggle apps` and `... toggle
# system`. A route renamed in the tree without the table noticing is a key that
# opens nothing. The claim is that the key opens a menu with something in it,
# not that something was picked from it: dismissing is a non-zero exit and has
# nothing to do with whether the route exists.
while read -r route; do
  rm -f "$test_tmp/menu.rows"
  menu toggle "$route" >/dev/null 2>&1
  [[ -s $test_tmp/menu.rows ]] ||
    fail "every route a keybinding opens has rows to show" "$route"
done < <(grep -oE 'strapd-menu toggle [a-z]+' "$ROOT/keybindings/actions.toml" |
  awk '{ print $3 }' | sort -u)
pass "every route a keybinding opens has rows to show"
