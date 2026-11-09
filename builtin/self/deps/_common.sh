# Shared by the "self deps" commands (ignored by routing thanks to "_").
source "$CB_ROOT/lib/core.sh"
source "$CB_ROOT/lib/deps.sh"
cb::config_load
cb::plugins_load
cb::deps_collect

# Installs or updates <tool>... with the configured managers: shows the commands, asks
# once, runs them. Returns 1 if something could not be done.
_deps_run() { # install|update tool...
  local action=$1 tool pm c failed=0
  local -a pms=() cmds=() none=()
  local -A by_pm=()
  shift
  if ((${#_CB_PMS[@]} == 0)); then
    cb::pm_ask || ui::die "no package manager configured: '$CB_NAME self deps managers add <manager>'"
  fi
  for tool; do
    if pm=$(cb::pm_for "$tool"); then
      [[ -n ${by_pm[$pm]+x} ]] || pms+=("$pm")
      by_pm[$pm]+=" $(cb::pm_package "$pm" "$tool")"
    else
      none+=("$tool")
    fi
  done
  for tool in "${none[@]}"; do
    ui::warn "'$tool' is not packaged for ${_CB_PMS[*]}: install it by hand"
  done
  ((${#pms[@]})) || return 1
  for pm in "${pms[@]}"; do
    # Word splitting of the package list is intended (validated names, no spaces).
    # shellcheck disable=SC2086
    mapfile -t -O "${#cmds[@]}" cmds < <(cb::pm_commands "$pm" "$action" ${by_pm[$pm]})
  done
  ui::title "Commands to run:"
  printf '  %s\n' "${cmds[@]}"
  ui::confirm "Run them?" y || ui::die "cancelled"
  for c in "${cmds[@]}"; do
    printf '%s$ %s%s\n' "$UI_DIM" "$c" "$UI_RESET"
    eval "$c" || { ui::error "failed: $c"; failed=1; } # the next ones may still work (another manager)
  done
  ((!failed && ${#none[@]} == 0))
}
