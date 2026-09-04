#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

template="$ROOT/default/snapper/root"
limine_defaults="$ROOT/etc/limine-entry-tool.d/strapd-defaults.conf"
limine_notify_autostart="$ROOT/config/autostart/limine-snapper-notify.desktop"

grep -Fx 'NUMBER_CLEANUP="yes"' "$template" >/dev/null
grep -Fx 'NUMBER_LIMIT="5"' "$template" >/dev/null
grep -Fx 'TIMELINE_CREATE="no"' "$template" >/dev/null
! grep -Eq '^TIMELINE_(CLEANUP|LIMIT_)' "$template" || fail "Snapper template keeps timeline cleanup details out of the default config"
grep -Fx 'MAX_SNAPSHOT_ENTRIES=6' "$limine_defaults" >/dev/null || fail "Limine allows for a snapshot created before Snapper cleanup"
pass "Snapper and Limine retain update snapshots without a transient limit mismatch"

grep -Fx '[Desktop Entry]' "$limine_notify_autostart" >/dev/null
grep -Fx 'Hidden=true' "$limine_notify_autostart" >/dev/null
pass "Limine Snapper warning notifier is disabled by default"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/snapper" <<'STUB'
#!/bin/bash
printf 'snapper %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin/snapper"

cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
STUB
chmod +x "$fake_bin/systemctl"

: >"$test_tmp/calls.log"

TEST_LOG="$test_tmp/calls.log" \
PATH="$fake_bin:$PATH" \
STRAPD_SNAPPER_CONFIGURE_TEST=1 \
STRAPD_PATH="$ROOT" \
STRAPD_SNAPPER_CONFIG_PATH="$test_tmp/etc/snapper/configs/root" \
STRAPD_SNAPPER_CONF_PATH="$test_tmp/etc/conf.d/snapper" \
  bash -euo pipefail "$ROOT/install/config/snapper.sh" >/dev/null

cmp -s "$template" "$test_tmp/etc/snapper/configs/root" || fail "snapshot configure installs the strapd Snapper template"
grep -Fx 'SNAPPER_CONFIGS="root"' "$test_tmp/etc/conf.d/snapper" >/dev/null || fail "snapshot configure writes /etc/conf.d/snapper"
grep -Fx 'systemctl disable --now snapper-timeline.timer' "$test_tmp/calls.log" >/dev/null || fail "snapshot configure disables timeline snapshots"
grep -Fx 'systemctl enable --now snapper-cleanup.timer limine-snapper-sync.service' "$test_tmp/calls.log" >/dev/null || fail "snapshot configure enables cleanup and Limine snapshot sync"
pass "snapshot configure normalizes Snapper policy and services"

setup_system="$ROOT/bin/strapd-apply-system"
grep -F 'config/all.sh' "$setup_system" >/dev/null ||
  fail "system setup runs the config phase"
grep -F 'config/snapper.sh' "$ROOT/install/config/all.sh" >/dev/null ||
  fail "config phase normalizes Snapper"
pass "system setup normalizes Snapper during fresh installs"
