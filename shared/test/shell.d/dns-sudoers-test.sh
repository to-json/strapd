#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

dns="$ROOT/bin/strapd-dns"
sudoers_file="$ROOT/etc/sudoers.d/strapd-dns"
rule='%wheel ALL=(root) NOPASSWD: /usr/bin/strapd-dns Cloudflare, /usr/bin/strapd-dns Google, /usr/bin/strapd-dns DHCP'

# Exactly one rule, matched whole. A second line, or the same command with its
# arguments dropped, which sudoers reads as "any arguments", would widen the
# grant while leaving this line in place.
rules=$(grep -vE '^[[:space:]]*(#|$)' "$sudoers_file")
[[ $rules == "$rule" ]] ||
  fail "dns sudoers file carries exactly the stock-provider rule and nothing else" "got: $rules"

if command -v visudo >/dev/null; then
  visudo -cf "$sudoers_file" >/dev/null || fail "dns sudoers rule parses"
fi

grep -Fx 'PACKAGED_PATH=/usr/bin/strapd-dns' "$dns" >/dev/null ||
  fail "strapd-dns elevates the path the sudoers rule names"

# `sudo -l` alone answers whether a command is permitted, not whether it is
# passwordless, and strapd ships a blanket %wheel rule that permits everything.
grep -E 'sudo -n -l -l' "$dns" >/dev/null ||
  fail "strapd-dns reads the grant from the long sudo listing"

pass "dns sudoers rule is scoped to the stock providers"

# require_root returns immediately for root, so the stubs below would not stand
# between the script and the host's real config.
if (( EUID == 0 )); then
  pass "running as root; skipping the elevation checks, which would rewrite this machine's DNS"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# pkexec stands in for the exec at the end of require_root, so the DNS writes
# below it never run and real pkexec is never reached.
cat >"$stub_bin/pkexec" <<'SH'
#!/bin/bash
printf 'pkexec %s\n' "$*" >"$ELEVATION_LOG"
SH
chmod +x "$stub_bin/pkexec"

# The sudo stub plays both parts: it answers the passwordless probe from
# STUB_GRANTED and logs the elevation otherwise. STUB_GRANTED empty stands for
# an install whose strapd-settings predates the sudoers file.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ $1 == -n && $2 == -l ]]; then
  for granted in ${STUB_GRANTED-Cloudflare Google DHCP}; do
    [[ ${!#} == "$granted" ]] || continue
    echo "    Options: !authenticate"
    exit 0
  done
  echo "    Matched: ${!#}"
  exit 0
fi
printf 'sudo %s\n' "$*" >"$ELEVATION_LOG"
SH
chmod +x "$stub_bin/sudo"

elevation_for() {
  : >"$test_tmp/elevation"
  ELEVATION_LOG="$test_tmp/elevation" \
  PATH="$stub_bin:$PATH" \
    bash "$dns" "$1" </dev/null >/dev/null
  cat "$test_tmp/elevation"
}

for provider in Cloudflare Google DHCP; do
  elevation=$(elevation_for "$provider")
  [[ $elevation == "sudo /usr/bin/strapd-dns $provider" ]] ||
    fail "strapd-dns takes the passwordless sudo grant for $provider without a terminal" "got: $elevation"
done

pass "strapd-dns elevates the stock providers through sudo, not polkit"

# A dev-linked checkout elevates the packaged path like everyone else, rather
# than handing sudo a path no rule can name and losing the grant.
dev_linked=$(STRAPD_PATH="$test_tmp/checkout" elevation_for Cloudflare)
[[ $dev_linked == "sudo /usr/bin/strapd-dns Cloudflare" ]] ||
  fail "strapd-dns elevates the system install wherever STRAPD_PATH points" "got: $dev_linked"

custom=$(elevation_for Custom)
[[ $custom == "pkexec /usr/bin/strapd-dns Custom" ]] ||
  fail "strapd-dns leaves Custom on the polkit path, since no sudoers rule covers it" "got: $custom"

# The grant is what makes sudo passwordless, so its absence has to route to
# polkit. Betting on sudo leaves the panel's toggle execing into a password
# prompt it has no terminal to show.
ungranted=$(STUB_GRANTED="" elevation_for Cloudflare)
[[ $ungranted == "pkexec /usr/bin/strapd-dns Cloudflare" ]] ||
  fail "strapd-dns falls back to polkit where the sudoers grant is not installed" "got: $ungranted"

pass "strapd-dns falls back to polkit wherever the grant does not reach"
