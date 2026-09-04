# strapd on Debian

Debian 13 ("trixie") is the target. The distro-neutral core lives in `shared/`,
and this directory holds only what Debian does differently: the apt package
hooks, the install machinery, and the system setup `strapd apply system` runs.

The runtime tree is flat (`bin/`, `default/`, `config/`, ...). A checkout is
split by distro; `install/place-tree.sh` merges `shared/` and `debian/` into
that flat layout, exactly as the Arch one does. To run the shell suite against
the assembled Debian tree:

    ./run-tests.sh debian

## Installing (layer onto an existing Debian)

On a machine already running Debian 13, from a checkout:

    debian/install.sh

It installs the packages in `install/strapd-base.packages`, lays the tree down
at `/usr/share/strapd` with its commands on `/usr/bin`, seeds the shipped
configs into your home, and runs root-owned setup for services, firewall, login
and generic hardware. Then log out and pick a strapd session.

## The Wayland stack gap

trixie's archive doesn't carry the modern compositors strapd is built on.
`install/strapd-base.packages` installs the core desktop minus those; the rest
come from outside stable:

- sway is in trixie, and is the one session that works off a stock install.
- niri isn't in stable. Use `trixie-backports` if it's there, or an upstream
  build.
- MangoWC (`mango`) isn't packaged for Debian. Build it from source.
- Noctalia shell isn't packaged. Build it from source or run its flatpak.

Until those are in place their sessions won't start. sway is the fallback that
always does.

## Status

D1, where we are now: the layer-onto-existing install path. Package list,
`place-tree.sh`, `install.sh`, the apt package hooks (`strapd-pkg-add`,
`strapd-pkg-missing`, `strapd-pkg-remove`), and a Debian `apply-system` /
`apply-hardware` that runs the neutral config, login, post-install and
generic-hardware setup. The assembled tree passes the shell suite,
`checks.debian-shell-tests`.

D2, later: an install medium of strapd's own, built with debootstrap or
live-build, and the long tail of machine-specific hardware quirks the Arch
layer carries.
