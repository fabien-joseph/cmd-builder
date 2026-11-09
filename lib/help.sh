# Generated --help, built from the flags.sh files.

cb::_section() { printf '\n%s%s%s\n' "$UI_BOLD" "$1" "$UI_RESET"; }

# Prints aligned "left  right" rows. Arguments: l1 r1 l2 r2 ...
cb::_rows() {
  local -a a=("$@")
  local i w=0
  for ((i = 0; i < ${#a[@]}; i += 2)); do
    ((${#a[i]} > w)) && w=${#a[i]}
  done
  ((w > 30)) && w=30
  for ((i = 0; i < ${#a[@]}; i += 2)); do
    printf '  %s%-*s%s  %s\n' "$UI_CYAN" "$w" "${a[i]}" "$UI_RESET" "${a[i + 1]}"
  done
}

cb::_usage_args() {
  local s=' [options]' name a
  for name in "${_CB_ARGS[@]}"; do
    a=$name
    [[ -n ${_CB_A_VAR[$name]} ]] && a+=...
    if [[ -n ${_CB_A_OPT[$name]} ]]; then s+=" [$a]"; else s+=" <$a>"; fi
  done
  printf '%s' "$s"
}

# An example names its plugin by directory name ("system info"); a renamed plugin is shown
# under its exposed name, the one the user types.
cb::_example_line() {
  local ex=$1 w=${1%% *} id
  for id in "user:$w" "core:$w"; do
    if [[ -n ${_CB_RENAME[$id]:-} && ${_CB_ID_STATE[$id]:-} == active ]]; then
      printf '%s%s' "${_CB_RENAME[$id]}" "${ex#"$w"}"
      return
    fi
  done
  printf '%s' "$ex"
}

# Help of a command. The spec of the directory must be loaded (cb::spec_load).
cb::help() {
  local dir=$1 display=$2 exe name l r i
  local -a children rows
  exe=$(cb::executable "$dir")
  mapfile -t children < <(cb::children "$dir")

  printf '%s%s%s' "$UI_BOLD" "$display" "$UI_RESET"
  [[ -n $_CB_ABOUT ]] && printf ' — %s' "$_CB_ABOUT"
  printf '\n'
  [[ -n $_CB_DESC ]] && printf '\n%s\n' "$_CB_DESC"

  cb::_section Usage
  [[ -n $exe ]] && printf '  %s%s\n' "$display" "$(cb::_usage_args)"
  ((${#children[@]})) && printf '  %s <command> [options]\n' "$display"

  if [[ -n $exe ]] && ((${#_CB_ARGS[@]})); then
    rows=()
    for name in "${_CB_ARGS[@]}"; do
      r=${_CB_A_DESC[$name]}
      [[ -n ${_CB_A_CHOICES[$name]} ]] && r+=" (choices: ${_CB_A_CHOICES[$name]// /, })"
      [[ -n ${_CB_A_CHFROM[$name]} ]] && r+=' (Tab for possible values)'
      [[ -n ${_CB_A_OPT[$name]} ]] && r+=' (optional)'
      rows+=("$name" "$r")
    done
    cb::_section Arguments
    cb::_rows "${rows[@]}"
  fi

  rows=()
  if [[ -n $exe ]]; then
    for name in "${_CB_FLAGS[@]}"; do
      if [[ -n ${_CB_F_SHORT[$name]} ]]; then l="-${_CB_F_SHORT[$name]}, --$name"; else l="    --$name"; fi
      r=${_CB_F_DESC[$name]}
      if [[ ${_CB_F_TYPE[$name]} == bool ]]; then
        [[ ${_CB_F_DEFAULT[$name]:-0} == 1 ]] && r+=" (on by default, --no-$name to disable)"
      else
        if [[ -n ${_CB_F_CHOICES[$name]} ]]; then l+=" <${_CB_F_CHOICES[$name]// /|}>"; else l+=" <${_CB_F_TYPE[$name]}>"; fi
        [[ -n ${_CB_F_DEFAULT[$name]+x} ]] && r+=" (default: ${_CB_F_DEFAULT[$name]})"
        [[ -n ${_CB_F_CHFROM[$name]} ]] && r+=' (Tab for possible values)'
      fi
      [[ -n ${_CB_F_REQ[$name]} ]] && r+=' (required)'
      rows+=("$l" "$r")
    done
  fi
  rows+=('-h, --help' 'Show this help')
  cb::_section Options
  cb::_rows "${rows[@]}"

  if ((${#children[@]})); then
    rows=()
    for name in "${children[@]}"; do rows+=("$name" "$(cb::about_of "$(cb::child_dir "$dir" "$name")")"); done
    cb::_section Commands
    cb::_rows "${rows[@]}"
  fi

  if ((${#_CB_EXAMPLES[@]})); then
    cb::_section Examples
    for ((i = 0; i < ${#_CB_EXAMPLES[@]}; i += 2)); do
      printf '  %s%s %s%s\n' "$UI_CYAN" "$CB_NAME" "$(cb::_example_line "${_CB_EXAMPLES[i]}")" "$UI_RESET"
      [[ -n ${_CB_EXAMPLES[i + 1]} ]] && printf '      %s%s%s\n' "$UI_DIM" "${_CB_EXAMPLES[i + 1]}" "$UI_RESET"
    done
  fi

  ((${#children[@]})) && printf "\nRun '%s <command> --help' for details.\n" "$display"
  return 0
}

# Help of the root command: active plugins + self.
cb::help_root() {
  local name
  local -a rows=()
  printf '%s%s%s — your commands, everywhere (cmd-builder)\n' "$UI_BOLD" "$CB_NAME" "$UI_RESET"
  cb::_section Usage
  printf '  %s <command> [options]\n' "$CB_NAME"
  for name in "${_CB_PLUGIN_NAMES[@]}"; do
    rows+=("$name" "$(cb::about_of "${_CB_PLUGINS[$name]}")")
  done
  rows+=(self "$(cb::about_of "$CB_ROOT/builtin/self")")
  cb::_section Commands
  cb::_rows "${rows[@]}"
  printf "\nRun '%s <command> --help' for details.\n" "$CB_NAME"
  if ((${#_CB_CONFLICTS[@]})); then
    printf '\n' >&2
    ui::warn "${#_CB_CONFLICTS[@]} plugin conflict(s): run '$CB_NAME self doctor'"
  fi
}
