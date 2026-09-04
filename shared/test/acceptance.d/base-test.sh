#!/bin/bash
#
# Shared helpers for test/acceptance.d/*-test.sh. Mirrors the pass/fail output of
# test/shell.d/base-test.sh so both suites read the same way, but adds `require`:
# an acceptance test that silently skips when the software it checks against is
# missing would report a green suite that proved nothing.

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "source test/acceptance.d/base-test.sh from an acceptance test; do not run it directly" >&2
  exit 1
fi

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
ARTIFACTS="${STRAPD_ACCEPTANCE_DIR:-/tmp/strapd-acceptance}"

mkdir -p "$ARTIFACTS"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  local description="$1" detail="${2:-}"
  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

# Hard-fail (never skip) when a command this suite depends on is absent.
require() {
  local cmd
  for cmd; do
    command -v "$cmd" >/dev/null 2>&1 ||
      fail "acceptance dependency present: $cmd" \
           "$cmd is not installed; acceptance tests must run on a box that has it"
  done
}
