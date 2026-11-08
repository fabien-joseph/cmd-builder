source "$CB_COMMAND_DIR/../_common.sh"

mapfile -t found < <(cb::pm_detect)
if ((${#_CB_PMS[@]})); then
  ui::title "Configured (in order):"
  printf '  %s\n' "${_CB_PMS[@]}"
else
  ui::info "none configured yet"
fi
ui::info "detected on this machine: ${found[*]:-none}"
ui::info "supported: ${_CB_PM_ALL[*]}"
