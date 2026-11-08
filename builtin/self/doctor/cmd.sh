source "$CB_ROOT/lib/core.sh"
cb::config_load
cb::plugins_load

errors=0 warnings=0
ok() { printf '  %s✔%s %s\n' "$UI_GREEN" "$UI_RESET" "$*"; }
ko() { printf '  %s✖%s %s\n' "$UI_RED" "$UI_RESET" "$*"; ((errors++)); }
wa() { printf '  %s⚠%s %s\n' "$UI_YELLOW" "$UI_RESET" "$*"; ((warnings++)); }
rel() { printf '%s' "${1#"$CB_ROOT"/}"; }

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
for id in "${_CB_IDS[@]}"; do [[ ${_CB_ID_STATE[$id]} == active ]] && ((active++)); done
ok "${#_CB_IDS[@]} plugin(s) found, $active active"
for c in "${_CB_CONFLICTS[@]}"; do wa "$c"; done

echo
ui::title "Commands"
count=0 bad=0
dirs=("$CB_ROOT/builtin/self")
for id in "${_CB_IDS[@]}"; do dirs+=("${_CB_ID_DIR[$id]}"); done
for top in "${dirs[@]}"; do
  while IFS= read -r d; do
    ((count++))
    before=$errors
    if out=$( (cb::spec_load "$d") 2>&1 >/dev/null); then :; else ko "$(rel "$d"): ${out:-invalid flags.sh}"; fi
    [[ -f $d/cmd && ! -x $d/cmd ]] && ko "$(rel "$d")/cmd is not executable (chmod +x)"
    [[ -f $d/cmd.sh && -f $d/cmd ]] && wa "$(rel "$d"): both cmd.sh and cmd exist, cmd.sh is used"
    if [[ -z $(cb::executable "$d") && -z $(cb::children "$d") ]]; then
      wa "$(rel "$d") does nothing (no cmd.sh, no cmd, no subcommand)"
    fi
    ((errors > before)) && ((bad++))
  done < <(cb::walk "$top")
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
