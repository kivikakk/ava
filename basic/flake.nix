{
  description = "Ava BASIC development shell";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;

    zig-overlay.url = github:mitchellh/zig-overlay;
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
    zig-overlay.inputs.flake-utils.follows = "flake-utils";

    zls.url = github:zigtools/zls;
    zls.inputs.nixpkgs.follows = "nixpkgs";
    zls.inputs.flake-utils.follows = "flake-utils";
    zls.inputs.zig-overlay.follows = "zig-overlay";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig-overlay,
    zls,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      zig = zig-overlay.packages.${system}.master;
    in {
      formatter = pkgs.alejandra;

      devShells.default = pkgs.mkShell {
        name = "ava";
        nativeBuildInputs = [
          zig-overlay.packages.${system}.master
          zls.packages.${system}.zls
        ];
      };
    });
}
