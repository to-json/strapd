#!/usr/bin/env bash
#
# Run the shell suite against an assembled distro tree.
#
# The source is split by distro (shared/ + arch/ + debian/); the tests run
# against the flat runtime tree place-tree.sh produces. This assembles that tree
# for one distro into a tempdir and runs the whole suite there.
#
# Usage: ./run-tests.sh [distro] [test-args...]
#   distro defaults to 'arch'. Pass 'debian' to assemble shared/ + debian/.
#   Anything after the distro is forwarded to test/shell.
#
# For just the neutral core (the NixOS layer's view), run `bash
# shared/test/shell`. The suites also run under `nix flake check`.
set -euo pipefail
cd "$(dirname "$0")"

distro=arch
if (($#)) && [[ -d $1 && -d $1/bin ]] && [[ $1 == arch || $1 == debian ]]; then
  distro=$1
  shift
fi

tree=$(mktemp -d)
trap 'rm -rf "$tree"' EXIT

cp -a shared/. "$tree/"
cp -a "$distro/." "$tree/"

STRAPD_PATH="$tree" exec bash "$tree/test/shell" "$@"
