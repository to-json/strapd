#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The install path is the one thing in the tree no unit test exercises end to
# end: every script under install/ is sourced by an all.sh, and any one of them
# reaching for something a later phase still owns takes the whole install down
# under `set -eE`. Phase 2 shipped four of those and none showed up until an
# install was actually run. This walks the references statically instead.

orchestrators=(
  "$ROOT/bin/strapd-apply-system"
  "$ROOT/bin/strapd-apply-hardware"
  "$ROOT/bin/strapd-provision-user"
)
while IFS= read -r layer; do
  orchestrators+=("$layer")
done < <(find "$ROOT/install" -name all.sh | sort)

missing=""
for orchestrator in "${orchestrators[@]}"; do
  while IFS= read -r ref; do
    [[ -n $ref ]] || continue
    target="$ROOT/install/${ref#\$STRAPD_INSTALL/}"
    [[ -f $target ]] || missing+="  ${orchestrator#"$ROOT/"} -> $ref"$'\n'
  done < <(grep -oE '\$STRAPD_INSTALL/[A-Za-z0-9/._-]+' "$orchestrator" | sort -u)
done
[[ -z $missing ]] ||
  fail "every install layer an orchestrator sources exists" "$missing"
pass "every install layer an orchestrator sources exists"

# Matching is on command position -- start of line, after a shell operator, or
# after sudo/exec/--exec/ExecStart= -- so prose in a comment that names a script
# is not mistaken for a call. A token followed by a `.` is a unit or config file
# name, not a command, and is skipped.
command_position='(^[[:space:]]*|[;&|(]|\$\(|`|--exec |sudo |exec |then |else |do |ExecStart=/usr/bin/)'
unshipped=""
while IFS= read -r command; do
  [[ -n $command ]] || continue
  [[ -f "$ROOT/bin/$command" ]] && continue

  # Two commands the install path names that do not exist yet. Delete the entry
  # in the same commit the script lands, and this starts guarding it.
  #
  #   strapd-provision-owner  ExecStart of its own .service
  #   strapd-shell            the --exec action on first-run/wifi.sh's notification
  case "$command" in
    strapd-provision-owner | strapd-shell) continue ;;
  esac

  unshipped+="  $command"$'\n'
  unshipped+=$(grep -rn -- "$command" "$ROOT/install" | sed "s|$ROOT/|    |" | head -3)$'\n'
done < <(grep -rhoE "${command_position}strapd-[a-z0-9-]+([^a-z0-9.-]|\$)" "$ROOT/install" |
  grep -oE 'strapd-[a-z0-9-]+' | sort -u)

[[ -z $unshipped ]] ||
  fail "every strapd-* command the install path runs is shipped or a known gap" "$unshipped"
pass "every strapd-* command the install path runs is shipped or a known gap"
