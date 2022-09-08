{ lib
, buildPythonPackage
, click
, pyyaml
, nsf-ssh-auth-cli
, nsf-shc-nix-lib
}:

buildPythonPackage rec  {
  pname = "nsf-factory-common-install-py";
  version = "0.1.0";
  src = ./.;
  buildInputs = [ ];

  doCheck = false;

  propagatedBuildInputs = [
    click
    pyyaml
    nsf-ssh-auth-cli
  ];

  postInstall = with nsf-shc-nix-lib; ''
    buildPythonPath "$out"

    ${nsfShC.pkg.installClickExesBashCompletion [
      "device-common-ssh-auth-dir"
      "device-ssh-auth-dir"
      "device-state"
      "device-current-state"
    ]}
  '';
}
