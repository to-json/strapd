# nixosConfigurations.strapd-iso: a live/demo ISO.
#
# This is a medium to *try* strapd, not to install it: per the NixOS layer's
# dropped-imperative-UX rule, a real machine is provisioned from the user's own
# flake, never by an imperative installer. So this leans on the stock
# installation-cd-minimal profile only for a bootable live environment and then
# puts the strapd desktop on top of it. Boot the ISO, land at the strapd
# login, pick a compositor, look around.
{ config, lib, pkgs, modulesPath, self, home-manager, ... }:

{
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    self.nixosModules.strapd
    home-manager.nixosModules.home-manager
  ];

  strapd.enable = true;

  # The live user the CD profile ships. It autologins on a console getty by
  # default; release that so strapd's greetd owns vt1 and the ISO boots to the
  # strapd login screen rather than a root shell. The account keeps its empty
  # password, which tuigreet accepts.
  services.getty.autologinUser = lib.mkForce null;

  # Seed the strapd user config for the live user through the same
  # home-manager module the reference machine uses, so the demo session is
  # themed and configured exactly like a real one.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.nixos = {
      imports = [ self.homeManagerModules.strapd ];
      strapd.enable = true;
      home.stateVersion = "25.05";
    };
  };

  # The squashfs already carries the whole closure; a second compressor pass
  # over the desktop is slow for no benefit on a throwaway medium.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  networking.hostName = "strapd-live";

  # ISO_STATE_VERSION intentionally matches the CD profile's expectation.
  system.stateVersion = "25.05";
}
