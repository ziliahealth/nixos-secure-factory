{ stdenv
, lib
, nsf-device-common-install
, makeWrapper
, coreutils
, gnugrep
, usbutils
, procps
}:

stdenv.mkDerivation rec {
  version = "0.1.0";
  pname = "nixos-device-type-install";
  name = "${pname}-${version}";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  propagatedUserEnvPkgs = [
    nsf-device-common-install
  ];

  propagatedBuildInputs = [
    nsf-device-common-install
  ];

  buildInputs = [
    nsf-device-common-install
    # For the common lib *.sh.
    coreutils
    gnugrep
    usbutils
    procps
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

  installPhase = ''
    mkdir -p "$out/share/${pname}"
    find . -mindepth 1 -maxdepth 1 -exec mv -t "$out/share/${pname}" {} +

    mkdir -p "$out/bin"
    for cmd in $(find "$out/share/${pname}/bin" -mindepth 1 -maxdepth 1); do
      target_cmd_basename="$(basename "$cmd")"
      makeWrapper "$cmd" "$out/bin/$target_cmd_basename" \
        --prefix PATH : "${lib.makeBinPath buildInputs}" \
        --prefix PATH : "$out/share/${pname}/bin"
    done
  '';

  meta = {
    description = ''
      Some scripts meant to be run on new nixos devices of a specific type when
      first installed.
    '';
  };

  passthru.pname = pname;
}
