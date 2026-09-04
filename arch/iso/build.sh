#!/bin/bash
#
# Build strapd's installation media.
#
# The profile is archiso's own `releng` with strapd's bits laid over it, copied
# fresh at build time rather than vendored: releng is what upstream tests, and
# tracking it is free as long as we never fork it. What strapd adds is in
# iso/overlay/.
#
# releng already boots both BIOS and UEFI. The installer needs a UEFI machine,
# but the *medium* boots either way, which is what lets it say so rather than
# refusing to start.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# The repo root, one up from arch/: the medium's tree is assembled from
# shared/ + arch/, the same flat layout place-tree produces.
REPO_ROOT=$(cd -- "$REPO/.." && pwd)
OUT=${OUT:-$REPO/iso/out}
WORK=${WORK:-/var/tmp/strapd-iso}

die() { printf 'iso/build.sh: %s\n' "$1" >&2; exit 1; }
step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }

(( EUID == 0 )) || die "mkarchiso needs root"

# One build at a time. Two racing is not a slow build but a broken one that
# takes a while to see: the second clears the work tree the first is still
# pacstrapping into, and the first carries on writing to a directory that no
# longer exists. /var/tmp rather than /var/lock, which is not always present.
lockfile="/var/tmp/strapd-iso-build.lock"
exec 9>"$lockfile"
flock -n 9 || die "another build is already running (lock: $lockfile)"
command -v mkarchiso >/dev/null || die "archiso is not installed (pacman -S archiso)"
[[ -d /usr/share/archiso/configs/releng ]] || die "archiso's releng profile is missing"

profile="$WORK/profile"

# An interrupted build leaves mkarchiso's bind mounts behind inside the work
# tree, and rm walks straight into them and fails with "Device or resource
# busy". Unmounting deepest-first is what makes a retry possible without a
# reboot.
if [[ -d $WORK ]]; then
  step "Clearing the previous work tree"
  # A pipe rather than process substitution: this script gets run detached,
  # and /dev/fd is not always there when it is.
  findmnt -rno TARGET | grep "^$WORK" | sort -r | while read -r mountpoint; do
    umount -l "$mountpoint" 2>/dev/null || true
  done
  rm -rf "$WORK"
fi

mkdir -p "$profile" "$OUT"

step "Copying archiso's releng profile"
cp -r /usr/share/archiso/configs/releng/. "$profile/"

step "Overlaying strapd"
# Everything except the package list, which is appended rather than replaced.
for entry in "$REPO"/iso/overlay/*; do
  [[ $(basename "$entry") == packages.x86_64 ]] && continue
  cp -r "$entry" "$profile/"
done
cat "$REPO/iso/overlay/packages.x86_64" >>"$profile/packages.x86_64"

# A safe-graphics entry on the medium's own boot menu, for the machine whose
# GPU the kernel cannot drive -- the one failure the medium cannot report,
# because reporting needs a display. The UEFI entry is a file in the overlay;
# syslinux keeps its entries in one config, so the BIOS one is appended here.
cat >>"$profile/syslinux/archiso_sys-linux.cfg" <<'SYSLINUX'

LABEL strapd_nomodeset
TEXT HELP
Boot the strapd installer with kernel modesetting disabled, for a machine
whose graphics the kernel cannot drive. Slower, and it shows a console.
ENDTEXT
MENU LABEL strapd installer (%ARCH%, BIOS, ^safe graphics)
LINUX /%INSTALL_DIR%/boot/%ARCH%/vmlinuz-linux
INITRD /%INSTALL_DIR%/boot/%ARCH%/initramfs-linux.img
APPEND archisobasedir=%INSTALL_DIR% archisosearchuuid=%ARCHISO_UUID% nomodeset
SYSLINUX

sed -i 's|Arch Linux install medium|strapd installer|g' \
  "$profile/efiboot/loader/entries"/*.conf \
  "$profile/syslinux"/*.cfg

# Same exclusions as an installed system: no history, no plan harness.
step "Putting the strapd tree on the medium"
mkdir -p "$profile/airootfs/usr/share/strapd"
cp -a "$REPO_ROOT/shared/." "$profile/airootfs/usr/share/strapd/"
cp -a "$REPO_ROOT/arch/." "$profile/airootfs/usr/share/strapd/"
rm -rf "$profile/airootfs/usr/share/strapd"/{.git,plan-harness-workspace,iso/out}

# archiso substitutes iso_label into the boot entries, which is how the kernel
# finds the medium it booted from, so the name and the label have to agree.
step "Naming the image"
sed -i \
  -e 's|^iso_name=.*|iso_name="strapd"|' \
  -e 's|^iso_label=.*|iso_label="STRAPD_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"|' \
  -e 's|^iso_publisher=.*|iso_publisher="strapd"|' \
  -e 's|^iso_application=.*|iso_application="strapd installer"|' \
  "$profile/profiledef.sh"

# mkarchiso applies this array over the copied tree, and a file listed with the
# wrong mode is one the live user cannot run.
grep -q 'strapd-install' "$profile/profiledef.sh" ||
  sed -i 's|^file_permissions=(|file_permissions=(\n  ["/usr/local/bin/strapd-install"]="0:0:755"|' \
    "$profile/profiledef.sh"

# releng compresses with xz, right for an image downloaded by millions and
# wrong for media built on the machine that will write it to a stick: it spends
# the better part of an hour to save bandwidth nobody is paying for. zstd -19
# is close in size and finishes in minutes.
step "Compressing with zstd rather than xz"
sed -i "s|^airootfs_image_tool_options=.*|airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')|" \
  "$profile/profiledef.sh"

step "Building (this takes a while and a few gigabytes)"
mkarchiso -v -w "$WORK/work" -o "$OUT" "$profile"

step "Done"
ls -lh "$OUT"/*.iso
