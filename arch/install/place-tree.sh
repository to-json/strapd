#!/bin/bash
#
# Put strapd's files where the system expects them.
#
# Called twice, from two directions, which is why it is its own file:
#
#   install.sh          onto the running machine, with --root /
#   strapd-install      into a freshly pacstrapped chroot, with --root /mnt
#
# One has a running system and sudo, the other a mounted target and is already
# root, so this assumes root and takes the target as an argument.
#
# It places only the files that cannot be found through $STRAPD_PATH: the tree
# itself, the commands on PATH, and the handful at fixed system paths, read by
# things that run before anything has told them where strapd is.

set -euo pipefail

root=/
source_repo=""

usage() {
  echo "Usage: install/place-tree.sh --root <target> --from <repo>" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --root) shift; root="${1:-}" ;;
    --from) shift; source_repo="${1:-}" ;;
    *) usage ;;
  esac
  shift || true
done

[[ -n $root && -d $root ]] || usage
# Two shapes of source arrive here: a checkout split by distro (shared/ +
# arch/), and an already-flat tree, which is what the ISO carries.
[[ -n $source_repo && ( -f $source_repo/arch/install/strapd-base.packages \
  || -f $source_repo/install/strapd-base.packages ) ]] || usage
(( EUID == 0 )) || { echo "place-tree.sh must run as root" >&2; exit 1; }

# Trailing slashes make every path below ambiguous; strip once, here.
root="${root%/}"
target="$root/usr/share/strapd"

# The runtime tree is flat (bin/, default/, config/, ...), so from a checkout
# shared/ and arch/ are merged into the layout everything downstream (the
# dispatcher, $STRAPD_PATH, the tests) expects.
rm -rf "$target"
mkdir -p "$target"
if [[ -d $source_repo/shared ]]; then
  cp -a "$source_repo/shared/." "$target/"
  cp -a "$source_repo/arch/." "$target/"
else
  cp -a "$source_repo/." "$target/"
  rm -rf "$target"/{.git,plan-harness-workspace}
fi

# Set the modes here rather than trusting the source tree. The ISO route
# arrives with every file at 0644: mkarchiso copies its airootfs with
# --no-preserve=mode so its own file_permissions array is the single authority,
# and a tree dropped in wholesale loses every executable bit. That fails at the
# very last step of an otherwise complete install.
chmod 0755 "$target"/bin/*
find "$target/install" -name '*.sh' -exec chmod 0755 {} +
[[ -f $target/install.sh ]] && chmod 0755 "$target/install.sh"
for runner in "$target"/test/shell "$target"/test/acceptance; do
  [[ -f $runner ]] && chmod 0755 "$runner"
done

# The link target is the path *inside* the installed system, the same string
# either way, so it is written out rather than derived from $target, which
# carries the mount prefix in a chroot.
mkdir -p "$root/usr/bin"
for command in "$target"/bin/strapd*; do
  ln -sf "/usr/share/strapd/bin/$(basename "$command")" \
    "$root/usr/bin/$(basename "$command")"
done

# uwsm reads its env.d before anything has told it where strapd lives. Without
# this, every session starts with STRAPD_PATH unset and first-run fails with 127.
install -Dm644 "$target/default/uwsm/env.d/10-strapd" \
  "$root/usr/share/uwsm/env.d/10-strapd"
install -Dm644 "$target/etc/profile.d/strapd.sh" "$root/etc/profile.d/strapd.sh"

for unit in "$target"/default/systemd/user/*.service; do
  install -Dm644 "$unit" "$root/usr/lib/systemd/user/$(basename "$unit")"
done
install -Dm644 "$target/default/systemd/user/app.slice.d/10-oomd.conf" \
  "$root/usr/lib/systemd/user/app.slice.d/10-oomd.conf"

# Executable, not 644: systemd runs these rather than reading them.
for generator in "$target"/default/systemd/user-environment-generators/*; do
  install -Dm755 "$generator" \
    "$root/usr/lib/systemd/user-environment-generators/$(basename "$generator")"
done

# /etc/skel is where a new user's home comes from: `useradd -m` seeds from it,
# and without strapd's configs there a fresh machine has no compositor config at
# all. niri then writes its own default, which spawns waybar and never calls
# `uwsm finalize`, so uwsm times out, kills the compositor and drops the user
# back at the greeter -- after an install that reported success.
#
# strapd-reinstall-configs documents /etc/skel as the source it replays from.
skel="$root/etc/skel"
mkdir -p "$skel/.config"
cp -a "$target/config/." "$skel/.config/"
install -Dm644 "$target/default/bashrc" "$skel/.bashrc"

# Twice, into two directories, for two different readers.
#
# /usr/share/wayland-sessions is where every greeter looks, so a machine that
# kept its existing display manager still finds strapd's sessions. But that
# directory is shared -- niri, sway and mango each install a session file of
# their own -- so a greeter pointed at it offers six entries, three of which
# start a bare compositor with none of the session environment. strapd's own
# greeter is pointed at the directory holding only strapd's three.
for session in "$target"/default/wayland-sessions/*.desktop; do
  install -Dm644 "$session" "$root/usr/share/wayland-sessions/$(basename "$session")"
  install -Dm644 "$session" "$target/wayland-sessions/$(basename "$session")"
done
