source "$CB_COMMAND_DIR/../_resolve.sh"
id=$(cb::resolve_plugin "$ARG_PLUGIN") || exit 1
if [[ ${_CB_ID_STATE[$id]} != disabled ]]; then
  ui::info "$id is already enabled"
  exit 0
fi
cb::config_set_disabled "$id" 0
ui::success "$id enabled"
