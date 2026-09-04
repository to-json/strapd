# strapd on NixOS

strapd is an Arch + Wayland desktop that treats the compositor as a choice
rather than the product. niri, sway and MangoWC all get equal support. This
directory is the NixOS layer: the same tree and the same ~350 `strapd`
commands, packaged and wired the NixOS way. Arch stays the reference; NixOS is
the second distro, supported from the shared core with no abstraction layer
between them.

Everything here lives under `nix/`. The repo-root `flake.nix` only delegates in.

## What's different from Arch

The rule is declarative, not imperative. On Arch you mutate the running system:
install a package, update, switch channels. On NixOS you rebuild your flake, so
strapd's imperative package, update and channel commands are dropped, and
`nix/pkgs/strapd/excluded-commands.txt` records every one of them and why.
What's left is either distro-neutral, or degrades to something sensible when
an optional app is absent.

Concretely:

- The tree installs to a stable `/etc/strapd`, rewritten from
  `/usr/share/strapd` at build time, so user-editable configs never embed a
  store path that goes stale on rebuild.
- Runtime dependencies sit on the session `PATH`
  (`environment.systemPackages`), because keybindings invoke `strapd-*`
  directly and never through per-script wrappers.
- The home-manager module seeds user config copy-if-absent, and renders the
  default theme at activation. Your edits to seeded files survive a rebuild.
- Login is greetd + tuigreet, offering exactly the three strapd sessions.
- Package removal, installs and updates are gone. Edit your flake.

## Ways to use it

### 1. The modules, in your own flake

```nix
{
  inputs.strapd.url = "github:<owner>/strapd"; # this repo

  outputs = { nixpkgs, strapd, home-manager, ... }: {
    nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        strapd.nixosModules.strapd
        home-manager.nixosModules.home-manager
        {
          strapd.enable = true;
          # strapd.compositors = [ "niri" "sway" "mango" ]; # the default

          home-manager.users.you = {
            imports = [ strapd.homeManagerModules.strapd ];
            strapd.enable = true;
          };
        }
      ];
    };
  };
}
```

`nixosModules.strapd` brings the desktop: the three compositors through their
nixpkgs modules, greetd, uwsm, Noctalia, the service parity, the systemd user
units. `homeManagerModules.strapd` seeds the per-user config and renders the
theme. If you override the package, point both `strapd.package` options at the
same one.

### 2. The reference VM

`nixosConfigurations.strapd-vm` is a minimal x86_64 machine with the desktop
enabled, used to verify the NixOS layer on something closer to real hardware. It
builds as a disk image (`packages.x86_64-linux.vm-image`) and boots in the
sibling QEMU rig by direct kernel load. See that rig's `run-nixos.sh` for the
build-then-boot flow; the image ships as raw and the host converts it to qcow2.

### 3. The live ISO

`packages.x86_64-linux.iso`, from `nixosConfigurations.strapd-iso`, is a live
demo medium. Boot it, land at the strapd login, pick a compositor, look around.
It is not an installer. You provision a real machine from its own flake, per the
declarative rule above.

```sh
nix build .#packages.x86_64-linux.iso
# result/iso/*.iso -> write to a USB stick
```

## Layout

```
flake.nix                      # root; delegates to nix/
nix/outputs.nix                # packages, modules, nixosConfigurations, checks
nix/pkgs/strapd/               # the tree derivation + command exclusions
nix/pkgs/strapd-sessions.nix   # the three wayland-sessions
nix/modules/nixos.nix          # nixosModules.strapd (the system half)
nix/modules/home.nix           # homeManagerModules.strapd (the user half)
nix/hosts/vm.nix               # nixosConfigurations.strapd-vm
nix/hosts/iso.nix              # nixosConfigurations.strapd-iso
nix/checks/shell-tests.nix     # test/shell under `nix flake check`
```

## Checks

```sh
nix flake check          # builds the strapd package and runs test/shell
nix build .#strapd       # just the tree package
```

The shell suite runs against a tree shaped exactly like the package, with the
same command exclusions and the same shebang patching. So a command this layer
drops can't be tested here, and a menu row or keybinding that names a missing
command fails the build.
