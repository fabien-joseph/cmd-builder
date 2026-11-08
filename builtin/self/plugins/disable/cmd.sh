source "$CB_COMMAND_DIR/../_resolve.sh"
id=$(cb::resolve_plugin "$ARG_PLUGIN") || exit 1
if [[ ${_CB_ID_STATE[$id]} == disabled ]]; then
  ui::info "$id is already disabled"
  exit 0
fi
cb::config_set_disabled "$id" 1
ui::success "$id disabled (re-enable: $CB_NAME self plugins enable $id)"
