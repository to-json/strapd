#!/bin/bash
#
# Expands `repeat`-bearing actions in keybinding JSON into N concrete actions,
# one per value in the repeat range. Non-repeat actions pass through unchanged.
#
# Meant to be sourced, not executed directly.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source keybindings/lib/repeat-expand.sh from another script; do not run it directly" >&2
  exit 1
fi

# expand_repeats <json>
#
# Every action with a `repeat = { var = "n", range = [start, end] }` table is
# replaced by one action per value in the inclusive range, with `{n}`
# substituted -- as a literal string replace, not a numeric operation -- into
# every string in that action, whatever backends happen to be present.
expand_repeats() {
  local json="$1"

  jq '
    def substitute_n($nstr):
      walk(if type == "string" then gsub("\\{n\\}"; $nstr) else . end);

    .action |= (
      map(
        if has("repeat") then
          (.repeat.range[0]) as $start
          | (.repeat.range[1]) as $end
          | del(.repeat) as $base
          | [range($start; $end + 1) as $n | ($base | substitute_n($n | tostring))]
        else
          [.]
        end
      ) | flatten(1)
    )
  ' <<<"$json"
}
