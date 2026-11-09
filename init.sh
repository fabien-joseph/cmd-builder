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
source "$CB_ROOT/lib/install.sh"

cb::valid_root_name "$CB_NAME" || ui::die "invalid name '$CB_NAME' (lower case letters, digits, - and _, starting with a letter)"

bin_dir=$_CB_BIN_DIR
link=$bin_dir/$CB_NAME
target=$CB_ROOT/main.sh
rc_begin=$(cb::rc_begin "$CB_NAME")
rc_end=$(cb::rc_end "$CB_NAME")
zshrc=${ZDOTDIR:-$HOME}/.zshrc

# ---------------------------------------------------------------------------
# Uninstall. Each step is independent and first checks whether it was already
# done: if the script is interrupted halfway, running it again simply finishes
# the job.
# ---------------------------------------------------------------------------

# Step 2: the block added to an rc file (step 1, the link, is cb::link_remove).
uninstall_rc() {
  local rc=$1 rc_status=0
  cb::rc_replace "$rc" "$CB_NAME" || rc_status=$?
  case $rc_status in
    0) ui::success "'$CB_NAME' block removed from $(cb::tilde "$rc")" ;;
    2) [[ -e $rc ]] && ui::info "$(cb::tilde "$rc"): already cleaned" ;;
    *)
      ui::warn "$(cb::tilde "$rc"): '$rc_begin' found but not '$rc_end'; file left untouched, remove the block by hand"
      uninstall_incomplete=1
      return 1
      ;;
  esac
  return 0
}

# Step 3: the files of ~/.config/<name>, one by one, then the directory if empty.
uninstall_config() {
  local shared
  if [[ ! -d $CB_CONFIG_DIR ]]; then
    ui::info "$CB_CONFIG_DIR: already removed"
    return 0
  fi
  cb::config_dir_clean "$CB_CONFIG_DIR"
  if [[ -L $CB_CONFIG_DIR/config ]]; then
    # Shared with another name ("self rename --keep-old") or a dotfile: only the link goes.
    local to
    to=$(readlink -- "$CB_CONFIG_DIR/config")
    rm -f -- "$CB_CONFIG_DIR/config" && ui::success "link $CB_CONFIG_DIR/config removed (its target $to is kept)"
  elif shared=$(cb::config_shared_with "$CB_CONFIG_DIR/config"); then
    # The other name ("self rename --keep-old") uses this file through a link: it gets the file.
    rm -f -- "$shared" && mv -- "$CB_CONFIG_DIR/config" "$shared" &&
      ui::success "configuration moved to $shared (it is shared with '$(basename -- "$(dirname -- "$shared")")')"
  elif [[ -e $CB_CONFIG_DIR/config ]]; then
    if ui::confirm "Also remove your configuration ($CB_CONFIG_DIR/config)?" n; then
      rm -f -- "$CB_CONFIG_DIR/config" && ui::success "$CB_CONFIG_DIR/config removed"
    else
      ui::info "configuration kept"
    fi
  fi
  cb::config_dir_remove "$CB_CONFIG_DIR"
}

if [[ $mode == uninstall ]]; then
  ui::title "Uninstalling '$CB_NAME'"
  uninstall_incomplete=0
  cb::link_remove "$CB_NAME"
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
# Package manager for the tools user plugins may need (decision 0014): asked once.
source "$CB_ROOT/lib/deps.sh"
cb::config_load
((${#_CB_PMS[@]})) || cb::pm_ask || true
cb::completion_install
ui::success "completion generated in $CB_CONFIG_DIR/"

# rc file integration (PATH + completion), after confirmation.
rc_block() {
  local shell=$1 rc=$2
  if cb::rc_has "$rc" "$CB_NAME"; then
    ui::info "already configured in $(cb::tilde "$rc")"
    return 0
  fi
  ui::confirm "Enable '$CB_NAME' completion in $(cb::tilde "$rc")?" y || return 1
  cb::rc_append "$rc" "$shell" "$CB_NAME"
  ui::success "added to $(cb::tilde "$rc")"
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
  printf '  source %s\n' "$(cb::tilde "$reload_rc")"
  ui::info "Then try: $CB_NAME --help"
else
  ui::success "All set! Open a new terminal, then run: $CB_NAME --help"
fi
