{pkgs}: let
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
  };

  amaranth-boards = python.pkgs.amaranth-boards.overridePythonAttrs rec {
    version = "0.1.dev249+g${pkgs.lib.substring 0 7 src.rev}";
    src = pkgs.fetchFromGitHub {
      owner = "amaranth-lang";
      repo = "amaranth-boards";
      rev = "19b97324ecf9111c5d16377af79f82aad761c476";
      postFetch = "rm -f $out/.git_archival.txt $out/.gitattributes";
      hash = "sha256-0uvn91i/yuIY75lL5Oxvozdw7Q2Uw83JWo7srgEYEpI=";
    };

    build-system = [python.pkgs.pdm-backend];
  };

  niar = python.pkgs.buildPythonPackage {
    name = "niar";
    version = "0.1.3";
    src = pkgs.fetchzip {
      url = "https://git.sr.ht/~kivikakk/niar/archive/a478292edabfee100c450a59d0898f3f6bf91c51.tar.gz";
      hash = "sha256-GJkk6BmbodHqX40Dc16Eek+ReWRoqlebZVvfJrEYCFM=";
    };
    pyproject = true;

    build-system = [python.pkgs.pdm-backend];

    propagatedBuildInputs =
      [
        # These seem correctly placed.
        python.pkgs.amaranth
        amaranth-boards
        amaranth-stdio
      ]
      ++
      # These here I'm unsure of. Seems to work for now, with:
      # $ nix run . build
      # $ nix develop -c fish -c 'python -m avacore build'
      # What was it failing with before that made us try propagatedNativeBuildInputs?
      toolchain-pkgs;

    doCheck = true;
  };

  toolchain-pkgs = with pkgs; [
    yosys
    icestorm
    trellis
    nextpnr
    openfpgaloader
  ];
in {
  inherit python niar pytest-watcher toolchain-pkgs;
}
