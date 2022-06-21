{ stdenv
, lib
, makeWrapper
, nsf-device-system-config
, coreutils
, gnugrep
, nix-prefetch-git
, nix
, git
, jq
, yq
, gawk
, gnutar
, gzip
}:

stdenv.mkDerivation rec {
  version = "0.1.0";
  pname = "nsf-device-system-config-updater";
  name = "${pname}-${version}";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  propagatedUserEnvPkgs = [
  ];

  propagatedBuildInputs = [
  ];

  buildInputs = [
    nsf-device-system-config
    coreutils
    gnugrep
    nix-prefetch-git
    nix
    git
    jq
    yq
    gawk
    gnutar
    gzip
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
      Tools to update the current nixos system configuration
    '';
  };

  passthru.pname = pname;
}
