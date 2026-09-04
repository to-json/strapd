# Build and install uwsm from source.
#
# uwsm is the Universal Wayland Session Manager: strapd-session ends in
# `exec uwsm start ... <compositor>`, so it is load-bearing: without it no
# session comes up, packaged sway included. Arch has it in the repos; Debian
# trixie does not package it at all (see strapd-external.packages), so this
# layer builds it here.
#
# Its runtime dependencies, python3-xdg, python3-dbus, are in
# strapd-base.packages; the build-only tools are pulled in just for this step.
# The whole thing is wrapped so a failure (a network blip, an upstream change)
# is a loud warning in the install log rather than an aborted install: a desktop
# that installs and then explains it needs uwsm built beats one that stops
# halfway with the tree already laid down.

if command -v uwsm >/dev/null 2>&1; then
  echo "uwsm already present ($(command -v uwsm)); skipping build"
  return 0 2>/dev/null || exit 0
fi

build_uwsm() {
  local src
  src=$(mktemp -d)
  trap 'rm -rf "$src"' RETURN

  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git meson ninja-build pkgconf scdoc || return 1

  # A shallow clone of the default branch; uwsm is pure Python + data files, so
  # "building" it is really meson staging the scripts into /usr/local.
  git clone --depth 1 https://github.com/Vladimir-csp/uwsm "$src/uwsm" || return 1
  ( cd "$src/uwsm" &&
    meson setup build --prefix=/usr/local &&
    meson install -C build ) || return 1

  command -v uwsm >/dev/null 2>&1
}

if build_uwsm; then
  echo "uwsm installed: $(command -v uwsm) ($(uwsm --version 2>/dev/null | head -1))"
else
  echo "WARNING: uwsm build failed. No compositor session will start until it is" >&2
  echo "         installed by hand; see debian/install/strapd-external.packages." >&2
fi

# Always succeed: apply-system runs this under set -e, and a missing uwsm is a
# reported problem, not a reason to abort a tree that is otherwise in place.
exit 0
