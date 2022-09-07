#!/usr/bin/env bash

get_device_config_etc_dir() {
  echo "/etc/nixos-device-system-config"
}


get_device_config_etc_nix_search_path_dir() {
  echo "$(get_device_config_etc_dir)/nix-search-path"
}


get_search_path_srcs_from_system_cfg_dir() {
  local system_cfg_dir="$1"
  find "${system_cfg_dir}$(get_device_config_etc_nix_search_path_dir)" -mindepth 1 -maxdepth 1
}


build_nix_search_path_args_from_search_path_srcs() {
  # Use name ref for the output.
  # shellcheck disable=SC2178
  declare -n out_array="$1"
  local search_path_srcs="$2"

  out_array=()
  while read -r path; do
    local pathName
    pathName="$(basename "$path")"
    out_array+=( "-I" "$pathName=$path" )
  done < <(echo "$search_path_srcs")
}


build_nix_search_path_args_from_system_cfg_dir() {
  local out_array_var_name="$1"
  local system_cfg_dir="$2"

  local search_path_srcs
  search_path_srcs="$(get_search_path_srcs_from_system_cfg_dir "$system_cfg_dir")"

  build_nix_search_path_args_from_search_path_srcs "$out_array_var_name" "$search_path_srcs"
}


# TODO: Move into a more generic pkg / module.
build_nixos_config_dir() {
  echo "build_nixos_config_dir begin"
  local out_var_name="$1"
  local config_filename="$2"
  shift
  shift
  # Remaing arguments passed directly to 'nix build'.

  local tmpdir
  tmpdir="$(mktemp -d)"

  local outLink="$tmpdir/nixos_config_dir"

  nix build \
    -v \
    --show-trace \
    --out-link "$outLink" \
    -f "$config_filename" \
    "$@" \
    || { rm -rf "$tmpdir"; return 1; }

  local out_val
  out_val=$(readlink -f "$outLink") \
    || { rm -rf "$tmpdir"; return 1; }

  rm -rf "$tmpdir"

  eval "$out_var_name='$out_val'"
  echo "build_nixos_config_dir end"
}


build_device_config_dir() {
  echo "build_device_config_dir begin"
  local out_var_name="$1"
  local config_filename="$2"
  local device_id="$3"
  shift
  shift
  shift
  # Remaing arguments passed directly to 'nix build'.

  build_nixos_config_dir "$out_var_name" "$config_filename" \
    --argstr "deviceIdentifier" "$device_id" \
    "$@"

  echo "build_device_config_dir end"
}


_parse_user_search_path_overrides_args() {
  # shellcheck disable=SC2178
  declare -n _out_nix_search_path_overrides_a="$1"
  shift 1

  _out_nix_search_path_overrides_a=()
  declare -gA _out_nix_search_path_overrides_aa=() # Global associative array.

  local i
  local j
  local k

  while [ "$#" -gt 0 ]; do
      i="$1"; shift 1
      case "$i" in
        -I)
          j="$1"; shift 1
          _out_nix_search_path_overrides_a+=("$j")
          ;;
        --max-jobs|-j|--cores|--builders)
          j="$1"; shift 1
          _out_nix_build_fwd_flags+=("$i" "$j")
          ;;
        --show-trace|--keep-failed|-K|--keep-going|-k|--verbose|-v|-vv|-vvv|-vvvv|-vvvvv|--fallback|--repair|--no-build-output|-Q|-j*)
          _out_nix_build_fwd_flags+=("$i")
          ;;
        --option)
          j="$1"; shift 1
          k="$1"; shift 1
          _out_nix_build_fwd_flags+=("$i" "$j" "$k")
          ;;
        *)
          1>&2 echo "ERROR: $0: _parse_build_device_config_args: unknown option '$i'"
          return 1
          ;;
      esac
  done
}


create_aa_from_parsed_serach_path_override_args() {
    # shellcheck disable=SC2178
    declare -n _out_nix_search_path_overrides_aa="${1?}"
    shift 1

    declare -gA _out_nix_search_path_overrides_aa=() # Global associative array.

    [[ $# -gt 0 ]] || return 0

    while IFS= read -d '' -r sp_override; do
      local key
      key="$(echo "$sp_override" | awk -F '=' '{ print $1}')"
      local value
      value="$(echo "$sp_override" | awk -F '=' '{ print $2}')"
      # echo "key='$key'; value='$value'"
      # shellcheck disable=SC2034
      _out_nix_search_path_overrides_aa["$key"]="$value"
    done < <(printf "%s\0" "$@")
}


# shellcheck disable=2120 # Optional arguments.
build_device_config_system_closure() {
  echo "build_device_config_system_closure begin"
  local out_var_name="$1"
  local system_cfg_dir="$2"
  shift 2
  # Remaing arguments passed directly to 'nix build'.

  local tmpdir
  tmpdir="$(mktemp -d)"

  local configdir
  configdir="$(mktemp -d)"

  cp --no-preserve=ownership,mode -rT $system_cfg_dir $configdir
  system_cfg_dir=$configdir

  local outLink="$tmpdir/system"

  local search_path_args=()
  build_nix_search_path_args_from_system_cfg_dir "search_path_args" "$system_cfg_dir"

  local search_path_args_overrides_a=()

  _parse_user_search_path_overrides_args \
    "search_path_args_overrides_a" "$@"

  # echo "search_path_args_overrides_a='$(printf "%s\n" "${search_path_args_overrides_a[@]}" | paste -s -d',')'"

  declare -A search_path_args_overrides_aa=() # Associative array.
  create_aa_from_parsed_serach_path_override_args \
    "search_path_args_overrides_aa" "${search_path_args_overrides_a[@]}"

  # echo "search_path_args_overrides_aa='$(printf "%s\n" "${search_path_args_overrides_aa[@]}" | paste -s -d',')'"

  # The nixos's nixpkgs sources (nixos channel).
  local nixos_src_from_sp_dir
  nixos_src_from_sp_dir="${system_cfg_dir}$(get_device_config_etc_nix_search_path_dir)/nixos"

  local nixos_src
  nixos_src="${search_path_args_overrides_aa["nixos"]:-$nixos_src_from_sp_dir}"
  # echo "nixos_src='$nixos_src'"

  # We call nix build with user custom args in front of
  # filtered_search_path_args ones. This is bause the leftmost
  # arg has priority over the rightmost one (-I in particular).
  # This will allow the user to override some of the fixed -I
  # instructions here.
  nix build \
    -v \
    --show-trace \
    --out-link "$outLink" \
    -f "$nixos_src/nixos" \
    "$@" \
    -I "nixos-config=${system_cfg_dir}$(get_device_config_etc_dir)/configuration.nix" \
    "${search_path_args[@]}" \
    system \
    || { rm -rf "$tmpdir"; rm -rf "$configdir"; return 1; }

  local out_val
  out_val=$(readlink -f "$outLink") \
    || { rm -rf "$tmpdir"; rm -rf "$configdir"; return 1; }
  rm -rf "$tmpdir"
  rm -rf "$configdir"

  eval "$out_var_name='$out_val'"
  echo "build_device_config_system_closure end"
}
