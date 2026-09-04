#!/bin/bash

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# `systemctl --user enable --now a.service b.service` is all-or-nothing: name
# one unit that is not installed and the whole call fails, taking the rest of
# first run with it. A unit can be deferred to a later phase while the script
# that enables it comes over now, so pin it here.
#
# A unit counts as shipped if the tree carries a file by that name, or if the
# script enabling it writes the unit itself first.
missing=()

while read -r script; do
  [[ -n $script ]] || continue

  # Line continuations first, so a multi-unit enable reads as one command.
  enabled=$(sed -e ':a' -e '/\\$/{N;s/\\\n//;ta' -e '}' "$script" |
    grep -oE 'systemctl[^|;&]*\benable\b[^|;&]*' |
    grep -oE '\bstrapd-[a-z0-9-]+\.(service|timer|socket|path)\b' | sort -u)

  while read -r unit; do
    [[ -n $unit ]] || continue
    find "$ROOT" -name "$unit" | grep -q . && continue
    grep -qF "$unit" <<<"$(grep -E '(>|tee)[[:space:]]*\S*'"$unit" "$script")" && continue
    missing+=("${script#"$ROOT"/}: $unit")
  done <<<"$enabled"
done < <(grep -rlE 'systemctl.*\benable\b' "$ROOT/install")

(( ${#missing[@]} == 0 )) ||
  fail "install/ only enables units the tree ships" "$(printf '%s\n' "${missing[@]}")"
pass "install/ only enables units the tree ships"
