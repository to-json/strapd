{
  # strapd on NixOS. This file is deliberately the only Nix at the repo root:
  # a flake cannot reach above its own directory, so the root flake exists to
  # hand the whole tree to nix/, where the NixOS layer lives. The Arch layer
  # (install/, iso/) neither knows nor cares that this file exists.
  description = "strapd: an Arch + Wayland desktop, here with NixOS as the distro";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: import ./nix/outputs.nix inputs;
}
