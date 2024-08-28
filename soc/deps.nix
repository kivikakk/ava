{
  pkgs,
  python,
  ...
}: {
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
}
