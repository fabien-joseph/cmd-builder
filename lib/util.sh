# Internal utility functions.

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
cb::valid_name() { [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; }

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

# Subcommands of a directory (one per line, sorted). Ignores _xxx and .xxx.
cb::children() {
  local d n
  for d in "$1"/*/; do
    d=${d%/}
    n=${d##*/}
    cb::valid_name "$n" && cb::is_command_dir "$d" && printf '%s\n' "$n"
  done
}

cb::is_child() { cb::valid_name "$2" && cb::is_command_dir "$1/$2"; }

# Prints a command directory then, recursively, all its subcommands.
cb::walk() {
  printf '%s\n' "$1"
  local c
  while IFS= read -r c; do
    [[ -n $c ]] && cb::walk "$1/$c"
  done < <(cb::children "$1")
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
