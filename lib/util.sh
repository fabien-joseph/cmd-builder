# Internal utility functions.

# Characters of names, written out: a range such as [a-z] depends on the user's locale
# (under tr_TR.UTF-8 it does not contain "i"; under en_US.UTF-8 it matches accented letters). Every name
# check uses these patterns (review of 2026-11-09, POR-05).
_CB_AZ=abcdefghijklmnopqrstuvwxyz _CB_AZU=ABCDEFGHIJKLMNOPQRSTUVWXYZ _CB_09=0123456789
_CB_AN=$_CB_AZ$_CB_AZU$_CB_09
_CB_RE_NAME="^[$_CB_AN][${_CB_AN}_-]*$"                        # command and plugin directories
_CB_RE_ID="^(core|user):[$_CB_AN][${_CB_AN}_-]*$|^user:[+][$_CB_AN][${_CB_AN}_-]*$"
_CB_RE_ROOT="^[$_CB_AZ][$_CB_AZ${_CB_09}_-]*$"                 # root command name
_CB_RE_FLAG="^[$_CB_AZ$_CB_09][$_CB_AZ${_CB_09}-]*$"
_CB_RE_ARG="^[$_CB_AZ$_CB_09][$_CB_AZ${_CB_09}_-]*$"
_CB_RE_SHORT="^[$_CB_AN]$"
_CB_RE_TOOL="^[$_CB_AN][${_CB_AN}._+-]*$"
_CB_RE_PKG="^([${_CB_AN}@][${_CB_AN}._+@/-]*|-)$"
_CB_RE_INT="^-?[$_CB_09]+$"

# Absolute path of a file, symlinks resolved (portable, without readlink -f).
cb::realpath() {
  local p=$1 d
  while [[ -L $p ]]; do
    d=$(cd -P "$(dirname -- "$p")" && pwd) || return 1
    p=$(readlink -- "$p")
    [[ $p == /* ]] || p=$d/$p
  done
  d=$(cd -P "$(dirname -- "$p")" && pwd) || return 1
  printf '%s/%s\n' "$d" "${p##*/}"
}

# Valid name for a command or a plugin.
cb::valid_name() { [[ $1 =~ $_CB_RE_NAME ]]; }

# Valid name for the root command (stricter than cb::valid_name: it becomes a file name in
# ~/.local/bin and is written into shell code: completion scripts, rc blocks).
cb::valid_root_name() { [[ $1 =~ $_CB_RE_ROOT ]]; }

# A directory is a command if it contains flags.sh, cmd.sh or cmd.
cb::is_command_dir() {
  [[ -d $1 ]] && [[ -f $1/flags.sh || -f $1/cmd.sh || -f $1/cmd ]]
}

# Executable of a command (cmd.sh first), empty for a pure router.
cb::executable() {
  if [[ -f $1/cmd.sh ]]; then
    printf '%s' "$1/cmd.sh"
  elif [[ -f $1/cmd && -x $1/cmd ]]; then
    printf '%s' "$1/cmd"
  fi
}

# Subcommands of a directory (one per line, sorted). Ignores _xxx, .xxx and +xxx.
# The subcommands of its extension (_CB_OVL, plugins/+<plugin>/, decision 0013) are merged in.
cb::children() {
  local d n ovl=${_CB_OVL[$1]:-}
  if [[ -z $ovl ]]; then
    for d in "$1"/*/; do
      d=${d%/}
      n=${d##*/}
      cb::valid_name "$n" && cb::is_command_dir "$d" && printf '%s\n' "$n"
    done
    return 0
  fi
  for d in "$1"/*/ "$ovl"/*/; do
    d=${d%/}
    n=${d##*/}
    cb::valid_name "$n" && cb::is_command_dir "$d" && printf '%s\n' "$n"
  done | sort -u
}

cb::is_child() {
  cb::valid_name "$2" || return 1
  cb::is_command_dir "$1/$2" || { [[ -n ${_CB_OVL[$1]:-} ]] && cb::is_command_dir "${_CB_OVL[$1]}/$2"; }
}

# Directory of the subcommand <name> of <dir>: the one of the extension of <dir> if it has
# it (a user command shadows the official one), otherwise <dir>/<name>.
# Same as cb::child_dir, result in REPLY: no subshell, for loops over many children.
cb::child_dir_r() {
  local ovl=${_CB_OVL[$1]:-}
  if [[ -n $ovl ]] && cb::is_command_dir "$ovl/$2"; then REPLY=$ovl/$2; else REPLY=$1/$2; fi
}

cb::child_dir() {
  local ovl=${_CB_OVL[$1]:-}
  if [[ -n $ovl ]] && cb::is_command_dir "$ovl/$2"; then printf '%s' "$ovl/$2"; else printf '%s' "$1/$2"; fi
}

# The one routing rule (decision 0001), shared by cb::main, completion and self doctor:
# from the command directory <dir>, the following words that name a subcommand are consumed.
# Sets _CB_ROUTE_DIR (directory reached) and _CB_ROUTE_N (number of words consumed).
cb::descend() { # dir word...
  _CB_ROUTE_DIR=$1 _CB_ROUTE_N=0
  shift
  while (($#)) && cb::is_child "$_CB_ROUTE_DIR" "$1"; do
    _CB_ROUTE_DIR=$(cb::child_dir "$_CB_ROUTE_DIR" "$1")
    ((++_CB_ROUTE_N))
    shift
  done
}

# Prints "directory<TAB>words" for a command then, recursively, for all its subcommands
# (words: the path of names below <dir>, e.g. "db restore"). A symlinked subcommand that
# points back to the directory or one of its parents is skipped: it would never end.
cb::walk() { # dir [words] [physical path of dir]
  local real=${3:-} c d r
  [[ -n $real ]] || real=$(cd -P -- "$1" 2>/dev/null && pwd)
  printf '%s\t%s\n' "$1" "${2:-}"
  while IFS= read -r c; do
    [[ -n $c ]] || continue
    d=$(cb::child_dir "$1" "$c")
    if [[ ! -L $d && ${d%/*} == "$1" ]]; then
      r=$real/$c
    else
      r=$(cd -P -- "$d" 2>/dev/null && pwd) || continue
      [[ $real == "$r" || $real == "$r"/* ]] && continue
    fi
    cb::walk "$d" "${2:+$2 }$c" "$r"
  done < <(cb::children "$1")
}

# Root directory of the plugin that contains the command directory <dir>: an extension
# (plugins/+x) has its own, even when it is reached through the official plugin.
cb::plugin_root_of() { # dir default
  local rel
  case $1 in
    "$CB_ROOT"/plugins/+*)
      rel=${1#"$CB_ROOT"/plugins/}
      printf '%s' "$CB_ROOT/plugins/${rel%%/*}"
      ;;
    *) printf '%s' "$2" ;;
  esac
}

# True if $1 is one of the following words.
cb::in_list() {
  local v=$1 x
  shift
  for x; do [[ $x == "$v" ]] && return 0; done
  return 1
}

# Suggestions close to $1 among the following candidates (separated by ", ").
cb::suggest() {
  local w=$1 c out=()
  shift
  for c; do
    [[ -z $c || -z $w ]] && continue
    if [[ $c == "$w"* || $w == "$c"* || $c == *"$w"* || ${c:0:2} == "${w:0:2}" ]]; then
      out+=("$c")
    fi
  done
  local IFS=,
  [[ ${#out[@]} -gt 0 ]] && printf '%s' "${out[*]}" | sed 's/,/, /g'
}

# Escapes a string to write it between double quotes in a script.
cb::dq() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//\$/\\\$}
  s=${s//\`/\\\`}
  printf '%s' "$s"
}
