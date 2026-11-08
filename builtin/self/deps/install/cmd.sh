source "$CB_COMMAND_DIR/../_common.sh"

todo=()
for tool in "${_CB_DEP_TOOLS[@]}"; do
  cb::dep_ok "$tool" && continue
  [[ -n ${_CB_DEP_REQ[$tool]:-} || $FLAG_ALL == 1 ]] && todo+=("$tool")
done
if ((${#todo[@]} == 0)); then
  ui::success "Nothing to install."
  exit 0
fi
_deps_run install "${todo[@]}"
status=$?
for tool in "${todo[@]}"; do
  if cb::dep_ok "$tool"; then
    ui::success "$tool installed"
  else
    ui::warn "$tool still not found (does the package provide a command with another name?)"
    status=1
  fi
done
exit "$status"
