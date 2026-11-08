# Resolves a plugin name or id to a single id (printed on stdout).
source "$CB_ROOT/lib/core.sh"
cb::config_load
cb::plugins_load

cb::resolve_plugin() {
  local q=$1 id
  local -a found=()
  if [[ $q == *:* ]]; then
    [[ -n ${_CB_ID_DIR[$q]:-} ]] || ui::die "plugin not found: $q (see '$CB_NAME self plugins')"
    printf '%s' "$q"
    return
  fi
  for id in "${_CB_IDS[@]}"; do
    [[ ${id#*:} == "$q" || ${_CB_ID_NAME[$id]} == "$q" ]] && found+=("$id")
  done
  ((${#found[@]})) || ui::die "plugin not found: $q (see '$CB_NAME self plugins')"
  ((${#found[@]} == 1)) || ui::die "'$q' is ambiguous: ${found[*]} — use the full id"
  printf '%s' "${found[0]}"
}
