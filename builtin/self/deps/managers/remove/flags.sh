about "Stop using a package manager"
_cb_configured_pms() {
  cb::config_load && printf '%s\n' "${_CB_PMS[@]}"
}
arg manager "Package manager" --choices-from _cb_configured_pms
example "self deps managers remove brew"
