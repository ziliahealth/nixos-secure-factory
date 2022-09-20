#!/usr/bin/env bash
common_sh_lib_dir="$(pkg-nsf-common-get-sh-lib-dir)"
# shellcheck source=permissions.sh
. "$common_sh_lib_dir/permissions.sh"

common_factory_install_sh_lib_dir="$(pkg-nsf-factory-common-install-get-sh-lib-dir)"
# shellcheck source=SCRIPTDIR/../sh-lib/tools.sh
. "$common_factory_install_sh_lib_dir/tools.sh"
# shellcheck source=SCRIPTDIR/../sh-lib/gpg.sh
. "$common_factory_install_sh_lib_dir/gpg.sh"
# shellcheck source=SCRIPTDIR/../sh-lib/git.sh
. "$common_factory_install_sh_lib_dir/git.sh"
# shellcheck source=SCRIPTDIR/../sh-lib/workspace_paths.sh
. "$common_factory_install_sh_lib_dir/workspace_paths.sh"

# permissions

create_and_assign_proper_permissions_to_gopass_home_dir_lazy_and_silent() {
  local target_gopass_home_dir="$1"
  create_and_assign_proper_permissions_to_dir_lazy "$target_gopass_home_dir" "700"
  create_and_assign_proper_permissions_to_dir_lazy "$target_gopass_home_dir/.config" "755"
}


get_gopass_sandbox_dir() {
  # TODO: Defaults to '~/.nixos-secure-factory/.gnupg'
  local ws_dir
  ws_dir="$(get_nixos_secure_factory_workspace_dir)"
  local default_sandbox_gopass_home_dir="$ws_dir/.gopass-home"

  local gopass_home_sanbox_dir="${PKG_NSF_FACTORY_COMMON_INSTALL_SANDBOXED_GOPASS_HOME_DIR:-$default_sandbox_gopass_home_dir}"
  echo "$gopass_home_sanbox_dir"
}


is_gopass_home_sandboxed() {
  local gopass_home_sanbox_disable_value="${PKG_NSF_FACTORY_COMMON_INSTALL_SANDBOXED_GOPASS_HOME_DISABLE:-0}"
  # 1>&2 echo "gopass_home_sanbox_disable_value='$gopass_home_sanbox_disable_value'"
  ! test "1" == "${gopass_home_sanbox_disable_value:-0}"
}


get_gopass_home_dir() {
  if is_gopass_home_sandboxed; then
    # 1>&2 echo "get_gopass_home_dir -> sandboxed"
    local sandbox_gopass_home_dir
    sandbox_gopass_home_dir="$(get_gopass_sandbox_dir)"
    create_and_assign_proper_permissions_to_gopass_home_dir_lazy_and_silent "$sandbox_gopass_home_dir"
    echo "$sandbox_gopass_home_dir"
  else
    # 1>&2 echo "get_gopass_home_dir -> not sandboxed"
    echo "$HOME"
  fi
}


run_sandboxed_gopass() {
  local gpg_home_dir
  gpg_home_dir="$(get_default_gpg_home_dir)" || return 1

  local gopass_home_dir
  gopass_home_dir="$(get_gopass_home_dir)" || return 1

  ensure_minimal_git_config_error_if_not || return 1

  GOPASS_HOMEDIR="$gopass_home_dir" \
  GOPASS_CONFIG="$gopass_home_dir/.config/gopass/gopass.yaml" \
  GNUPGHOME="$gpg_home_dir" \
    nix-gopass "$@"
}


configure_gopass_store() {
  local store_id="$1"
  run_sandboxed_gopass init --store "$store_id"
  run_sandboxed_gopass config autosync false
  run_sandboxed_gopass config autoimport false

  # TODO: Consider this.
  run_sandboxed_gopass config check_recipient_hash false

  run_sandboxed_gopass config noconfirm true
  run_sandboxed_gopass config nopager true
  # run_sandboxed_gopass config --store "$store_id" nocolor true

  run_sandboxed_gopass config askformore false
  run_sandboxed_gopass config notifications false
  run_sandboxed_gopass config safecontent false
}


configure_gopass_root_store() {
  store_id=""
  run_sandboxed_gopass init --store "$store_id"
  run_sandboxed_gopass config autosync false
  run_sandboxed_gopass config autoimport false
}


_list_authorized_pub_key_files_from_authorized_gpg_ids_and_public_key_files() {
  local auth_gpg_ids="$1"
  local pubkey_files="$2"

  declare -A auth_gpg_ids_a=()
  while read -r auth_id; do
    auth_gpg_ids_a+=( ["$auth_id"]="null" )
  done < <(echo "$auth_gpg_ids")

  # First encountered public key is used. Subsequent
  # occurences are diregarded.
  local pubkey_bn
  local previous_pubkey
  while read -r pubkey; do
    pubkey_bn="$(basename "$pubkey")"
    previous_pubkey="${auth_gpg_ids_a["$pubkey_bn"]-undefined}"
    if [[ "null" == "$previous_pubkey" ]] \
        || [[ "${#pubkey}" -lt "${#previous_pubkey}" ]]; then
      auth_gpg_ids_a["$pubkey_bn"]="$pubkey"
    fi
  done < <(echo "$pubkey_files")

  for pk in "${auth_gpg_ids_a[@]}"; do
    if [[ "$pk" == "null" ]]; then
      continue
    fi
    printf "%s\n" "$pk"
  done
}


list_gopass_vault_pub_keys_files_at() {
  local vault_dir="${1?}"
  local rel_dir_to_substore="${2?}"

  local pubkeys_dir
  pubkeys_dir="$vault_dir/$rel_dir_to_substore/.public-keys"

  if ! pubkeys_dir="$(realpath "$pubkeys_dir")" \
      || ! [[ -d "$pubkeys_dir" ]]; then
    1>&2 echo "ERROR: list_gopass_vault_pub_keys_files_at:"
    1>&2 echo " -> Cannot find '$pubkeys_dir'"
    return 1
  fi

  # "$device_secrets_repo_root_pubkeys_dir" \
  local pubkey_dirs=( \
    "$pubkeys_dir" )

  [[ "${#pubkey_dirs[@]}" -eq 0 ]] || \
    find "${pubkey_dirs[@]}" -mindepth 1 -maxdepth 1
}


list_gopass_vault_pub_keys_files_at_w_parents() {
  local vault_dir="${1?}"
  local rel_dir_to_substore="${2?}"

  list_gopass_vault_pub_keys_files_at \
    "$vault_dir" "$rel_dir_to_substore"

  local parent_dirs=()
  local parent_dir
  parent_dir="$rel_dir_to_substore"
  while ! [[ "." == "$parent_dir" ]] && ! [[ "" == "$parent_dir" ]]; do
    parent_dir="$(dirname "$rel_dir_to_substore")"
    parent_dirs=( "${parent_dirs[@]}" "$parent_dir")
  done

  for parent_dir in "${parent_dirs[@]}"; do
    list_gopass_vault_pub_keys_files_at \
      "$vault_dir" "$parent_dir" || return 1
  done
}


list_gopass_vault_gpg_ids_at() {
  local vault_dir="${1?}"
  local rel_dir_to_substore="${2?}"

  local gpg_id_file
  gpg_id_file="$vault_dir/$rel_dir_to_substore/.gpg-id"

  if ! gpg_id_file="$(realpath "$gpg_id_file")" \
      || ! [[ -f "$gpg_id_file" ]]; then
    1>&2 echo "ERROR: list_gopass_vault_gpg_ids_at:"
    1>&2 echo " -> Cannot find '$gpg_id_file'"
    return 1
  fi

  (! [[ -f "$gpg_id_file" ]] \
      || cat "$gpg_id_file") \
    | sort | uniq
}


list_gopass_vault_authorized_pub_keys_at() {
  local vault_dir="${1?}"
  local rel_dir_to_substore="${2?}"

  local auth_gpg_ids
  auth_gpg_ids="$(list_gopass_vault_gpg_ids_at \
    "$vault_dir" "$rel_dir_to_substore")" || return 1
  local pubkey_files
  pubkey_files="$(list_gopass_vault_pub_keys_files_at_w_parents \
    "$vault_dir" "$rel_dir_to_substore")" || return 1
  _list_authorized_pub_key_files_from_authorized_gpg_ids_and_public_key_files \
    "$auth_gpg_ids" "$pubkey_files"
}


import_gopass_vault_authorized_pub_keys_at() {
  local vault_dir="${1?}"
  local rel_dir_to_substore="${2?}"

  local peers_gpg_pub_keys
  mapfile -t peers_gpg_pub_keys < <(list_gopass_vault_authorized_pub_keys_at \
      "$vault_dir" "$rel_dir_to_substore") \
    || return 1

  import_gpg_public_key_files "${peers_gpg_pub_keys[@]}"
}


list_gopass_vault_authorized_gpg_ids_w_email_at() {
  local vault_dir="${1?}"
  local rel_dir_to_substore="${2?}"

  local peers_gpg_pub_keys
  mapfile -t peers_gpg_pub_keys < <(list_gopass_vault_authorized_pub_keys_at \
      "$vault_dir" "$rel_dir_to_substore") \
    || return 1

  list_gpg_id_w_email_from_key_files "${peers_gpg_pub_keys[@]}"
}
