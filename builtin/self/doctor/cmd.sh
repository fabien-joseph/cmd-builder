source "$CB_ROOT/lib/core.sh"
source "$CB_ROOT/lib/deps.sh"
cb::config_load
cb::plugins_load

errors=0 warnings=0
ok() { printf '  %s✓%s %s\n' "$UI_GREEN" "$UI_RESET" "$*"; }
ko() { printf '  %s✗%s %s\n' "$UI_RED" "$UI_RESET" "$*"; ((errors++)); }
wa() { printf '  %s!%s %s\n' "$UI_YELLOW" "$UI_RESET" "$*"; ((warnings++)); }
rel() { printf '%s' "${1#"$CB_ROOT"/}"; }

# Checks one `example` of a command the way the parser would see it. <top> and <name>:
# the plugin the flags.sh belongs to and its exposed name. Prints the problem, if any.
check_example() {
  local top=$1 name=$2 ex=$3 dir out
  local -a w=()
  # Split like the shell would (quotes), without expanding anything: xargs does that.
  out=$(printf '%s\n' "$ex" | xargs printf '%s\n' 2>&1) || { echo "unbalanced quotes"; return; }
  [[ -n $out ]] && mapfile -t w <<<"$out"
  ((${#w[@]})) || { echo "empty command line"; return; }
  # The plugin itself, also under its directory name (renamed or shadowed plugin).
  if [[ ${w[0]} == "$name" || ${w[0]} == "${top##*/}" ]]; then
    dir=$top
  elif ! dir=$(cb::plugin_dir "${w[0]}"); then
    if [[ ${w[0]} == "$CB_NAME" ]]; then
      echo "starts with '$CB_NAME': write it without the root name"
    else
      echo "unknown command '${w[0]}'"
    fi
    return
  fi
  w=("${w[@]:1}")
  cb::descend "$dir" "${w[@]}"
  dir=$_CB_ROUTE_DIR w=("${w[@]:_CB_ROUTE_N}")
  # In a subshell: the parser exits on the first error. Dynamic --strict choices are not
  # validated (their values depend on the machine).
  # Copies with the reserved prefix: flags.sh may assign "dir" or "w" (see cb::spec_load).
  _cb_dir=$dir _cb_w=("${w[@]}")
  (
    ui::error() { printf '%s\n' "$*" >&2; }
    cb::spec_load "$_cb_dir" 2>/dev/null || exit 0 # an invalid flags.sh is reported elsewhere
    if [[ -z $(cb::executable "$_cb_dir") ]]; then
      ((${#_cb_w[@]} == 0)) || [[ ${_cb_w[0]} == -h || ${_cb_w[0]} == --help ]] || echo "unknown subcommand '${_cb_w[0]}'"
      exit 0
    fi
    _CB_NO_DYNAMIC=1
    cb::parse "$_cb_dir" "x" "${_cb_w[@]}" 2>&1 >/dev/null | head -n 1
  ) 2>/dev/null
}

ui::title "Environment"
ok "Bash $BASH_VERSION"
if command -v git >/dev/null; then ok "$(git --version)"; else wa "git not found (needed for self update)"; fi
link=$(command -v "$CB_NAME" 2>/dev/null)
if [[ -z $link ]]; then
  ko "'$CB_NAME' not found in PATH (run './init.sh $CB_NAME' again or add ~/.local/bin to PATH)"
elif [[ $(cb::realpath "$link") == "$CB_ROOT/main.sh" ]]; then
  ok "$link → $CB_ROOT/main.sh"
else
  ko "'$CB_NAME' in PATH does not point to this cmd-builder: $link"
fi
for s in bash zsh; do
  if [[ -f $CB_CONFIG_DIR/completion.$s ]]; then ok "$s completion generated"; else wa "$s completion missing (run ./init.sh $CB_NAME again)"; fi
done

echo
ui::title "Configuration"
if [[ -f $CB_CONFIG_DIR/config ]]; then ok "$CB_CONFIG_DIR/config"; else wa "no config file ($CB_CONFIG_DIR/config)"; fi
for e in "${_CB_CONFIG_ERRORS[@]}"; do ko "config $e"; done
for id in "${!_CB_DISABLED[@]}" "${!_CB_RENAME[@]}"; do
  [[ -n ${_CB_ID_DIR[$id]:-} ]] || wa "the config mentions $id, which does not exist"
done

echo
ui::title "Plugins"
active=0
for id in "${_CB_IDS[@]}"; do [[ ${_CB_ID_STATE[$id]} == active || ${_CB_ID_STATE[$id]} == extends:* ]] && ((active++)); done
ok "${#_CB_IDS[@]} plugin(s) found, $active active"
for c in "${_CB_CONFLICTS[@]}"; do wa "$c"; done

echo
ui::title "Dependencies"
cb::deps_collect
if ((${#_CB_DEP_TOOLS[@]} == 0)); then
  ok "no extra tool needed"
else
  dep_missing=0
  for tool in "${_CB_DEP_TOOLS[@]}"; do
    cb::dep_ok "$tool" && continue
    [[ -n ${_CB_DEP_REQ[$tool]:-} ]] || continue
    wa "$tool missing, needed by ${_CB_DEP_USERS[$tool]} (run '$CB_NAME self deps install')"
    ((dep_missing++))
  done
  ((dep_missing)) || ok "${#_CB_DEP_TOOLS[@]} tool(s) declared, the required ones are installed"
  ((${#_CB_PMS[@]})) || wa "no package manager configured ('$CB_NAME self deps managers add <manager>')"
fi

echo
ui::title "Commands"
count=0 bad=0
dirs=("$CB_ROOT/builtin/self") names=(self)
for id in "${_CB_IDS[@]}"; do
  [[ $id == user:+* ]] && continue # an extension is checked with the official plugin
  dirs+=("${_CB_ID_DIR[$id]}") names+=("${_CB_ID_NAME[$id]}")
done
for t in "${!dirs[@]}"; do
  top=${dirs[t]}
  while IFS= read -r d; do
    ((count++))
    before=$errors
    if out=$( (cb::spec_load "$d") 2>&1 >/dev/null); then
      # Examples, checked against the declarations (warnings: the command itself works).
      while IFS= read -r -d '' ex; do
        msg=$(check_example "$top" "${names[t]}" "$ex")
        [[ -n $msg ]] && wa "$(rel "$d"): example '$ex': $msg"
      done < <(cb::spec_load "$d" >/dev/null 2>&1; for ((i = 0; i < ${#_CB_EXAMPLES[@]}; i += 2)); do printf '%s\0' "${_CB_EXAMPLES[i]}"; done)
    else
      ko "$(rel "$d"): ${out:-invalid flags.sh}"
    fi
    [[ -f $d/cmd && ! -x $d/cmd ]] && ko "$(rel "$d")/cmd is not executable (chmod +x)"
    [[ -f $d/cmd.sh && -f $d/cmd ]] && wa "$(rel "$d"): both cmd.sh and cmd exist, cmd.sh is used"
    if [[ -z $(cb::executable "$d") ]] && n=$( (cb::spec_load "$d" >/dev/null 2>&1; echo $((${#_CB_FLAGS[@]} + ${#_CB_ARGS[@]} + ${#_CB_REQS[@]}))) ) && ((n)); then
      wa "$(rel "$d") declares options, arguments or requires but has no cmd.sh: they are ignored"
    fi
    if [[ -z $(cb::executable "$d") && -z $(cb::children "$d") ]]; then
      wa "$(rel "$d") does nothing (no cmd.sh, no cmd, no subcommand)"
    fi
    ((errors > before)) && ((bad++))
  done < <(cb::walk "$top" | cut -f 1)
done
((bad == 0)) && ok "$count valid command(s)"

echo
if ((errors)); then
  ui::error "$errors error(s), $warnings warning(s)"
  exit 1
elif ((warnings)); then
  ui::warn "$warnings warning(s)"
else
  ui::success "Everything is fine."
fi
