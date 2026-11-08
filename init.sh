#!/usr/bin/env bash
# Installs cmd-builder under the name of your choice.
#
#   ./init.sh <name>               install
#   ./init.sh --uninstall <name>   uninstall
#
# - creates ~/.local/bin/<name> → main.sh (symlink, no sudo)
# - creates ~/.config/<name>/config and the completion scripts
# - offers to enable completion (and ~/.local/bin in PATH) in ~/.bashrc / ~/.zshrc
# Running either one again is safe (idempotent): an interrupted uninstall
# simply finishes on the next run.

case ${BASH_VERSION:-} in
  '' | [0-3].* | 4.[01].*)
    printf '%s\n' "cmd-builder requires Bash >= 4.2 (current: ${BASH_VERSION:-none})." \
      "On macOS: brew install bash, then run ./init.sh again" >&2
    exit 1
    ;;
esac

CB_ROOT=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mode=install
if [[ ${1:-} == --uninstall ]]; then
  mode=uninstall
  shift
fi
CB_NAME=${1:-}
# Checked before sourcing lib/core.sh, which would replace an empty name with a default.
if [[ -z $CB_NAME || $CB_NAME == -h || $CB_NAME == --help ]]; then
  printf '%s\n' 'Usage:' \
    '  ./init.sh <name>               install the root command <name> (e.g. ./init.sh mu)' \
    '  ./init.sh --uninstall <name>   uninstall it'
  [[ -n $CB_NAME ]] && exit 0 || exit 2
fi
CB_CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/$CB_NAME
source "$CB_ROOT/lib/core.sh"

[[ $CB_NAME =~ ^[a-z][a-z0-9_-]*$ ]] || ui::die "invalid name '$CB_NAME' (lower case letters, digits, - and _, starting with a letter)"

bin_dir=$HOME/.local/bin
link=$bin_dir/$CB_NAME
target=$CB_ROOT/main.sh
rc_begin="# >>> cmd-builder: $CB_NAME >>>"
rc_end="# <<< cmd-builder: $CB_NAME <<<"
zshrc=${ZDOTDIR:-$HOME}/.zshrc

# Path for display, with $HOME shown as ~. Not "${p/#$HOME/\~}": Bash 4.2 keeps the backslash.
tilde() {
  if [[ $1 == "$HOME" || $1 == "$HOME"/* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi
}

# ---------------------------------------------------------------------------
# Uninstall. Each step is independent and first checks whether it was already
# done: if the script is interrupted halfway, running it again simply finishes
# the job.
# ---------------------------------------------------------------------------

# Step 1: the ~/.local/bin/<name> link, only if it points to this cmd-builder.
uninstall_link() {
  if [[ ! -e $link && ! -L $link ]]; then
    ui::info "link $link: already removed"
  elif [[ -L $link && ($(readlink -- "$link") == "$target" || $(cb::realpath "$link" 2>/dev/null) == "$target") ]]; then
    rm -f -- "$link" && ui::success "link $link removed"
  else
    ui::warn "$link is not a link to this cmd-builder: left in place"
  fi
}

# Step 2: the block added to an rc file. Atomic rewrite (temp file + mv):
# an interruption leaves either the old file or the new one.
uninstall_rc() {
  local rc=$1 real tmp line skip=0 pending=0
  local -a out=()
  [[ -e $rc ]] || return 0
  real=$(cb::realpath "$rc") || real=$rc # if the rc is a symlink (dotfiles), edit its target
  tmp=$real.cb-uninstall.tmp
  rm -f -- "$tmp" # possible leftover of a previous interruption
  if ! grep -qF "$rc_begin" "$real"; then
    ui::info "$(tilde "$rc"): already cleaned"
    return 0
  fi
  while IFS= read -r line || [[ -n $line ]]; do
    if ((skip)); then
      [[ $line == "$rc_end" ]] && skip=0
      continue
    fi
    if [[ $line == "$rc_begin" ]]; then
      skip=1
      ((pending)) && pending=0 # also drop the blank line added before the block
      continue
    fi
    ((pending)) && out+=('')
    pending=0
    if [[ -z $line ]]; then pending=1; else out+=("$line"); fi
  done <"$real"
  if ((skip)); then
    # Begin marker without its end marker (edited by hand?): rewriting would drop the
    # whole end of the file, so leave it untouched.
    ui::warn "$(tilde "$rc"): '$rc_begin' found but not '$rc_end'; file left untouched, remove the block by hand"
    uninstall_incomplete=1
    return 1
  fi
  ((pending)) && out+=('')
  if ((${#out[@]})); then printf '%s\n' "${out[@]}" >"$tmp"; else : >"$tmp"; fi
  chmod --reference="$real" "$tmp" 2>/dev/null || chmod "$(stat -f %Lp "$real" 2>/dev/null || echo 644)" "$tmp"
  mv -f -- "$tmp" "$real" && ui::success "'$CB_NAME' block removed from $(tilde "$rc")"
}

# Step 3: the files of ~/.config/<name>, one by one, then the directory if empty.
uninstall_config() {
  local f
  if [[ ! -d $CB_CONFIG_DIR ]]; then
    ui::info "$CB_CONFIG_DIR: already removed"
    return 0
  fi
  for f in completion.bash completion.zsh config.tmp; do
    [[ -e $CB_CONFIG_DIR/$f ]] && rm -f -- "$CB_CONFIG_DIR/$f" && ui::success "$CB_CONFIG_DIR/$f removed"
  done
  if [[ -e $CB_CONFIG_DIR/config ]]; then
    if ui::confirm "Also remove your configuration ($CB_CONFIG_DIR/config)?" y; then
      rm -f -- "$CB_CONFIG_DIR/config" && ui::success "$CB_CONFIG_DIR/config removed"
    else
      ui::info "configuration kept"
    fi
  fi
  if rmdir -- "$CB_CONFIG_DIR" 2>/dev/null; then
    ui::success "$CB_CONFIG_DIR removed"
  elif [[ -d $CB_CONFIG_DIR ]]; then
    ui::info "$CB_CONFIG_DIR kept (it still contains files)"
  fi
}

if [[ $mode == uninstall ]]; then
  ui::title "Uninstalling '$CB_NAME'"
  uninstall_incomplete=0
  uninstall_link
  uninstall_rc "$HOME/.bashrc"
  uninstall_rc "$zshrc"
  uninstall_config
  echo
  if ((uninstall_incomplete)); then
    ui::warn "'$CB_NAME' is uninstalled, except the rc file block(s) reported above."
  else
    ui::success "'$CB_NAME' is uninstalled. Open a new terminal for it to take effect."
  fi
  ui::info "The $CB_ROOT directory (and your plugins) is untouched: delete it by hand if you want."
  ((uninstall_incomplete)) && exit 1
  exit 0
fi

# Is the name already taken?
case $(type -t "$CB_NAME") in
  keyword | builtin) ui::die "'$CB_NAME' is a shell keyword or builtin, choose another name" ;;
esac
if [[ -e $link || -L $link ]]; then
  if [[ $(cb::realpath "$link") != "$target" ]]; then
    ui::warn "$link already exists and does not point to this cmd-builder"
    ui::confirm "Replace it?" n || ui::die "installation cancelled"
  fi
elif existing=$(command -v "$CB_NAME" 2>/dev/null); then
  ui::warn "a command '$CB_NAME' already exists: $existing"
  ui::confirm "Install anyway (one will hide the other depending on PATH order)?" n || ui::die "installation cancelled"
fi

chmod +x "$target" "$CB_ROOT/init.sh"
mkdir -p "$bin_dir"
ln -sfn "$target" "$link"
ui::success "command installed: $link → $target"

cb::config_ensure
ui::success "configuration: $CB_CONFIG_DIR/config"
cb::completion_install
ui::success "completion generated in $CB_CONFIG_DIR/"

# rc file integration (PATH + completion), after confirmation.
rc_block() {
  local shell=$1 rc=$2 begin=$rc_begin end=$rc_end
  local comp=$CB_CONFIG_DIR/completion.$shell
  if [[ -f $rc ]] && grep -qF "$begin" "$rc"; then
    ui::info "already configured in $(tilde "$rc")"
    return 0
  fi
  ui::confirm "Enable '$CB_NAME' completion in $(tilde "$rc")?" y || return 1
  {
    printf '\n%s\n' "$begin"
    printf 'case ":$PATH:" in *":%s:"*) ;; *) export PATH="%s:$PATH" ;; esac\n' "$bin_dir" "$bin_dir"
    printf '[ -f "%s" ] && . "%s"\n' "$comp" "$comp"
    printf '%s\n' "$end"
  } >>"$rc"
  ui::success "added to $(tilde "$rc")"
}

configured=0 bash_ok=0 zsh_ok=0
if [[ -f $HOME/.bashrc || $SHELL == */bash ]]; then
  rc_block bash "$HOME/.bashrc" && configured=1 bash_ok=1
fi
if [[ -f $zshrc || $SHELL == */zsh ]]; then
  rc_block zsh "$zshrc" && configured=1 zsh_ok=1
fi

# rc file to reload in the current terminal: the one of the user's shell, if configured.
reload_rc=
case $SHELL in
  */bash) ((bash_ok)) && reload_rc=$HOME/.bashrc ;;
  */zsh) ((zsh_ok)) && reload_rc=$zshrc ;;
esac
if [[ -z $reload_rc ]] && ((bash_ok + zsh_ok == 1)); then
  ((bash_ok)) && reload_rc=$HOME/.bashrc || reload_rc=$zshrc
fi

case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *)
    if ((configured)); then
      ui::info "$bin_dir will be in your PATH in new terminals"
    else
      ui::warn "$bin_dir is not in your PATH: add 'export PATH=\"$bin_dir:\$PATH\"' to your rc file"
    fi
    ;;
esac

echo
if [[ -n $reload_rc ]]; then
  # This terminal read its rc file before the install: completion is not loaded here yet.
  ui::success "All set! Open a new terminal, or run this in the current one:"
  printf '  source %s\n' "$(tilde "$reload_rc")"
  ui::info "Then try: $CB_NAME --help"
else
  ui::success "All set! Open a new terminal, then run: $CB_NAME --help"
fi
