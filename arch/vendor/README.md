# Vendored AUR packages

The PKGBUILDs for the AUR packages strapd needs, kept in the tree and built by
`strapd vendor build`, which `arch/install.sh` runs after the pacman step.

## Why the PKGBUILDs are here rather than pulled at install time

Three reasons, in the order they bit:

1. **`install/*` runs as root, and neither `yay` nor `makepkg` will run as
   root.** That left the AUR set with no route in from the one place that
   needed it: `strapd-aur.packages` said so itself ("this file is a list of what
   needs building, not something install/* can act on"), and `install.sh` said
   it does not install from the AUR. So on a fresh Arch machine nothing in that
   list was ever installed. `strapd vendor build` drops to a real user for the
   build and keeps only the dependency install and the final `pacman -U`
   privileged.

2. **The AUR index moves underneath us.** `mangowc` was renamed to `mangowm`;
   the old package page now 404s, so `yay -S mangowc` -- printed by both
   `install.sh` and `strapd-session` -- had been telling people to run something
   that fails. That is also why first boot dead-ended: `tuigreet` with no
   remembered session takes the first entry in the sessions directory, which
   sorts to `strapd-mango.desktop`, and mango was never installable.

3. **A vendored PKGBUILD is a diff.** A version bump is reviewed like any other
   change instead of arriving silently on whichever day someone reinstalls.

## What is here

One directory per package, holding exactly what the AUR repo holds minus its
git metadata: `PKGBUILD`, `.SRCINFO`, and any patches or `.install` files.
`manifest.tsv` records the version and the AUR commit each was taken from.

Upstream sources are **not** vendored -- only the PKGBUILDs that name them. The
`source=` URLs and their checksums are pinned in each `.SRCINFO`, so a build is
still reproducible and verified, but it does reach the network. Vendoring the
tarballs would add hundreds of megabytes and still not give an offline build:
the Rust, Go and Flutter packages here fetch their own dependency trees during
`build()` regardless.

Two entries nothing asked for directly, pulled in because something else is
built on them:

- `scenefx0.5` — `mangowm` depends on it, and it is AUR-only.
- `zig0.15` — `herdr` builds with it, and it is AUR-only.

`wlroots0.20`, which `scenefx0.5` needs, is in `extra` and so is left to pacman.

## Refreshing

    strapd vendor refresh              # everything in the manifest
    strapd vendor refresh mangowm      # one package and whatever it is built on

Run it against a dev-linked checkout (`strapd dev link`), never an installed
tree: it rewrites this directory, and the point is to read the result as a diff
before it ships. It follows build dependencies that pacman cannot resolve from
the official repos, which is how `scenefx0.5` and `zig0.15` got here.

If a package has been renamed or deleted, refresh says so and leaves the
vendored copy alone rather than shipping one fewer package than the manifest
claims.

## Building

    strapd vendor build                # everything not already at the vendored version
    strapd vendor build mangowm        # one package, its vendored deps first
    strapd vendor build --list         # vendored vs installed versions
    strapd vendor build --force        # rebuild even if already installed

Build order is worked out from the `.SRCINFO` files, so `scenefx0.5` is built
before `mangowm` and `zig0.15` before `herdr` without anything saying so twice.
