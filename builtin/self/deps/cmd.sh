source "$CB_COMMAND_DIR/_common.sh"

if ((${#_CB_PMS[@]})); then
  ui::info "package managers: ${_CB_PMS[*]}"
else
  ui::info "no package manager configured yet ('$CB_NAME self deps managers add <manager>')"
fi
if ((${#_CB_DEP_TOOLS[@]} == 0)); then
  ui::success "Your commands need no extra tool."
  exit 0
fi

missing=0
ui::title "$(printf '  %-14s %-20s %-20s %s' TOOL STATE PACKAGE 'USED BY')"
for tool in "${_CB_DEP_TOOLS[@]}"; do
  if cb::dep_ok "$tool"; then
    state=installed color=$UI_GREEN
  elif [[ -n ${_CB_DEP_REQ[$tool]:-} ]]; then
    state=missing color=$UI_RED
    ((missing++))
  else
    state="missing (optional)" color=$UI_YELLOW
  fi
  if pm=$(cb::pm_for "$tool"); then pkg="$pm: $(cb::pm_package "$pm" "$tool")"; else pkg=-; fi
  printf '  %-14s %s%-20s%s %-20s %s\n' "$tool" "$color" "$state" "$UI_RESET" "$pkg" "${_CB_DEP_USERS[$tool]}"
done
echo
if ((missing)); then
  ui::warn "$missing required tool(s) missing: run '$CB_NAME self deps install'"
else
  ui::success "All required tools are installed."
fi
