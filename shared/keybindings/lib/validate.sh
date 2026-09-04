#!/bin/bash
#
# Validates keybinding JSON against the four rules in keybindings/schema.md.
# All four are checked in one pass and every violation reported: a caller fixing
# their TOML should see everything wrong at once.
#
# Meant to be sourced, not executed directly.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source keybindings/lib/validate.sh from another script; do not run it directly" >&2
  exit 1
fi

# validate_actions <json> <backend...>
#
# The backend list is a caller-supplied parameter rather than a constant baked
# into the jq filter, so a later phase can pass more without editing this file.
#
# On success: exits 0 and prints <json> back out unchanged, matching
# expand_repeats's calling convention so a caller can chain the pipeline by
# reassigning $json from each stage's stdout.
#
# On failure: exits 1, prints nothing on stdout, and prints every violation
# found to stderr, one per line, naming the action id and the rule it broke.
validate_actions() {
  local json="$1"
  shift
  local backends=("$@")

  if (( ${#backends[@]} == 0 )); then
    echo "validate_actions: at least one backend must be given" >&2
    return 1
  fi

  # Single jq pass building an array of {id, rule, detail}: one branch for rule
  # 1 (duplicate ids, across the whole array) concatenated with one for rules
  # 2-4 (per action/backend pair).
  local violations
  violations=$(jq -c --args '
    ($ARGS.positional) as $backends
    | (
        .action
        | group_by(.id)
        | map(select(length > 1))
        | map({
            id: .[0].id,
            rule: "rule1-duplicate-id",
            detail: "id used by \(length) actions after repeat expansion (must be unique)"
          })
      ) as $rule1
    | [
        .action[] as $a
        | $backends[] as $b
        | if ($a | has($b) | not) then
            {id: $a.id, rule: "rule2-missing-backend-table", detail: "missing [action.\($b)] table"}
          else
            ($a[$b]) as $tbl
            | ($tbl | has("dispatch")) as $has_dispatch
            | ($tbl | has("unsupported")) as $has_unsupported
            | if ($has_dispatch and $has_unsupported) then
                {id: $a.id, rule: "rule3-dispatch-and-unsupported", detail: "[action.\($b)] sets both dispatch and unsupported; exactly one is required"}
              elif (($has_dispatch or $has_unsupported) | not) then
                {id: $a.id, rule: "rule3-neither-dispatch-nor-unsupported", detail: "[action.\($b)] sets neither dispatch nor unsupported; exactly one is required"}
              elif $has_unsupported and (($tbl.reason // "") | length == 0) then
                {id: $a.id, rule: "rule4-unsupported-missing-reason", detail: "[action.\($b)] sets unsupported=true without a non-empty reason"}
              else
                empty
              end
          end
      ] as $rule234
    | ($rule1 + $rule234)
  ' -- "${backends[@]}" <<<"$json") || { echo "validate_actions: jq failed while checking rules" >&2; return 1; }

  local count
  count=$(jq 'length' <<<"$violations")

  if (( count > 0 )); then
    jq -r '.[] | "id=\(.id) rule=\(.rule): \(.detail)"' <<<"$violations" >&2
    return 1
  fi

  printf '%s\n' "$json"
}
