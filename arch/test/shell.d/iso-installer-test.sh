#!/bin/bash
#
# The installer that runs from the live medium. It cannot be exercised here: it
# partitions a disk. What can be checked is the order of its questions and the
# shape of its refusals -- the only unrecoverable mistake it can make is writing
# to the wrong disk, and the only defence is asking everything first.

set -uo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

INSTALLER="$ROOT/iso/overlay/airootfs/usr/local/bin/strapd-install"

[[ -x $INSTALLER ]] ||
  fail "the installer is on the medium and executable" "$INSTALLER"
bash -n "$INSTALLER" || fail "the installer parses"
pass "the installer is on the medium, executable, and parses"

code=$(grep -vE '^[[:space:]]*#' "$INSTALLER")

# The whole safety argument. wipefs is the first irreversible act, so every
# question has to come before it.
first_write=$(grep -n 'wipefs' "$INSTALLER" | head -1 | cut -d: -f1)
[[ -n $first_write ]] || fail "the installer partitions something"
for question in 'Which disk' 'Type the disk path again' 'Hostname' 'Your username' \
                'Password for' 'Timezone' 'Console keymap'; do
  line=$(grep -n "$question" "$INSTALLER" | head -1 | cut -d: -f1)
  [[ -n $line ]] || fail "the installer asks: $question"
  (( line < first_write )) ||
    fail "every question comes before anything is written" \
      "'$question' is asked at line $line, after wipefs at $first_write"
done
pass "every question is asked before anything is written"

grep -q 'confirmed == "\$target_disk"' <<<"$code" ||
  fail "the disk is confirmed by typing it again"
pass "the disk is confirmed by typing it again"

# The live medium is a block device too, and installing onto it destroys the
# installer partway through.
grep -q 'run/archiso' <<<"$code" ||
  fail "the installer refuses the medium it booted from"
pass "the installer refuses the medium it booted from"

grep -q 'EUID == 0' <<<"$code" || fail "it requires root"
grep -q '/sys/firmware/efi' <<<"$code" ||
  fail "it checks the machine booted UEFI"
efi_line=$(grep -n '/sys/firmware/efi' "$INSTALLER" | head -1 | cut -d: -f1)
(( efi_line < first_write )) ||
  fail "the UEFI check comes before the disk is touched" "checked at $efi_line"
pass "root and UEFI are checked before the disk is touched"

# Downloading a couple of gigabytes is most of the install; finding out the
# network is down after the disk is erased is the worst possible ordering.
grep -q 'no network' <<<"$code" || fail "it checks for a network"
pass "it checks for a network before erasing anything"

# Both kernels and both microcodes. The machine this lands on is unknown, and
# the cheapest insurance against a kernel regression is a second boot entry.
grep -q 'linux-lts' <<<"$code" ||
  fail "a fallback kernel is installed"
grep -q 'intel-ucode' <<<"$code" && grep -q 'amd-ucode' <<<"$code" ||
  fail "both microcodes are installed"
pass "a fallback kernel and both microcodes are installed"

grep -q 'nomodeset' <<<"$code" ||
  fail "there is a safe-graphics boot entry for a GPU the kernel cannot drive"
grep -q 'LTS kernel' <<<"$code" ||
  fail "the fallback kernel gets its own boot entry"
pass "the boot menu offers a fallback kernel and safe graphics"

# NVMe and mmc number partitions with a `p`; SATA does not. Getting it wrong
# formats nothing and then fails, on exactly the modern laptops this targets.
grep -q 'target_disk}p1' <<<"$code" ||
  fail "nvme partition naming is handled"
pass "nvme and sata partition naming are both handled"

grep -q 'place-tree.sh' <<<"$code" ||
  fail "the tree is placed by the shared script, not a second copy of it"
grep -q 'strapd-apply-system' <<<"$code" ||
  fail "system setup goes through the same entry point install.sh uses"
pass "it shares the tree placement and the system setup with install.sh"

# The chroot configuration heredoc is unquoted so the hostname and username
# expand into it. A password expanded the same way would sit in a script body
# that any failure could echo.
grep -q 'chpasswd' <<<"$code" || fail "passwords are set"
awk '/<<CHROOT/,/^CHROOT$/' "$INSTALLER" | grep -q 'password' &&
  fail "the password is not expanded into the chroot heredoc"
pass "the password is piped to chpasswd, not expanded into a script"
