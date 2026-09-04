#!/bin/bash

set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/base-test.sh"

stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

cat >"$stub_dir/ufw" <<'STUB'
#!/bin/bash
printf 'ufw %s\n' "$*" >>"$TEST_LOG"
if [[ ${1:-} == status ]]; then
  echo 'Status: inactive'
fi
STUB

cat >"$stub_dir/ufw-docker" <<'STUB'
#!/bin/bash
set -euo pipefail
PATH="/bin:/usr/bin:/sbin:/usr/sbin:/snap/bin/"
printf 'ufw-docker %s\n' "$*" >>"$TEST_LOG"
if ! ufw status 2>/dev/null | grep -Fq 'Status: active'; then
  echo 'inactive' >&2
  exit 1
fi
STUB

cat >"$stub_dir/sed" <<'STUB'
#!/bin/bash
printf 'sed %s\n' "$*" >>"$TEST_LOG"
if [[ ${1:-} == 0,/^PATH=* ]]; then
  exec /usr/bin/sed "$@"
fi
exit 0
STUB

cat >"$stub_dir/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
STUB

chmod +x "$stub_dir"/*

export TEST_LOG="$stub_dir/firewall.log"
PATH="$stub_dir:$ROOT/bin:$PATH" bash -eE -c 'source "$1"' bash "$ROOT/install/config/firewall.sh"

grep -q '^ufw-docker install$' "$TEST_LOG" || fail "ufw-docker rules are installed"
grep -q '^systemctl enable ufw$' "$TEST_LOG" || fail "ufw is enabled for next boot"

pass "firewall config installs ufw-docker rules without activating live UFW"

# ufw-docker is an AUR package and nothing builds the AUR list yet, so on a real
# install it is absent. The config layer runs under `bash -eE`: before the guard
# went in, that missing binary took every install down at the firewall step.
: >"$TEST_LOG"
rm "$stub_dir/ufw-docker"
PATH="$stub_dir:$ROOT/bin:$PATH" bash -eE -c 'source "$1"' bash "$ROOT/install/config/firewall.sh" \
  >"$stub_dir/no-ufw-docker.out" ||
  fail "firewall config survives a missing ufw-docker"

grep -q '^systemctl enable ufw$' "$TEST_LOG" ||
  fail "ufw is still enabled when ufw-docker is missing"
grep -q 'skipping Docker firewall protections' "$stub_dir/no-ufw-docker.out" ||
  fail "the skipped Docker protections are reported" "$(cat "$stub_dir/no-ufw-docker.out")"

pass "firewall config skips ufw-docker rules loudly when the AUR package is absent"
