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

      python = let
        packageOverrides = final: prev: {
          amaranth = prev.amaranth.overridePythonAttrs {
            src = pkgs.fetchFromGitHub {
              owner = "amaranth-lang";
              repo = "amaranth";
              rev = "ba1860553cacfbb5d358f9a9e0699fb7efce0451";
              hash = "sha256-RXHdNIf8S6eHZPswajLY72Fn4zB7P1C9iRcUWqACYT8=";
            };
          };
        };
      in
        pkgs.python3.override {
          inherit packageOverrides;
          self = python;
        };

      niarVer = "0.1.3";
      niarRev = "3b3125d40267b3a2438be8fd647c8ecf35ef7b0d";
      niar = python.pkgs.buildPythonPackage {
        name = "niar";
        src = pkgs.fetchzip {
          url = "https://git.sr.ht/~kivikakk/niar/archive/${niarRev}.tar.gz";
          hash = "sha256-EH64Jl70DXITiZqLCgjCnHlMaS2lYtmkI8aaaRxKbAQ=";
        };
        PDM_BUILD_SCM_VERSION = niarVer;
        pyproject = true;

        build-system = [python.pkgs.pdm-backend];

        propagatedBuildInputs = [
          python.pkgs.amaranth
          python.pkgs.amaranth-boards
        ];

        doCheck = true;
      };
    in rec {
      formatter = pkgs.alejandra;

      packages.default = python.pkgs.buildPythonApplication {
        name = "avacore";
        src = ./.;
        pyproject = true;

        build-system = [python.pkgs.pdm-backend];
        nativeBuildInputs = [
          pkgs.yosys
          pkgs.icestorm
          pkgs.trellis
          pkgs.nextpnr
          pkgs.openfpgaloader
          zig
          zls
        ];
        propagatedBuildInputs = [niar];

        doCheck = true;
        nativeCheckInputs = [
          python.pkgs.pytestCheckHook
          python.pkgs.pytest-xdist
        ];
      };

      apps.default = {
        type = "app";
        program = "${packages.default}/bin/avacore";
      };
    });
}
