#!/usr/bin/env bash
common_sh_lib_dir="$(pkg-nsf-common-get-sh-lib-dir)"
# shellcheck source=sh_stream.sh
. "$common_sh_lib_dir/sh_stream.sh"

common_factory_install_sh_lib_dir="$(pkg-nsf-factory-common-install-get-sh-lib-dir)"
# shellcheck source=SCRIPTDIR/../sh-lib/prompt.sh
. "$common_factory_install_sh_lib_dir/prompt.sh"
# shellcheck source=SCRIPTDIR/../sh-lib/gpg.sh
. "$common_factory_install_sh_lib_dir/gpg.sh"
# shellcheck source=SCRIPTDIR/../sh-lib/gopass.sh
. "$common_factory_install_sh_lib_dir/gopass.sh"
# shellcheck source=SCRIPTDIR/../sh-lib/app_factory_info_store.sh
. "$common_factory_install_sh_lib_dir/app_factory_info_store.sh"
# shellcheck source=SCRIPTDIR/../sh-lib/workspace_paths.sh
. "$common_factory_install_sh_lib_dir/workspace_paths.sh"
# shellcheck source=SCRIPTDIR/../sh-lib/app_factory_gopass_vaults_ro.sh
. "$common_factory_install_sh_lib_dir/app_factory_gopass_vaults_ro.sh"


is_factory_gopass_main_store_initialized() {
  local gpg_key_id
  read_or_prompt_for_factory_info__user_gpg_default_id "gpg_key_id" \
    || return 1

  local gopass_home_dir
  gopass_home_dir="$(get_gopass_home_dir)"

  # && factory-gopass --yes mounts | head -n 1 | grep -q "$gopass_home_dir/.password-store" \
  test -e "$gopass_home_dir/.password-store"
}


list_gopass_main_store_and_config_files() {
  local gopass_home_dir
  gopass_home_dir="$(get_gopass_home_dir)"

  local files
  files="$(
    test -d "$gopass_home_dir/.config/gopass" \
      && find "$gopass_home_dir/.config/gopass" -mindepth 1 -type f
    find "$gopass_home_dir/.config" -mindepth 1 -maxdepth 1 -type d -name gopass
    find "$gopass_home_dir" -mindepth 1 -maxdepth 1 -type d -name '.password-store*'
  )"
  printf "%s" "$files" | grep ^
}


rm_factory_gopass_main_store_and_config() {
  print_title_lvl4 "Removing factory gopass main store and config"

  local to_be_rm_files
  if ! to_be_rm_files="$(list_gopass_main_store_and_config_files)"; then
    echo "Nothing to remove."
    return 0
  fi

  echo "The following files will be removed:"
  echo "$to_be_rm_files" | awk '{ print "  " $0 }'
  prompt_for_user_approval "" || return 1

  echo "Removing the files."
  echo "$to_be_rm_files" | xargs -r rm -r --
}


init_factory_gopass_main_store_and_config() {
  print_title_lvl4 "Initializing factory gopass main store and config"

  if is_factory_gopass_main_store_initialized; then
    echo "Factory gopass main store already initialized."
    return 0
  fi

  local gpg_key_id
  read_or_prompt_for_factory_info__user_gpg_default_id "gpg_key_id"

  echo_eval "factory-gopass --yes init '$gpg_key_id'"
}


_configure_factory_gopass_secrets_stores() {
  stores_ids="$(
    get_gopass_factory_only_vault_id
    get_gopass_device_vault_id
  )"

  for sid in $stores_ids; do
    configure_gopass_store "$sid"
  done
}


is_factory_only_gopass_secrets_store_already_mount() {
  local sdir
  sdir="$(get_gopass_factory_only_vault_repo_dir)"
  factory-gopass mounts | grep -q "(${sdir})"
}


mount_factory_only_gopass_secrets_store_if_required() {
  print_title_lvl4 "Mounting factory only gopass secret stores"

  if ! is_factory_only_gopass_secrets_store_already_mount; then
    echo "Already mounted."
    return 0
  fi

  init_factory_gopass_main_store_and_config

  local gpg_key_id
  read_or_prompt_for_factory_info__user_gpg_default_id "gpg_key_id"

  local sid
  sid="$(get_gopass_factory_only_vault_id)"
  local sdir
  sdir="$(get_gopass_factory_only_vault_repo_dir)"

  echo_eval "factory-gopass mounts add " \
    "'$sid'" \
    "'$sdir' || true"

  configure_gopass_store "$sid"
}


mount_factory_gopass_secrets_stores() {
  print_title_lvl4 "Mounting factory gopass secret stores"

  init_factory_gopass_main_store_and_config

  local gpg_key_id
  read_or_prompt_for_factory_info__user_gpg_default_id "gpg_key_id"

  # TODO: In case already mounted, validate that it points to expected repo.
  # TODO: Retrieve from factory config state.
  echo_eval "factory-gopass mounts add " \
    "'$(get_gopass_factory_only_vault_id)'" \
    "'$(get_gopass_factory_only_vault_repo_dir)' || true"
  echo_eval "factory-gopass mounts add " \
    "'$(get_gopass_device_vault_id)'" \
    "'$(get_gopass_device_vault_repo_dir)' || true"

  _configure_factory_gopass_secrets_stores
}


umount_factory_gopass_secrets_stores() {
  print_title_lvl4 "Unmounting factory gopass secret stores"

  init_factory_gopass_main_store_and_config

  echo_eval "factory-gopass mounts remove '$(get_gopass_factory_only_vault_id)'"
  echo_eval "factory-gopass mounts remove '$(get_gopass_device_vault_id)'"
}


mount_gopass_device_substore() {
  local sskey
  sskey="$(get_gopass_device_substore_key "$@")" || return 1
  local ssdir
  ssdir="$(get_gopass_device_substore_dir "$@")" || return 1

  print_title_lvl5 "Mounting device substore at '$sskey' from '$ssdir'"

  if exists_gopass_device_substore "$@"; then
    echo "Device secret store already exists."
    return 0
  fi

  local factory_gpg_key_id
  read_or_prompt_for_factory_info__user_gpg_default_id "factory_gpg_key_id"

  echo_eval "factory-gopass mounts add '$sskey' '$ssdir' || true"
  configure_gopass_store "$sskey"
}


umount_gopass_device_substore() {
  local sskey
  sskey="$(get_gopass_device_substore_key "$@")" || return 1

  print_title_lvl5 "Unmounting device substore at '$sskey'"

  if ! exists_gopass_device_substore "$@"; then
    echo "Device secret store does not exists. Nothing to unmount."
    return 0
  fi

  echo_eval "factory-gopass mounts remove '$sskey'"
}


mount_gopass_factory_only_device_substore() {
  local sskey
  sskey="$(get_gopass_device_factory_only_substore_key "$@")" || return 1
  local ssdir
  ssdir="$(get_gopass_device_factory_only_substore_dir "$@")" || return 1

  print_title_lvl5 "Mounting device factory only substore at '$sskey' from '$ssdir'"

  if exists_gopass_factory_only_device_substore "$@"; then
    echo "Device factory only secret store already exists."
    return 0
  fi

  local factory_gpg_key_id
  read_or_prompt_for_factory_info__user_gpg_default_id "factory_gpg_key_id"

  echo_eval "factory-gopass mounts add '$sskey' '$ssdir' || true"
  configure_gopass_store "$sskey"
}


umount_gopass_factory_only_device_substore() {
  local sskey
  sskey="$(get_gopass_device_substore_key "$@")" || return 1

  print_title_lvl5 "Unmounting device factory only substore at '$sskey'"

  if ! exists_gopass_factory_only_device_substore "$@"; then
    echo "Device secret store does not exists. Nothing to unmount."
    return 0
  fi

  echo_eval "factory-gopass mounts remove '$sskey'"
}


mount_gopass_factory_device_substores() {
  mount_gopass_device_substore "$@" \
    && mount_gopass_factory_only_device_substore "$@"
}


umount_gopass_factory_device_substores() {
  umount_gopass_device_substore "$@" \
    && umount_gopass_factory_only_device_substore "$@"
}


rm_no_prompt_gopass_device_substore() {
  sskey="$(get_gopass_device_substore_key "$@")"

  print_title_lvl5 "${FUNCNAME[0]}"

  if ! exists_gopass_device_substore "$@"; then
    echo "Device secret store does not exists. Nothing to remove."
    return 0
  fi

  umount_gopass_cdevice_substore "$@"
  echo_eval "factory-gopass --yes rm -r '$sskey'"
}


rm_no_prompt_gopass_factory_only_device_substore() {
  print_title_lvl5 "${FUNCNAME[0]}"

  sskey="$(get_gopass_device_factory_only_substore_key "$@")"

  if ! exists_gopass_factory_only_device_substore "$@"; then
    echo "Factory only device secret store does not exists. Nothing to remove."
    return 0
  fi

  umount_gopass_factory_only_device_substore "$@"
  echo_eval "factory-gopass --yes rm -r '$sskey'"
}


rm_no_prompt_gopass_factory_device_substores() {
  rm_no_prompt_gopass_device_substore "$@" \
    && rm_no_prompt_gopass_factory_only_device_substore "$@"
}


list_all_device_names_from_gopass_factory_vaults_and_device_config() {
  local device_config
  device_config="$(get_device_cfg_repo_root_dir)"
  local device_secrets_repo_root
  device_secrets_repo_root="$(get_gopass_device_vault_repo_dir)"
  local factory_secrets_repo_root
  factory_secrets_repo_root="$(get_gopass_factory_only_vault_repo_dir)"

  local device_search_path=(
    "$device_config/device" \
    "$device_secrets_repo_root/device" \
    "$factory_secrets_repo_root/device" \
  )

  [[ "${#device_search_path[@]}" -eq 0 ]] || \
    find \
      "${device_search_path[@]}" \
      -mindepth 1 -maxdepth 1 -exec basename {} \; | \
        grep -v -E  -e '^.git$' -e '^.public-keys$' -e '^.gpg-id$' \
          -e '^device$' -e '^device-family$' -e '^device-type$' | \
        sort | uniq
}


list_all_device_names_from_gopass_device_secret_vault() {
  local device_secrets_repo_root
  device_secrets_repo_root="$(get_gopass_device_vault_repo_dir)"

  local device_search_path=(
    "$device_secrets_repo_root/device" \
  )

  [[ "${#device_search_path[@]}" -eq 0 ]] || \
    find \
      "${device_search_path[@]}" \
      -mindepth 1 -maxdepth 1 -exec basename {} \; | \
        grep -v -E  -e '^.git$' -e '^.public-keys$' -e '^.gpg-id$' \
          -e '^device$' -e '^device-family$' -e '^device-type$' | \
        sort | uniq
}


mount_all_gopass_factory_device_substores() {
  print_title_lvl3 "Mounting all factory device substores"
  # We assumes required gpg keys are already imported into the keyring.

  local device_names
  if ! device_names="$(list_all_device_names_from_gopass_device_secret_vault)"; then
    echo "Nothing to mount."
    return 0
  fi

  while read -r dn; do
    print_title_lvl4 "Mounting factory device '$dn''s substores "
    mount_gopass_factory_device_substores "$dn" || return 1
  done < <(echo "$device_names")
}


umount_all_gopass_factory_device_substores() {
  print_title_lvl3 "Unmounting all factory device substores"
  # We assumes required gpg keys are already imported into the keyring.

  local device_names
  if ! device_names="$(list_all_device_names_from_gopass_device_secret_vault)"; then
    echo "Nothing to mount."
    return 0
  fi

  while read -r dn; do
    print_title_lvl4 "Unmounting device '$dn''s substore "
    umount_gopass_factory_device_substores "$dn" || return 1
  done < <(echo "$device_names")
}


is_factory_user_gopass_gpg_id() {
  if ! [[ "x" == "${1:+x}" ]]; then
    1>&2 echo "ERROR: is_factory_user_gopass_gpg_id: Missing argument."
    return 1
  fi

  local gpg_id_or_email="$1"

  local email_user_name
  email_user_name="$(get_email_for_gpg_id "$gpg_id_or_email" | awk -F'@' '{ print $1 }')" || return 1

  local email_domain
  email_domain="$(get_email_for_gpg_id "$gpg_id_or_email" | awk -F'@' '{ print $2 }')" || return 1

  local device_domain
  device_domain="$(get_required_factory_info__device_defaults_email_domain)" || return 1

  # 1>&2 echo "$email_user_name"
  # 1>&2 echo "$email_domain"
  if ! [[ "$email_domain" == "$device_domain" ]]; then
    # Factory user email domain not equal to that of devices. This
    # is clearly not a device. We can thus shortcircuit the
    # potentially costly below check.
    return 0 # true
  fi

  local device_names
  if [[ "x" == "${2:+x}" ]]; then
    # Allow to optimize by retrieving the listing outside of the loop.
    device_names="$2"
  else
    device_names="$(list_all_device_names_from_gopass_factory_vaults_and_device_config)"
  fi

  ! echo "$device_names" | grep -q "${email_user_name}"
}


select_unique_factory_user_gopass_gpg_id() {
  local -n _out_ref="$1"
  local gpg_id_or_email="${2:-}"
  _out_ref=""

  local matching_gpg_id_outer_1=""
  select_unique_gpg_id "matching_gpg_id_outer_1" "$gpg_id_or_email" || return 1

  if ! is_factory_user_gopass_gpg_id "$matching_gpg_id_outer_1"; then
    1>&2 echo "ERROR: gpg id '$matching_gpg_id_outer_1' selected from '$gpg_id_or_email' does not refer to a factory user."
    return 1
  fi

  # shellcheck disable=SC2034  # Out by ref.
  _out_ref="$matching_gpg_id_outer_1"
}


list_all_peers_pub_key_files_from_gopass_vaults() {
  local device_secrets_repo_root
  device_secrets_repo_root="$(get_gopass_device_vault_repo_dir)"
  local factory_secrets_repo_root
  factory_secrets_repo_root="$(get_gopass_factory_only_vault_repo_dir)"

  find \
    "$factory_secrets_repo_root" "$device_secrets_repo_root" \
    -name '.public-keys' -exec find {} -mindepth 1 -maxdepth 1 \;
}


list_all_authorized_peers_gpg_ids_from_gopass_vaults() {
  local device_secrets_repo_root
  device_secrets_repo_root="$(get_gopass_device_vault_repo_dir)"
  local factory_secrets_repo_root
  factory_secrets_repo_root="$(get_gopass_factory_only_vault_repo_dir)"

  find \
    "$factory_secrets_repo_root" "$device_secrets_repo_root" \
    -name '.gpg-id' -exec cat {} \; | sort | uniq
}


list_all_authorized_peers_pub_key_files_from_gopass_vaults() {
  local auth_gpg_ids
  auth_gpg_ids="$(list_all_authorized_peers_gpg_ids_from_gopass_vaults)" || return 1
  local pubkey_files
  pubkey_files="$(list_all_peers_pub_key_files_from_gopass_vaults)" || return 1
  _list_authorized_pub_key_files_from_authorized_gpg_ids_and_public_key_files \
    "$auth_gpg_ids" "$pubkey_files"
}


import_all_authorized_peers_public_key_files_from_gopass_vaults() {
  local device_secrets_repo_root
  device_secrets_repo_root="$(get_gopass_device_vault_repo_dir)"
  local factory_secrets_repo_root
  factory_secrets_repo_root="$(get_gopass_factory_only_vault_repo_dir)"

  local peers_gpg_pub_keys
  mapfile -t peers_gpg_pub_keys < <(list_all_authorized_peers_pub_key_files_from_gopass_vaults) \
    || return 1

  import_gpg_public_key_files "${peers_gpg_pub_keys[@]}"
}


list_factory_user_peers_pub_keys_from_gopass_vaults() {
  # local device_secrets_repo_root_pubkeys_dir
  # device_secrets_repo_root_pubkeys_dir="$(get_gopass_device_vault_repo_dir)/.public-keys"
  local vault_dir
  vault_dir="$(get_gopass_factory_only_vault_repo_dir)" || return 1
  list_gopass_vault_pub_keys_files_at "$vault_dir" "."
}


list_authorized_factory_user_peers_gpg_ids_from_gopass_vaults() {
  local vault_dir
  vault_dir="$(get_gopass_factory_only_vault_repo_dir)" || return 1
  list_gopass_vault_gpg_ids_at "$vault_dir" "."
}


list_authorized_factory_user_peers_pub_keys_from_gopass_vaults() {
  local vault_dir
  vault_dir="$(get_gopass_factory_only_vault_repo_dir)" || return 1
  list_gopass_vault_authorized_pub_keys_at "$vault_dir" "."
}


import_authorized_factory_user_peers_public_keys_from_gopass_vaults() {
  local vault_dir
  vault_dir="$(get_gopass_factory_only_vault_repo_dir)" || return 1
  import_gopass_vault_authorized_pub_keys_at "$vault_dir" "."
}


list_authorized_factory_user_peers_gpg_ids_w_email_from_gopass_vaults() {
  local vault_dir
  vault_dir="$(get_gopass_factory_only_vault_repo_dir)" || return 1
  list_gopass_vault_authorized_gpg_ids_w_email_at "$vault_dir" "."
}
