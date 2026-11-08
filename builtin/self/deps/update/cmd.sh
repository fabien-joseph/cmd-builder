source "$CB_COMMAND_DIR/../_common.sh"

todo=()
for tool in "${_CB_DEP_TOOLS[@]}"; do
  cb::dep_ok "$tool" && todo+=("$tool")
done
if ((${#todo[@]} == 0)); then
  ui::success "Nothing to update."
  exit 0
fi
_deps_run update "${todo[@]}"
