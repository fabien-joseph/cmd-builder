about "Disable a plugin (it stays on disk)"
_cb_enabled_plugins() {
  local id
  for id in "${_CB_IDS[@]}"; do
    [[ ${_CB_ID_STATE[$id]} != disabled ]] && printf '%s\t%s\n' "$id" "$(cb::about_of "${_CB_ID_DIR[$id]}")"
  done
}
arg plugin "Plugin: name or id (core:name, user:name)" --choices-from _cb_enabled_plugins
example "self plugins disable core:system"
