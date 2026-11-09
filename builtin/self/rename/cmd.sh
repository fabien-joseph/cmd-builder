source "$CB_ROOT/lib/core.sh"
source "$CB_ROOT/lib/install.sh"

old=$CB_NAME new=$ARG_NAME keep=$FLAG_KEEP_OLD
old_link=$_CB_BIN_DIR/$old new_link=$_CB_BIN_DIR/$new
old_dir=$CB_CONFIG_DIR new_dir=$(cb::config_dir_of "$new")
nc=$new_dir/config
mapfile -t rcs < <(cb::rc_files)
mapfile -t shells < <(cb::rc_shells)
# Everything of the user in the old config directory moves: the config file and the data of
# plugins (the AI guide keeps plugin settings in $CB_CONFIG_DIR). Generated files do not.
mapfile -t entries < <(cb::config_dir_entries "$old_dir")

# True if both paths exist and are the same file (a --keep-old link, a shared dotfile).
same_file() { [[ -e $1 && -e $2 && $(cb::realpath "$1") == "$(cb::realpath "$2")" ]]; }
# True if both are regular files (not links) with the same content: a copy already made.
identical() { [[ -f $1 && ! -L $1 && -f $2 && ! -L $2 ]] && cmp -s -- "$1" "$2"; }

# ---------------------------------------------------------------------------
# Checks: nothing is changed until the confirmation.
# ---------------------------------------------------------------------------
cb::valid_root_name "$new" || ui::die "invalid name '$new' (lower case letters, digits, - and _, starting with a letter)" 2
if [[ $new == "$old" ]]; then
  ui::info "the command is already named '$old'"
  exit 0
fi
case $(type -t "$new") in
  keyword | builtin) ui::die "'$new' is a shell keyword or builtin, choose another name" ;;
esac
cb::link_is_ours "$old_link" ||
  ui::die "'$old' is not installed as $(cb::tilde "$old_link") (install it with ./init.sh $old)"
if [[ -e $new_link || -L $new_link ]] && ! cb::link_is_ours "$new_link"; then
  ui::die "$new_link already exists and is not a link to this cmd-builder: remove it, or choose another name"
fi
conflicts=()
for e in "${entries[@]}"; do
  d=$new_dir/$e
  [[ -e $d || -L $d ]] || continue
  same_file "$old_dir/$e" "$d" || identical "$old_dir/$e" "$d" || conflicts+=("$e")
done
if ((${#conflicts[@]})); then
  ui::error "both $old_dir and $new_dir contain, with different contents: ${conflicts[*]}"
  ui::die "uninstall '$new' first (./init.sh --uninstall $new), or merge the two files by hand"
fi
for i in "${!rcs[@]}"; do
  cb::rc_broken "${rcs[i]}" "$old" &&
    ui::die "$(cb::tilde "${rcs[i]}"): '$(cb::rc_begin "$old")' found but not '$(cb::rc_end "$old")'; fix the block by hand first"
done

# ---------------------------------------------------------------------------
# Plan and confirmation.
# ---------------------------------------------------------------------------
ui::title "Rename '$old' to '$new'"
if ((keep)); then
  printf '  %s: new link, %s kept\n' "$(cb::tilde "$new_link")" "$(cb::tilde "$old_link")"
  printf '  %s/: its files move to %s/, links to them are left in their place\n' "$(cb::tilde "$old_dir")" "$(cb::tilde "$new_dir")"
else
  printf '  %s → %s\n' "$(cb::tilde "$old_link")" "$(cb::tilde "$new_link")"
  printf '  %s/ → %s/\n' "$(cb::tilde "$old_dir")" "$(cb::tilde "$new_dir")"
fi
others=()
for e in "${entries[@]}"; do [[ $e == config ]] || others+=("$e"); done
((${#others[@]})) && printf '  files of your plugins moved too: %s\n' "${others[*]}"
for i in "${!rcs[@]}"; do
  cb::rc_has "${rcs[i]}" "$old" || continue
  if ((keep)); then
    cb::rc_has "${rcs[i]}" "$new" && continue
    printf "  %s: '%s' block added\n" "$(cb::tilde "${rcs[i]}")" "$new"
  else
    printf "  %s: '%s' block replaced by a '%s' block\n" "$(cb::tilde "${rcs[i]}")" "$old" "$new"
  fi
done
if existing=$(command -v "$new" 2>/dev/null) && [[ $existing != "$new_link" ]]; then
  ui::warn "a command '$new' already exists: $existing (one will hide the other depending on PATH order)"
fi
((keep)) || ui::warn "scripts and aliases calling '$old' will have to use '$new'"
ui::confirm "Rename?" n || ui::die "rename cancelled"
echo

# ---------------------------------------------------------------------------
# Steps, each one checking first whether it is already done: if the command is
# interrupted, running it again finishes the job. A step that fails stops everything
# (the old name keeps working); the old link goes last.
# ---------------------------------------------------------------------------
rerun="$old self rename $new"
((keep)) && rerun+=" --keep-old"
again="nothing after this step was done: fix it, then run '$rerun' again"

# 1. The new link.
if cb::link_is_ours "$new_link"; then
  ui::info "link $new_link: already there"
else
  mkdir -p "$_CB_BIN_DIR" && ln -sfn "$CB_ROOT/main.sh" "$new_link"
  cb::link_is_ours "$new_link" || ui::die "cannot create $new_link; $again"
  ui::success "command installed: $new_link → $CB_ROOT/main.sh"
fi

# 2. The configuration and the files of the plugins. A path is only removed when it is a
# link to the moved file or an identical copy of it: never the only real file.
mkdir -p "$new_dir" || ui::die "cannot create $new_dir; $again"
for e in "${entries[@]}"; do
  s=$old_dir/$e d=$new_dir/$e
  if [[ -L $s ]] && same_file "$s" "$d"; then
    ((keep)) || rm -f -- "$s" # a link to the moved file (or to the same dotfile): nothing to move
    continue
  fi
  if [[ -e $d || -L $d ]]; then
    if same_file "$s" "$d"; then
      rm -f -- "$d" # a link to $s, left by an earlier --keep-old: the file comes back
    else
      rm -f -- "$s" && ui::info "$d: already moved" # identical copy (checked above)
      continue
    fi
  fi
  mv -- "$s" "$d" || ui::die "cannot move $s to $d; $again"
  ui::success "$s moved to $d"
done
if [[ ! -e $nc ]]; then
  (CB_NAME=$new CB_CONFIG_DIR=$new_dir cb::config_ensure) && ui::success "configuration: $nc"
fi
if ((keep)); then
  for e in "${entries[@]}" config; do
    [[ -e $old_dir/$e || -L $old_dir/$e || ! -e $new_dir/$e ]] && continue
    mkdir -p "$old_dir" && ln -s "$new_dir/$e" "$old_dir/$e" && ui::success "$old_dir/$e → $new_dir/$e"
  done
fi

# 3. Completion scripts for the new name.
(CB_NAME=$new CB_CONFIG_DIR=$new_dir cb::completion_install) ||
  ui::die "cannot write the completion scripts in $new_dir; $again"
ui::success "completion generated in $new_dir/"

# 4. rc files: the block of the new name replaces (or, with --keep-old, joins) the old one.
incomplete=0 changed_rc=()
for i in "${!rcs[@]}"; do
  rc=${rcs[i]} shell=${shells[i]}
  if ((keep)); then
    cb::rc_has "$rc" "$old" && ! cb::rc_has "$rc" "$new" || continue
    cb::rc_append "$rc" "$shell" "$new" && ui::success "'$new' block added to $(cb::tilde "$rc")"
    changed_rc+=("$rc")
    continue
  fi
  st=0
  if cb::rc_has "$rc" "$new"; then
    cb::rc_replace "$rc" "$old" || st=$?
  else
    cb::rc_replace "$rc" "$old" "$new" "$shell" || st=$?
  fi
  case $st in
    0) ui::success "$(cb::tilde "$rc"): '$old' block replaced by '$new'" && changed_rc+=("$rc") ;;
    2) cb::rc_has "$rc" "$new" && ui::info "$(cb::tilde "$rc"): already updated" ;;
    *) ui::warn "$(cb::tilde "$rc"): end marker of the '$old' block missing, file left untouched" && incomplete=1 ;;
  esac
done

# 5. What is left of the old name, the link last.
if ((!keep)); then
  if [[ -d $old_dir ]]; then
    cb::config_dir_clean "$old_dir"
    cb::config_dir_remove "$old_dir"
  fi
  cb::link_remove "$old"
fi

echo
if ((incomplete)); then
  ui::warn "'$old' is renamed to '$new', except the rc file block(s) reported above."
  exit 1
fi
ui::success "Done: the command is now '$new'$( ((keep)) && printf " ('%s' still works)" "$old")."
reload=
for rc in "${changed_rc[@]}"; do
  [[ $rc == "$HOME/.bashrc" && $SHELL == */bash ]] && reload=$rc
  [[ $rc == */.zshrc && $SHELL == */zsh ]] && reload=$rc
done
if [[ -n $reload ]]; then
  ui::info "Open a new terminal, or run: source $(cb::tilde "$reload")"
else
  ui::info "Open a new terminal to use it."
fi
