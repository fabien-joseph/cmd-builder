source "$CB_COMMAND_DIR/../../_common.sh"

cb::in_list "$ARG_MANAGER" "${_CB_PMS[@]}" || ui::die "$ARG_MANAGER is not configured (see '$CB_NAME self deps managers')"
keep=()
for pm in "${_CB_PMS[@]}"; do [[ $pm == "$ARG_MANAGER" ]] || keep+=("$pm"); done
cb::config_set_package_managers "${keep[@]}"
ui::success "package managers: ${_CB_PMS[*]:-none}"
