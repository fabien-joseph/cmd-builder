#!/usr/bin/env bash
# cmd-builder — entry point.
# Installed with "./init.sh <name>": ~/.local/bin/<name> is a symlink to this file,
# and the name of the link becomes the name of the root command.

case ${BASH_VERSION:-} in
  '' | [0-3].* | 4.[01].*)
    printf '%s\n' "cmd-builder requires Bash >= 4.2 (current: ${BASH_VERSION:-none})." \
      "On macOS: brew install bash" >&2
    exit 1
    ;;
esac
# Bash in POSIX mode ("sh init.sh" where sh is Bash) rejects the "cb::" function names; an
# exported CDPATH would change what the "cd" below and in the libraries do.
set +o posix
unset CDPATH

# Resolves the symlink to find the project root (without readlink -f).
_cb_self=${BASH_SOURCE[0]}
while [[ -L $_cb_self ]]; do
  _cb_dir=$(cd -P "$(dirname -- "$_cb_self")" && pwd)
  _cb_self=$(readlink -- "$_cb_self")
  [[ $_cb_self == /* ]] || _cb_self=$_cb_dir/$_cb_self
done
CB_ROOT=$(cd -P "$(dirname -- "$_cb_self")" && pwd)
unset _cb_self _cb_dir

CB_NAME=${0##*/}
[[ $CB_NAME == main.sh ]] && CB_NAME=cmd-builder
CB_CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/$CB_NAME
export CB_ROOT CB_NAME CB_CONFIG_DIR

unset _CB_NO_DYNAMIC # internal (self doctor): never taken from the environment
source "$CB_ROOT/lib/core.sh"
cb::main "$@"
