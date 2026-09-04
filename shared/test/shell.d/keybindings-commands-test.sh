#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command yq
require_command jq

ACTIONS="$ROOT/keybindings/actions.toml"

# Every strapd-* command the keybinding table spawns, checked against bin/.
#
# actions.toml's header calls its unbuilt helpers a deliberate forward
# reference, but a paragraph of prose is not a check, and two bindings had
# already drifted past it: both spawned the generic `strapd-toggle <name>`,
# which wrote a file nothing reads. Both keys did nothing, silently.
#
# DEFERRED is empty, and that is the point. Add a name only when the phase that
# builds it is genuinely later than this one, and never without a reason beside
# it; a bare name is how the last two got in.
declare -A DEFERRED=()

json=$(yq -p toml -o json "$ACTIONS")

# One row per (action, backend, dispatch). Only spawning dispatches carry a
# command; a native one like `close-window` is the compositor's own verb.
rows=$(jq -r '
  .action[]
  | .id as $id
  | to_entries[]
  | select(.key | IN("niri", "sway", "mango"))
  | select(.value.dispatch != null)
  | [$id, .key, .value.dispatch]
  | @tsv' <<<"$json")

[[ -n $rows ]] || fail "actions.toml yields dispatches to check"

# niri quotes each argument separately, sway writes a plain command line, and
# mango puts the whole line after a comma.
spawned_argv() {
  local backend="$1" dispatch="$2"

  case "$backend" in
    niri)
      [[ $dispatch == spawn\ * ]] || return 1
      # Drop the verb, then take what is inside each pair of quotes.
      grep -oE '"[^"]*"' <<<"${dispatch#spawn }" | tr -d '"'
      ;;
    sway)
      [[ $dispatch == exec\ * ]] || return 1
      tr ' ' '\n' <<<"${dispatch#exec }"
      ;;
    mango)
      [[ $dispatch == spawn,* ]] || return 1
      tr ' ' '\n' <<<"${dispatch#spawn,}"
      ;;
  esac
}

missing=()
too_generic=()
declare -A per_action_command=()
divergent=()

while IFS=$'\t' read -r id backend dispatch; do
  mapfile -t argv < <(spawned_argv "$backend" "$dispatch" || true)
  (( ${#argv[@]} )) || continue
  command=${argv[0]}
  [[ $command == strapd-* ]] || continue

  # All three backends have to spawn the same command for one action, or the key
  # does different things depending on which compositor is running.
  if [[ -n ${per_action_command[$id]:-} && ${per_action_command[$id]} != "$command" ]]; then
    divergent+=("$id: ${per_action_command[$id]} vs $command ($backend)")
  fi
  per_action_command[$id]="$command"

  if [[ ! -x $ROOT/bin/$command && -z ${DEFERRED[$command]:-} ]]; then
    missing+=("$id ($backend): $command")
  fi

  # `strapd-toggle nightlight` against a bin/strapd-toggle-nightlight that
  # exists: the binding resolves to a real file either way, so only the more
  # specific name being available makes it wrong.
  if (( ${#argv[@]} > 1 )) && [[ -x $ROOT/bin/$command-${argv[1]} ]]; then
    too_generic+=("$id ($backend): $command ${argv[1]} should be $command-${argv[1]}")
  fi
done <<<"$rows"

(( ${#missing[@]} == 0 )) ||
  fail "every command a binding spawns exists or is a noted forward reference" "$(printf '%s\n' "${missing[@]}")"
pass "every command a binding spawns exists or is a noted forward reference"

(( ${#too_generic[@]} == 0 )) ||
  fail "no binding calls a generic helper that has a specific command" "$(printf '%s\n' "${too_generic[@]}")"
pass "no binding calls a generic helper that has a specific command"

(( ${#divergent[@]} == 0 )) ||
  fail "the three backends spawn the same command for an action" "$(printf '%s\n' "${divergent[@]}")"
pass "the three backends spawn the same command for an action"

# A deferred entry that has since been built is not a harmless leftover: it is
# a command the check has stopped looking at.
stale=()
for command in "${!DEFERRED[@]}"; do
  [[ -x $ROOT/bin/$command ]] && stale+=("$command is built; drop it from DEFERRED")
done
(( ${#stale[@]} == 0 )) || fail "the deferred list holds only unbuilt commands" "$(printf '%s\n' "${stale[@]}")"
pass "the deferred list holds only unbuilt commands"

# And one that nothing binds any more is a note about a key that is gone.
unreferenced=()
for command in "${!DEFERRED[@]}"; do
  grep -qF "$command" "$ACTIONS" || unreferenced+=("$command is not spawned by any binding")
done
(( ${#unreferenced[@]} == 0 )) || fail "the deferred list holds only commands a binding spawns" "$(printf '%s\n' "${unreferenced[@]}")"
pass "the deferred list holds only commands a binding spawns"
