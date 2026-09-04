# nixosConfigurations.strapd-vm, the reference machine.
#
# Built as a qcow2 (packages.x86_64-linux.vm-image) 
{ config, lib, pkgs, modulesPath, self, home-manager, ... }:

{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    self.nixosModules.strapd
    home-manager.nixosModules.home-manager
  ];

  strapd.enable = true;

  # The disk layout make-disk-image.nix produces for partitionTableType =
  # "efi": a root labeled nixos and an ESP labeled ESP.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
  boot.growPartition = true;

  # systemd-boot lands in the ESP's EFI/BOOT fallback path, which is what a
  # blank OVMF varstore auto-detects, the same way the rig boots everything.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  boot.loader.timeout = 1;

  # tty0 last makes it the primary console (the greeter's VT); ttyS0 feeds
  # the rig's serial.log, which is where boot output goes to be read from
  # outside, the lesson the Arch rig learned the hard way.
  boot.kernelParams = [ "console=ttyS0,115200" "console=tty0" ];

  networking.hostName = "strapd-vm";

  # The rig sshes as root on 2222 with its committed throwaway key
  # (seed/vm_key in the rig's repo); the guest's host key changes on every
  # overlay reset by design.
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE2N/uXz3EGjc36UEo7+sVrQfH3yQJSbEIbDQSWxInTT vm-rig throwaway"
  ];

  users.users.dev = {
    isNormalUser = true;
    initialPassword = "dev";
    extraGroups = [ "wheel" "networkmanager" "video" "docker" ];
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.dev = {
      imports = [ self.homeManagerModules.strapd ];
      strapd.enable = true;
      home.stateVersion = "25.05";
    };
  };

  # In-guest rebuilds (config-only iteration without rebuilding the image)
  # need the flake pushed via the rig's push-repo.sh and a nix that accepts
  # flake commands.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.05";
}
