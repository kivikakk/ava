{
  description = "Ava BASIC SoC development environment";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;

    avabasic-flake = {
      url = path:../basic;
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    niar-flake = {
      url = git+https://git.sr.ht/~kivikakk/niar;
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    avabasic-flake,
    niar-flake,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      zig = avabasic-flake.inputs.zig-overlay.packages.${system}.master;
      zls = avabasic-flake.inputs.zls-flake.packages.${system}.zls;
      avabasic = avabasic-flake.packages.${system}.avabasic;

      python = niar-flake.packages.${system}.python;
      niar = niar-flake.packages.${system}.niar;

      pytest-watcher = python.pkgs.buildPythonPackage rec {
        pname = "pytest_watcher";
        version = "0.4.2";
        src = pkgs.fetchPypi {
          inherit pname version;
          hash = "sha256-eykvAlyhlhfNdWfCKMYYe1CH8tqeTSz24UTldkoEcbA=";
        };
        pyproject = true;

        build-system = [python.pkgs.poetry-core];

        dependencies = with python.pkgs; [
          watchdog
          tomli
        ];
      };

      amaranth-stdio = python.pkgs.buildPythonPackage rec {
        pname = "amaranth-stdio";
        version = "0.1.dev34+g${pkgs.lib.substring 0 7 src.rev}";
        src = pkgs.fetchFromGitHub {
          owner = "kivikakk";
          repo = "amaranth-stdio";
          rev = "ca4fac262a2290495c82d76aa785bd8707afa781";
          # hash = "sha256-75CSOTCo0D4TV5GKob5Uw3CZR3tfLoaT2xbH2I3JYA8=";   # <-- from NixOS
          hash = "sha256-mO5YPz5zCgjvu7KRrD1omVZXZ2Q7/v/7D1NotG1NHqA="; # <-- from nix-darwin
        };
        pyproject = true;

        build-system = [python.pkgs.pdm-backend];

        dependencies = [python.pkgs.amaranth];

        dontCheckRuntimeDeps = 1; # amaranth 0.6.0.devX doesn't match anything.
      };
    in rec {
      formatter = pkgs.alejandra;

      packages.default = python.pkgs.buildPythonApplication {
        name = "avasoc";
        src = ./.;
        pyproject = true;

        build-system = [python.pkgs.pdm-backend];
        nativeBuildInputs = [pkgs.makeWrapper];
        buildInputs = [avabasic];
        propagatedBuildInputs = [
          niar
          amaranth-stdio
        ];

        doCheck = true;
        nativeCheckInputs = with python.pkgs; [
          python.pkgs.pytestCheckHook
          python.pkgs.pytest-xdist
          avabasic
        ];

        postFixup = ''
          wrapProgram $out/bin/avasoc \
            --run 'export NIAR_WORKING_DIRECTORY="$(pwd)"'
        '';
      };

      apps.default = {
        type = "app";
        program = "${packages.default}/bin/avasoc";
      };

      devShells.default = pkgs.mkShell {
        name = "avasoc";

        buildInputs = with python.pkgs; [
          python-lsp-server
          pyls-isort
          pylsp-rope
          pytest
          pytest-xdist
          pytest-watcher
          zig
          zls
          avabasic
        ];

        inputsFrom = [packages.default];
      };

      devShells.pure-python = pkgs.mkShell {
        name = "avasoc-pure-python";

        buildInputs = [
          pkgs.python3
          pkgs.pdm
          zig
          zls
          avabasic
        ];
      };
    });
}
