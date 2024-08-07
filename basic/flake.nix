{
  description = "Ava BASIC development shell";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;

    zig-overlay.url = github:mitchellh/zig-overlay;
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
    zig-overlay.inputs.flake-utils.follows = "flake-utils";

    zls-flake.url = github:zigtools/zls;
    zls-flake.inputs.nixpkgs.follows = "nixpkgs";
    zls-flake.inputs.flake-utils.follows = "flake-utils";
    zls-flake.inputs.zig-overlay.follows = "zig-overlay";
    zls-flake.inputs.gitignore.follows = "gitignore";

    gitignore.url = github:hercules-ci/gitignore.nix;
    gitignore.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig-overlay,
    zls-flake,
    gitignore,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      zig = zig-overlay.packages.${system}.master;
      zls = zls-flake.packages.${system}.zls;
      gitignoreSource = gitignore.lib.gitignoreSource;
    in rec {
      formatter = pkgs.alejandra;

      devShells.default = pkgs.mkShell {
        name = "avabasic";
        nativeBuildInputs = [
          zig
          zls
        ];
      };

      packages.default = packages.avabasic;
      packages.avabasic = pkgs.stdenvNoCC.mkDerivation {
        name = "avabasic";
        version = "main";
        src = gitignoreSource ./.;
        nativeBuildInputs = [zig];
        dontConfigure = true;
        dontInstall = true;
        doCheck = true;
        buildPhase = ''
          mkdir -p .cache
          ln -s ${pkgs.callPackage ./deps.nix {}} .cache/p
          zig build install --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache -Doptimize=ReleaseSafe --prefix $out
        '';
        checkPhase = ''
          zig build test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache
        '';
      };
    });
}
