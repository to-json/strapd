#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin" "$test_tmp/home"

for command in xdg-user-dirs-update xdg-settings xdg-mime; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$command"
done
chmod +x "$mock_bin"/*

# Provisioning prepends $STRAPD_PATH/bin, which shadows a mock for anything
# strapd ships, so the install suite is stubbed at its path instead. The real
# one rethemes the session it runs in and does a global Node install.
mkdir -p "$test_tmp/install/user"
: >"$test_tmp/install/user/all.sh"

HOME="$test_tmp/home" PATH="$mock_bin:$ROOT/bin:$PATH" STRAPD_PATH="$ROOT" \
  STRAPD_INSTALL="$test_tmp/install" bash "$ROOT/bin/strapd-provision-user" >/dev/null ||
  fail "strapd-provision-user finishes"

# strapd ships no skills yet, so what matters is that an empty skills directory
# links nothing rather than leaving a broken symlink named for the glob.
for agent_dir in .agents/skills .claude/skills .codex/skills .pi/agent/skills .gemini/config/skills; do
  dir="$test_tmp/home/$agent_dir"
  [[ -d $dir ]] || fail "strapd-provision-user creates $agent_dir"
  stray=$(find "$dir" -mindepth 1 -maxdepth 1 -xtype l)
  [[ -z $stray ]] || fail "strapd-provision-user leaves no dangling skill link in $agent_dir" "$stray"
done

for skill in "$ROOT"/default/agents/skills/*/; do
  [[ -d $skill ]] || continue
  name=$(basename "$skill")
  link="$test_tmp/home/.gemini/config/skills/$name"
  [[ -L $link && $(readlink "$link") == "${skill%/}" ]] ||
    fail "strapd-provision-user provisions the $name skill for Antigravity"
done

pass "strapd-provision-user links every skill it ships and nothing it does not"
