{
  description = "Ava BASIC";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;

    zig-overlay.url = github:mitchellh/zig-overlay;
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
    zig-overlay.inputs.flake-utils.follows = "flake-utils";

    zls-flake.url = github:zigtools/zls/0.13.0;
    zls-flake.inputs.nixpkgs.follows = "nixpkgs";
    zls-flake.inputs.flake-utils.follows = "flake-utils";
    zls-flake.inputs.zig-overlay.follows = "zig-overlay";
    zls-flake.inputs.gitignore.follows = "gitignore";

    gitignore.url = github:hercules-ci/gitignore.nix;
    gitignore.inputs.nixpkgs.follows = "nixpkgs";

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
    zig-overlay,
    zls-flake,
    gitignore,
    niar-flake,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      zig = zig-overlay.packages.${system}."0.13.0";
      zls = zls-flake.packages.${system}.zls;
      gitignoreSource = gitignore.lib.gitignoreSource;
      python = niar-flake.packages.${system}.python;
      niar = niar-flake.packages.${system}.niar;

      basic-deps = pkgs.callPackage ./basic/deps.nix {};
      soc-deps = pkgs.callPackage ./soc/deps.nix {inherit python;};
      # TODO: when we have internet
      # adc-deps = pkgs.callPackage ./adc/deps.nix {};

      python-de = with python.pkgs; [
        python-lsp-server
        pyls-isort
        pylsp-rope
      ];
    in rec {
      formatter = pkgs.alejandra;

      devShells.default = pkgs.mkShell {
        name = "ava";
        inputsFrom = [
          devShells.zig
          devShells.avasoc
        ];
      };

      packages.avabasic = pkgs.stdenvNoCC.mkDerivation {
        name = "avabasic";
        version = "main";
        src = gitignoreSource ./basic;
        nativeBuildInputs = [zig];
        dontConfigure = true;
        dontInstall = true;
        doCheck = true;
        buildPhase = ''
          mkdir -p .cache
          ln -s ${basic-deps} .cache/p
          zig build install --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache -Doptimize=ReleaseSafe --prefix $out
        '';
        checkPhase = ''
          zig build test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache
        '';
      };

      packages.avacore = pkgs.stdenvNoCC.mkDerivation {
        name = "avacore";
        version = "main";
        src = gitignoreSource ./core;
        nativeBuildInputs = [
          zig
          pkgs.llvmPackages.bintools
        ];
        dontConfigure = true;
        dontInstall = true;
        doCheck = true;
        buildPhase = ''
          mkdir -p .cache
          zig build install --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache -Doptimize=ReleaseSafe --prefix $out
        '';
        checkPhase = ''
          zig build test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache
        '';
      };

      devShells.zig = pkgs.mkShell {
        name = "zig";
        nativeBuildInputs = [
          zig
          zls
          pkgs.llvmPackages.bintools
          pkgs.libiconv
        ];
      };

      packages.avasoc = python.pkgs.buildPythonApplication {
        name = "avasoc";
        src = ./soc;
        pyproject = true;

        build-system = [python.pkgs.pdm-backend];
        nativeBuildInputs = [pkgs.makeWrapper];
        buildInputs = [];
        propagatedBuildInputs = [
          niar
          soc-deps.amaranth-stdio
          soc-deps.amaranth-soc
        ];

        doCheck = true;
        nativeCheckInputs = with python.pkgs; [
          python.pkgs.pytestCheckHook
          python.pkgs.pytest-xdist
          packages.avabasic
        ];

        postFixup = ''
          wrapProgram $out/bin/avasoc \
            --run 'export NIAR_WORKING_DIRECTORY="$(pwd)"'
        '';
      };

      devShells.avasoc = pkgs.mkShell {
        name = "avasoc";

        buildInputs =
          python-de
          ++ (with python.pkgs; [
            pytest
            pytest-xdist
            soc-deps.pytest-watcher
            zig
            zls
          ]);

        inputsFrom = [packages.avasoc];
      };

      devShells.avasoc-pdm = pkgs.mkShell {
        name = "avasoc-pdm";

        buildInputs =
          python-de
          ++ [
            pkgs.python3
            pkgs.pdm
            pkgs.yosys
            pkgs.icestorm
            pkgs.nextpnr
            zig
            zls
          ];
      };

      # TODO: when we have internet
      # packages.adc = pkgs.stdenvNoCC.mkDerivation {
      #   name = "adc";
      #   version = "main";
      #   src = gitignoreSource ./adc;
      #   nativeBuildInputs = [zig
      #   pkgs.libiconv];
      #   dontConfigure = true;
      #   dontInstall = true;
      #   doCheck = true;
      #   buildPhase = ''
      #     mkdir -p .cache
      #     ln -s ${adc-deps} .cache/p
      #     zig build install --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache -Doptimize=ReleaseSafe --prefix $out
      #   '';
      #   checkPhase = ''
      #     zig build test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache
      #   '';
      # };
    });
}
