# Install helpers shared by init.sh and "self rename" (decisions 0007 and 0012):
# the ~/.local/bin/<name> link, the blocks of ~/.bashrc / ~/.zshrc and the config directory.
# Not loaded by lib/core.sh: sourced by the scripts that need it, after lib/core.sh.
# Every helper first checks whether its job is already done, so that an interrupted run
# simply finishes when it is run again.

_CB_BIN_DIR=$HOME/.local/bin

# Path for display, with $HOME shown as ~. Not "${p/#$HOME/\~}": Bash 4.2 keeps the backslash.
cb::tilde() {
  if [[ $1 == "$HOME" || $1 == "$HOME"/* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi
}

# Valid name for the root command (stricter than cb::valid_name: it becomes a file name in
# ~/.local/bin and part of a shell function name).
cb::valid_root_name() { [[ $1 =~ ^[a-z][a-z0-9_-]*$ ]]; }

# Config directory of the root command <name>.
cb::config_dir_of() { printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/$1"; }

# rc files, one per line, in the order of cb::rc_shells.
cb::rc_files() { printf '%s\n' "$HOME/.bashrc" "${ZDOTDIR:-$HOME}/.zshrc"; }
cb::rc_shells() { printf '%s\n' bash zsh; }

# Markers of the rc block of <name>. Never change their format without a migration.
cb::rc_begin() { printf '# >>> cmd-builder: %s >>>' "$1"; }
cb::rc_end() { printf '# <<< cmd-builder: %s <<<' "$1"; }

# True if <rc> contains the begin marker of <name>.
cb::rc_has() { [[ -f $1 ]] && grep -qF "$(cb::rc_begin "$2")" "$1"; }

# True if <rc> has the begin marker of <name> but not its end marker (edited by hand?).
cb::rc_broken() { cb::rc_has "$1" "$2" && ! grep -qF "$(cb::rc_end "$2")" "$1"; }

# Prints the rc block of <name> for <shell> (bash|zsh): PATH + completion.
cb::rc_block() {
  local name=$1 shell=$2 comp
  comp=$(cb::config_dir_of "$name")/completion.$shell
  cb::rc_begin "$name"
  printf '\ncase ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH" ;; esac\n' "$_CB_BIN_DIR" "$_CB_BIN_DIR"
  printf '[ -f "%s" ] && . "%s"\n' "$comp" "$comp"
  cb::rc_end "$name"
  printf '\n'
}

# Appends the block of <name> to <rc>, after a blank line.
cb::rc_append() { # rc shell name
  { printf '\n'; cb::rc_block "$3" "$2"; } >>"$1"
}

# Rewrites <rc> without the block of <old> or, if <new> is given, with the block of <new>
# (for <shell>) in its place. Atomic (temp file + mv): an interruption leaves either the
# old file or the new one. Follows a symlinked rc file (dotfiles) to edit its target.
# Returns 0 when rewritten, 2 when there was no block of <old>, 1 when the end marker is
# missing: rewriting would drop the whole end of the file, so it is left untouched.
cb::rc_replace() { # rc old [new shell]
  local rc=$1 old=$2 new=${3:-} shell=${4:-bash} real tmp line begin end skip=0 pending=0
  local -a out=() block=()
  [[ -e $rc ]] || return 2
  begin=$(cb::rc_begin "$old") end=$(cb::rc_end "$old")
  real=$(cb::realpath "$rc") || real=$rc
  tmp=$real.cb-uninstall.tmp
  rm -f -- "$tmp" # possible leftover of a previous interruption
  grep -qF "$begin" "$real" || return 2
  cb::rc_broken "$real" "$old" && return 1
  [[ -n $new ]] && mapfile -t block < <(cb::rc_block "$new" "$shell")
  while IFS= read -r line || [[ -n $line ]]; do
    if ((skip)); then
      [[ $line == "$end" ]] && skip=0
      continue
    fi
    if [[ $line == "$begin" ]]; then
      skip=1
      if [[ -n $new ]]; then
        ((pending)) && out+=('') # keep the blank line before the block
        out+=("${block[@]}")
      fi
      pending=0 # without a new block, also drop the blank line added before it
      continue
    fi
    ((pending)) && out+=('')
    pending=0
    if [[ -z $line ]]; then pending=1; else out+=("$line"); fi
  done <"$real"
  ((skip)) && return 1
  ((pending)) && out+=('')
  if ((${#out[@]})); then printf '%s\n' "${out[@]}" >"$tmp"; else : >"$tmp"; fi
  chmod --reference="$real" "$tmp" 2>/dev/null || chmod "$(stat -f %Lp "$real" 2>/dev/null || echo 644)" "$tmp"
  mv -f -- "$tmp" "$real"
}

# True if <link> is a symlink to this checkout's main.sh (even a broken one).
cb::link_is_ours() {
  [[ -L $1 ]] || return 1
  [[ $(readlink -- "$1") == "$CB_ROOT/main.sh" || $(cb::realpath "$1" 2>/dev/null) == "$CB_ROOT/main.sh" ]]
}

# Removes the ~/.local/bin/<name> link, only if it points to this cmd-builder.
cb::link_remove() {
  local link=$_CB_BIN_DIR/$1
  if [[ ! -e $link && ! -L $link ]]; then
    ui::info "link $link: already removed"
  elif cb::link_is_ours "$link"; then
    rm -f -- "$link" && ui::success "link $link removed"
  else
    ui::warn "$link is not a link to this cmd-builder: left in place"
  fi
}

# Removes the generated files of a config directory (completion scripts, temp file).
# The config file itself is left to the caller.
cb::config_dir_clean() {
  local dir=$1 f
  for f in completion.bash completion.zsh config.tmp; do
    [[ -e $dir/$f ]] && rm -f -- "$dir/$f" && ui::success "$dir/$f removed"
  done
  return 0
}

# Removes a config directory if it is empty, says so otherwise.
cb::config_dir_remove() {
  if rmdir -- "$1" 2>/dev/null; then
    ui::success "$1 removed"
  elif [[ -d $1 ]]; then
    ui::info "$1 kept (it still contains files)"
  fi
}
