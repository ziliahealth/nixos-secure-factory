{ lib
, buildPythonPackage
, mypy
, pytest
, flake8
, ipython
, click
, pyyaml
, nsf-shc-nix-lib
, nsf-factory-common-install-py
}:

buildPythonPackage rec  {
  pname = "nsf-factory-install-py";
  version = "0.1.0";
  src = ./.;
  buildInputs = [ ];
  checkInputs = [
    mypy
    pytest
    flake8
  ];

  doCheck = false;

  checkPhase = ''
    mypy .
    pytest .
    flake8
  '';

  propagatedBuildInputs = [
    click
    pyyaml
    nsf-factory-common-install-py
  ];

  # Allow nix-shell inside nix-shell.
  # See `pkgs/development/interpreters/python/hooks/setuptools-build-hook.sh`
  # for the reason why.
  shellHook = ''
    setuptoolsShellHook
  '';
}
