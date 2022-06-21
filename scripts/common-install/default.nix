{ stdenv
, lib
, makeWrapper
, nsf-common
, coreutils
, gnugrep
, gnupg
, gopass
, git
, bashInteractive
}:

stdenv.mkDerivation rec {
  version = "0.1.0";
  pname = "nsf-common-install";
  name = "${pname}-${version}";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];


  propagatedUserEnvPkgs = [
    nsf-common
  ];

  propagatedBuildInputs = [
    nsf-common
  ];

  buildInputs = [
    nsf-common
    coreutils
    gnugrep
    gnupg
    gopass
    git
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

  pythonPathDeps = lib.strings.makeSearchPath "python-lib" [
  ];

  binPathDeps = lib.makeBinPath buildInputs;

  installPhase = ''
    mkdir -p "$out/share/${pname}"
    find . -mindepth 1 -maxdepth 1 -exec mv -t "$out/share/${pname}" {} +

    mkdir -p "$out/bin"
    for cmd in $(find "$out/share/${pname}/bin" -mindepth 1 -maxdepth 1); do
      target_cmd_basename="$(basename "$cmd")"
      makeWrapper "$cmd" "$out/bin/$target_cmd_basename" \
        --prefix PATH : "${binPathDeps}" \
        --prefix PATH : "$out/share/${pname}/bin" \
        --prefix PYTHONPATH : "$out/share/${pname}/python-lib" \
        --prefix PYTHONPATH : "${pythonPathDeps}"
    done
  '';

  # Principally required for read -e -i 'Default value'.
  preFixup = ''
    PATH="${bashInteractive}/bin:$PATH" patchShebangs "$out"
  '';

  shellHook = ''
    export PATH="${src}/bin''${binPathDeps:+:}$binPathDeps''${PATH:+:}$PATH"
    export PYTHONPATH="${src}/python-lib''${pythonPathDeps:+:}$pythonPathDeps''${PYTHONPATH:+:}$PYTHONPATH"
  '';

  meta = {
    description = ''
      Some scripts meant to be run on both the nixos device and
      the factory install computer.
    '';
  };

  passthru.pname = pname;
}
