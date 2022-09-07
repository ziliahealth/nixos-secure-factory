{ stdenv
, lib
, makeWrapper
, coreutils
, gnugrep
, nsf-shc-nix-lib
, nsf-common-install
, nsf-device-system-config
, nsf-device-system-config-updater
, openssh
, yq
, jq
, sshfs-fuse
, pwgen
, mkpasswd
, screen
, socat
, picocom
, python3
, virtualbox
, mr
, xclip
, diffutils
, bashInteractive
, remmina
, nsf-factory-common-install-py
}:
let
  pythonLib = nsf-factory-common-install-py;
  pythonPkgs = with python3.pkgs; [
    pythonLib
  ];
  pythonInterpreter = python3.withPackages (pp: pythonPkgs);

in
stdenv.mkDerivation rec {
  version = "0.1.0";
  pname = "nsf-factory-common-install";
  name = "${pname}-${version}";

  src = ./.;

  nativeBuildInputs = [
    makeWrapper
    # Required as we have python shebangs that needs to be patched
    # with a python that has the proper libraries.
    pythonInterpreter
  ];

  propagatedUserEnvPkgs = [
    nsf-common-install
    nsf-device-system-config
    nsf-factory-common-install-py
  ];

  propagatedBuildInputs = [
    mr
    nsf-common-install
    nsf-device-system-config
  ];

  buildInputs = [
    nsf-common-install
    nsf-device-system-config
    coreutils
    gnugrep
    mr # Simplifies working with multiple repos.

    # TODO: Consider removing the openssh dep as the nix
    # version might not work on non-nixos.
    openssh # ssh, sftp, scp, ssh-keygen
    yq # yaml manipulations
    jq # json manipulations
    sshfs-fuse
    pwgen
    mkpasswd

    remmina # provide vncviewer
    screen
    socat
    picocom
    pythonInterpreter

    # TODO: Consider this. Not certain if nix would be capable
    # of introducing this dependency on non nix system as it
    # requires a setuid wrapper.
    # virtualbox

    xclip
    diffutils

    nsf-device-system-config-updater
  ];

  postPatch = ''
    substituteInPlace ./bin/pkg-${pname}-get-sh-lib-dir \
      --replace 'default_pkg_dir=' '# default_pkg_dir=' \
      --replace '$default_pkg_dir/sh-lib' "$out/share/${pname}/sh-lib"

    substituteInPlace ./bin/pkg-${pname}-get-root-dir \
      --replace 'default_pkg_dir=' '# default_pkg_dir=' \
      --replace '$default_pkg_dir' "$out/share/${pname}"

    ! test -e "./.local-env.sh" || rm ./.local-env.sh
  '';


  binPathDeps = lib.makeBinPath buildInputs;

  buildPhase = "true";

  installPhase = with nsf-shc-nix-lib; ''
    mkdir -p "$out/share/${pname}"
    find . -mindepth 1 -maxdepth 1 -exec mv -t "$out/share/${pname}" {} +

    mkdir -p "$out/bin"
    for cmd in $(find "$out/share/${pname}/bin" -mindepth 1 -maxdepth 1); do
      target_cmd_basename="$(basename "$cmd")"
      makeWrapper "$cmd" "$out/bin/$target_cmd_basename" \
        --prefix PATH : "${binPathDeps}" \
        --prefix PATH : "$out/share/${pname}/bin"
    done
  '';

  meta = {
    description = ''
      Some scripts meant to be run by the factory technician
      to install nixos on new devices.
    '';
  };

  passthru = {
    inherit pname;
    python-interpreter = pythonInterpreter;
    python-packages = pythonPkgs;
    python-lib = pythonLib;
  };
}
