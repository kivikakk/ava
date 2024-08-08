{
  description = "Ava BASIC core development environment";

  # NOTE: I'd love to use pdm2nix or something like that, but An Attempt Was
  # Made and it was erroring out somewhere deep between it, pyproject-nix and
  # nixpkgs. ¯\_(ツ)_/¯  Another day.
  #
  # That this is the "simple" solution is slightly horrifying.

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;

    zig-overlay = {
      url = github:mitchellh/zig-overlay;
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    zls-flake = {
      url = github:zigtools/zls;
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.zig-overlay.follows = "zig-overlay";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig-overlay,
    zls-flake,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      zig = zig-overlay.packages.${system}.master;
      zls = zls-flake.packages.${system}.zls;

      niar-pkg = import ./niar.nix {inherit pkgs;};
      inherit (niar-pkg) python niar toolchain-pkgs;
    in rec {
      formatter = pkgs.alejandra;

      packages.default = python.pkgs.buildPythonApplication {
        name = "avacore";
        src = ./.;
        pyproject = true;

        build-system = [python.pkgs.pdm-backend];
        nativeBuildInputs = [pkgs.makeWrapper];
        propagatedBuildInputs = [niar];

        doCheck = true;
        nativeCheckInputs = [
          python.pkgs.pytestCheckHook
          python.pkgs.pytest-xdist
        ];

        postFixup = ''
          wrapProgram $out/bin/avacore \
            --run 'export NIAR_WORKING_DIRECTORY="$(pwd)"'
        '';
      };

      apps.default = {
        type = "app";
        program = "${packages.default}/bin/avacore";
      };

      devShells.default = pkgs.mkShell {
        name = "avacore";

        buildInputs = [
          python.pkgs.python-lsp-server
          python.pkgs.pyls-isort
          python.pkgs.pylsp-rope
          (packages.default.override {doCheck = false;})
          python.pkgs.pytest
          python.pkgs.pytest-xdist
        ];
      };

      devShells.pure-python = pkgs.mkShell {
        name = "avacore-pure-python";

        buildInputs =
          [
            pkgs.python3
            pkgs.pdm
            zig
            zls
          ]
          ++ toolchain-pkgs;
      };
    });
}
