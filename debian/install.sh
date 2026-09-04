#!/bin/bash
#
# Install strapd onto a Debian machine that already exists.
#
# The Debian twin of arch/install.sh, doing the same four things and differing
# only where the two distributions do: apt rather than pacman, and a preflight
# that checks for Debian.
#
#   1. the packages from install/strapd-base.packages
#   2. this checkout at /usr/share/strapd, with bin/ symlinked into /usr/bin
#   3. the handful of files that live at fixed system paths, which $STRAPD_PATH
#      cannot reach and so only an install can put in place
#   4. `strapd apply system`, the existing entry point for everything root-owned
#
# trixie's archive does not carry the modern Wayland stack strapd is built on:
# niri, mangowc and noctalia-shell are not in it, so strapd-base.packages is the
# installable core and the note at the end says where the rest comes from.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# The repo root, one up: place-tree assembles the flat tree from shared/ +
# debian/, so it takes the root, not this dir.
REPO_ROOT=$(cd -- "$REPO/.." && pwd)
TARGET=/usr/share/strapd
assume_yes=0

usage() {
  cat <<USAGE
Usage: ./install.sh [--yes]

Installs strapd from this checkout onto the running system. Needs sudo.

  --yes   do not ask before making changes
USAGE
}

while (($#)); do
  case "$1" in
    --yes|-y) assume_yes=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install.sh: unknown option '$1'" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

die() { printf 'install.sh: %s\n' "$1" >&2; exit 1; }
step() { printf '\n==> %s\n' "$1"; }

# Every check here is one that would otherwise fail somewhere less obvious:
# apt missing halfway through the package step, an install-user that is root,
# or a self-copy that empties the very tree it is reading from.

[[ -f /etc/debian_version ]] || die "this is not a Debian system"
command -v apt-get >/dev/null || die "apt-get is not installed"

(( EUID != 0 )) || die "run as your own user, not root; it will ask for sudo when it needs it"

install_user=$(id -un)
[[ $install_user != root ]] || die "run as a normal user; strapd sets up a user session"

[[ -f $REPO/install/strapd-base.packages ]] ||
  die "run this from a strapd checkout ($REPO does not look like one)"

# Installing the target onto itself would delete the source mid-copy.
[[ $REPO != "$TARGET" ]] ||
  die "this checkout is already the installed tree; nothing to copy"

command -v sudo >/dev/null || die "sudo is not installed"

if (( ! assume_yes )); then
  cat <<PROMPT

strapd will be installed from
  $REPO
onto this machine, for user '$install_user'. This will:

  - install packages from install/strapd-base.packages
  - replace $TARGET with this checkout
  - symlink its commands into /usr/bin
  - run system setup: services, firewall, login, hardware detection

PROMPT
  read -rp "Continue? [y/N] " reply
  [[ ${reply,,} == y* ]] || die "nothing was changed"
fi

step "Installing packages from install/strapd-base.packages"

mapfile -t packages < <(grep -vE '^\s*(#|$)' "$REPO/install/strapd-base.packages")
(( ${#packages[@]} )) || die "install/strapd-base.packages lists nothing"

sudo apt-get update
# --no-install-recommends keeps the install to what strapd names rather than
# each package's full recommends web. A re-run is a near no-op.
sudo apt-get install -y --no-install-recommends "${packages[@]}"

step "Installing the repo at $TARGET"

sudo bash "$REPO/install/place-tree.sh" --root / --from "$REPO_ROOT"

step "Seeding the shipped configs into $HOME"

# Without a compositor config in $HOME the desktop does not start: niri writes
# its own default, which never calls `uwsm finalize`, and the session is killed
# waiting for it.
#
# --no-clobber: this is somebody's existing machine, and their own foot.ini is
# not ours to replace. `strapd reinstall configs` is the deliberate version.
cp -rn /etc/skel/.config/. "$HOME/.config/" 2>/dev/null || true
[[ -e $HOME/.bashrc ]] || cp /etc/skel/.bashrc "$HOME/.bashrc"

step "Running system setup"

sudo STRAPD_PATH="$TARGET" "$TARGET/bin/strapd-apply-system" \
  --install-user "$install_user" --first-install

cat <<DONE

==> strapd is installed.

Log out and pick a session: strapd (Niri), strapd (Sway), or strapd (MangoWC).
The first login finishes setup and shows you the keybindings.

Sway came from trixie's archive. niri, MangoWC and the Noctalia shell are not
in stable. Install them from trixie-backports, a flatpak, or an upstream
build before the matching session will start. See debian/README.md.

DONE
