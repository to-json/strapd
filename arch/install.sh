#!/bin/bash
#
# Install strapd onto an Arch machine that already exists. The README points
# readers here, so it has to be the whole procedure. The ISO covers the other
# case, installing Arch and strapd together.
#
# Four things:
#
#   1. the packages from install/strapd-base.packages
#   2. this checkout at /usr/share/strapd, with bin/ symlinked into /usr/bin
#   3. the handful of files that live at fixed system paths, which $STRAPD_PATH
#      cannot reach and so only an install can put in place
#   4. `strapd apply system`, the existing entry point for everything
#      root-owned: hardware detection, services, firewall, snapshots, login
#
# The AUR half does not come through a helper. MangoWC is the only one of the
# three compositors not in the official repos, and it, xdg-terminal-exec, yay
# and the rest are built from the PKGBUILDs vendored in vendor/ -- see
# bin/strapd-vendor-build for why that rather than `yay -S`.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# The repo root, one up: place-tree assembles the flat tree from shared/ +
# arch/, so it takes the root, not this layer's dir.
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
# pacman missing halfway through the package step, an install-user that is root,
# or a self-copy that empties the very tree it is reading from.

[[ -f /etc/arch-release ]] || die "this is not an Arch system"
command -v pacman >/dev/null || die "pacman is not installed"

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
  - run system setup: services, firewall, snapshots, hardware detection

PROMPT
  read -rp "Continue? [y/N] " reply
  [[ ${reply,,} == y* ]] || die "nothing was changed"
fi

step "Installing packages from install/strapd-base.packages"

mapfile -t packages < <(grep -vE '^\s*(#|$)' "$REPO/install/strapd-base.packages")
(( ${#packages[@]} )) || die "install/strapd-base.packages lists nothing"

# --needed so a re-run is a no-op rather than a reinstall of two hundred
# packages, which is most of what makes this safe to run twice.
sudo pacman -S --needed --noconfirm "${packages[@]}"

step "Building the vendored AUR packages"

# The AUR half of the package set, built from PKGBUILDs kept in vendor/ rather
# than pulled through a helper: install/* runs as root inside the target and yay
# refuses to run as root, so this was the piece with no route in. It is also
# what makes the MangoWC session real rather than an entry in the greeter that
# cannot start.
#
# Not fatal. Everything the base desktop needs to reach a login is in the repo
# packages above, and one PKGBUILD that will not build should cost its own
# package rather than the install.
if ! STRAPD_VENDOR_DIR="$REPO/vendor" "$REPO/bin/strapd-vendor-build"; then
  echo "install.sh: some vendored packages did not build (see above)." >&2
  echo "install.sh: retry one at a time with: strapd vendor build <package>" >&2
fi

step "Installing the repo at $TARGET"

# Shared with the ISO installer, which does exactly this into a chroot.
sudo bash "$REPO/install/place-tree.sh" --root / --from "$REPO_ROOT"

step "Seeding the shipped configs into $HOME"

# Without a compositor config in $HOME the desktop does not start: niri writes
# its own default, which never calls `uwsm finalize`, and the session is killed
# waiting for it.
#
# --no-clobber, unlike the ISO route, which seeds a home created seconds
# earlier. This is somebody's existing machine, and their own foot.ini is not
# ours to replace; `strapd reinstall configs` is the deliberate version.
cp -rn /etc/skel/.config/. "$HOME/.config/" 2>/dev/null || true
[[ -e $HOME/.bashrc ]] || cp /etc/skel/.bashrc "$HOME/.bashrc"

step "Running system setup"

sudo STRAPD_PATH="$TARGET" "$TARGET/bin/strapd-apply-system" \
  --install-user "$install_user" --first-install

cat <<DONE

==> strapd is installed.

Log out and pick a session: strapd (Niri), strapd (Sway), or strapd (MangoWC).
The first login finishes setup and shows you the keybindings.

Niri and Sway came from the official repos. MangoWC came from vendor/, built
during the install. If its build was one of the ones that failed, that session
will not start until you retry it:

  strapd vendor build mangowm

DONE
