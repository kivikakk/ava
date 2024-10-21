{
  description = "Ava BASIC";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
    flake-utils.url = github:numtide/flake-utils;

    zig-overlay.url = github:mitchellh/zig-overlay;
    zig-overlay.inputs.nixpkgs.follows = "nixpkgs";
    zig-overlay.inputs.flake-utils.follows = "flake-utils";

    zls.url = github:zigtools/zls/0.13.0;
    zls.inputs.nixpkgs.follows = "nixpkgs";
    zls.inputs.flake-utils.follows = "flake-utils";
    zls.inputs.zig-overlay.follows = "zig-overlay";
    zls.inputs.gitignore.follows = "gitignore";

    gitignore.url = github:hercules-ci/gitignore.nix;
    gitignore.inputs.nixpkgs.follows = "nixpkgs";

    niar = {
      url = github:charlottia/niar;
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    zig-overlay,
    gitignore,
    ...
  } @ inputs:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      zig = zig-overlay.packages.${system}."0.13.0";
      zls = inputs.zls.packages.${system}.zls;
      gitignoreSource = gitignore.lib.gitignoreSource;
      python = inputs.niar.packages.${system}.python;
      niar = inputs.niar.packages.${system}.niar;

      basic-deps = pkgs.callPackage ./basic/deps.nix {};
      soc-deps = pkgs.callPackage ./soc/deps.nix {inherit python;};
      adc-deps = pkgs.callPackage ./adc/deps.nix {};

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

      # TODO: zon2nix doesn't support path-based dependencies.
      # packages.avacore = pkgs.stdenvNoCC.mkDerivation {
      #   name = "avacore";
      #   version = "main";
      #   src = gitignoreSource ./core;
      #   nativeBuildInputs = [
      #     zig
      #     pkgs.llvmPackages.bintools
      #   ];
      #   dontConfigure = true;
      #   dontInstall = true;
      #   doCheck = true;
      #   buildPhase = ''
      #     mkdir -p .cache
      #     zig build install --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache -Doptimize=ReleaseSafe --prefix $out
      #   '';
      #   checkPhase = ''
      #     zig build test --cache-dir $(pwd)/.zig-cache --global-cache-dir $(pwd)/.cache
      #   '';
      # };

      devShells.zig = pkgs.mkShell {
        name = "zig";
        nativeBuildInputs = [
          zig
          zls
          pkgs.llvmPackages.bintools
          # adc
          pkgs.libiconv
          pkgs.SDL2
          pkgs.pkg-config # See shellHook.
        ];

        shellHook = ''
          # See https://github.com/ziglang/zig/issues/18998.
          unset NIX_CFLAGS_COMPILE
          unset NIX_LDFLAGS
        '';
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

      # TODO: zon2nix doesn't support path-based dependencies.
      # packages.adc = pkgs.stdenvNoCC.mkDerivation {
      #   name = "adc";
      #   version = "main";
      #   src = gitignoreSource ./adc;
      #   nativeBuildInputs = [
      #     zig
      #     pkgs.libiconv
      #   ];
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
