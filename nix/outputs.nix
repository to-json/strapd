# All flake outputs. The root flake.nix delegates here so that everything
# NixOS-specific stays under nix/.
{ self, nixpkgs, home-manager }:
let
  inherit (nixpkgs) lib;
  systems = [ "x86_64-linux" "aarch64-linux" ];
  eachSystem = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

  packagesFor = pkgs: rec {
    strapd = pkgs.callPackage ./pkgs/strapd { src = self; };
    strapd-sessions = pkgs.callPackage ./pkgs/strapd-sessions.nix { inherit strapd; };
    strapd-plymouth = pkgs.callPackage ./pkgs/strapd-plymouth.nix { src = self; };
    default = strapd;
  };
in
{
  packages = eachSystem (pkgs:
    packagesFor pkgs
    // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux") {
      # The qcow2 the sibling VM rig boots. The *content* is x86_64, the closure
      # of nixosConfigurations.strapd-vm, but the image is assembled with
      # native tools (`pkgs` here is whichever architecture runs the build):
      # image assembly is file copying, and a closure is data. The bootloader
      # install is skipped for the same reason; it is the one step that
      # executes guest binaries, so the rig boots this image by direct
      # kernel load (-kernel/-initrd/-append init=...), the same way
      # nixos-rebuild build-vm boots its VMs. Bootloader-path testing is
      # deliberately out of scope for the rig; a real machine's install comes
      # from its own flake.
      vm-image = import "${nixpkgs}/nixos/lib/make-disk-image.nix" {
        inherit lib;
        config = self.nixosConfigurations.strapd-vm.config;
        # cptofs (the LKL tool that copies the closure into the image)
        # hardcodes a 100M kernel, lkl_start_kernel("mem=100M") in
        # tools/lkl/cptofs.c, and deadlocks on memory against this closure.
        # No flag exposes it, so the string gets patched.
        pkgs = import nixpkgs {
          system = "aarch64-linux";
          overlays = [
            (final: prev: {
              lkl = prev.lkl.overrideAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  substituteInPlace tools/lkl/cptofs.c --replace-fail "mem=100M" "mem=4096M"
                '';
              });
            })
          ];
        };
        # raw, not qcow2: make-disk-image assembles the raw image and then, for
        # qcow2, runs `qemu-img convert`, so both the raw and the qcow2 exist at
        # once, and the dev builder's nix build dir is a RAM-backed tmpfs, which
        # that doubled footprint overflows. A single raw image fits. The rig
        # wants a qcow2 to back its overlay, so the raw is converted Mac-side
        # (`qemu-img convert -f raw -O qcow2 nixos.img base-nixos.qcow2`); see
        # the dev VM rig's run-nixos.sh. This is the throwaway verification
        # image; a real machine installs from its own flake, not from this.
        format = "raw";
        partitionTableType = "efi";
        installBootLoader = false;
        # Big enough for the desktop closure with headroom; the rig never needs
        # 40G. (The raw's on-tmpfs footprint tracks the closure, not this number,
        # since the image is created sparse.)
        diskSize = 20480;
        copyChannel = false;
      };

      # The live/demo ISO (see nix/hosts/iso.nix). Unlike vm-image this is a
      # real ISO the stock CD profile knows how to build, so it comes straight
      # off its nixosConfiguration.
      iso = self.nixosConfigurations.strapd-iso.config.system.build.isoImage;
    });

  nixosModules.strapd = import ./modules/nixos.nix self;
  homeManagerModules.strapd = import ./modules/home.nix self;

  nixosConfigurations.strapd-vm = lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit self home-manager; };
    modules = [ ./hosts/vm.nix ];
  };

  nixosConfigurations.strapd-iso = lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit self home-manager; };
    modules = [ ./hosts/iso.nix ];
  };

  checks = eachSystem (pkgs:
    let system = pkgs.stdenv.hostPlatform.system;
    in {
      strapd = self.packages.${system}.strapd;
      shell-tests = pkgs.callPackage ./checks/shell-tests.nix {
        src = self;
        excludedCommands = ./pkgs/strapd/excluded-commands.txt;
      };
      # The whole suite against the Arch-assembled tree (shared/ + arch/).
      arch-shell-tests = pkgs.callPackage ./checks/arch-shell-tests.nix {
        src = self;
      };
      # The whole suite against the Debian-assembled tree (shared/ + debian/).
      debian-shell-tests = pkgs.callPackage ./checks/debian-shell-tests.nix {
        src = self;
      };
    });
}
