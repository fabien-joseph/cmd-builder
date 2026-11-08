source "$CB_COMMAND_DIR/../../_common.sh"

if cb::in_list "$ARG_MANAGER" "${_CB_PMS[@]}"; then
  ui::info "$ARG_MANAGER is already configured"
  exit 0
fi
command -v "$([[ $ARG_MANAGER == apt ]] && echo apt-get || echo "$ARG_MANAGER")" >/dev/null 2>&1 ||
  ui::warn "$ARG_MANAGER is not installed on this machine"
cb::config_set_package_managers "${_CB_PMS[@]}" "$ARG_MANAGER"
ui::success "package managers: ${_CB_PMS[*]}"
