source "$CB_ROOT/lib/core.sh"
cb::config_load
cb::plugins_load

if ((${#_CB_IDS[@]} == 0)); then
  ui::info "No plugin yet. Create the first one: $CB_NAME self new <name>"
  exit 0
fi

rows=()
for id in "${_CB_IDS[@]}"; do
  state=${_CB_ID_STATE[$id]}
  name=${_CB_ID_NAME[$id]}
  case $state in
    active) s="${UI_GREEN}active${UI_RESET}" ;;
    disabled) s="${UI_DIM}disabled${UI_RESET}" ;;
    reserved) s="${UI_RED}reserved name (self)${UI_RESET}" ;;
    shadowed:*) s="${UI_YELLOW}shadowed by ${state#shadowed:}${UI_RESET}" ;;
    extends:*) s="${UI_GREEN}extends ${state#extends:}${UI_RESET}" ;;
    inactive:*) s="${UI_YELLOW}inactive (${state#inactive:} is not active)${UI_RESET}" ;;
    orphan) s="${UI_YELLOW}inactive (extends nothing)${UI_RESET}" ;;
  esac
  [[ $name != "${id#*:}" && $id != user:+* ]] && s+=" ${UI_DIM}(renamed)${UI_RESET}"
  rows+=("$(printf '%-18s %-20s' "$name" "$id")" "$s")
done
ui::title "$(printf '  %-18s %-20s  %s' NAME ID STATE)"
cb::_rows "${rows[@]}"

if ((${#_CB_CONFLICTS[@]})); then
  echo
  ui::warn "${#_CB_CONFLICTS[@]} conflict(s): run '$CB_NAME self doctor' for details"
fi
