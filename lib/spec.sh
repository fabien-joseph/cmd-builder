# Loading of flags.sh files and the declaration DSL.
#
#   about       "One-line summary"
#   description "Longer text shown in --help"
#   flag <name> [-x] <bool|string|int> "description" [--default v] [--required] [choices]
#   arg  <name> "description" [--optional] [--variadic] [choices]
#
#   choices: --choices "a b c"          fixed list, validated
#            --choices-from "command"   list computed on the fly (one value per line,
#                                       "value<TAB>description" allowed): suggested by
#                                       completion, validated only with --strict
#   example "subcommand --flag" ["explanation"]     (prefixed with the root command name)
#   requires <command> [--optional] [--apt|--dnf|--pacman|--zypper|--apk|--brew <package|->]
#                                       a tool the command needs (decision 0014)
#
# Values reach cmd.sh as FLAG_<NAME> and ARG_<NAME> (upper case, "-" → "_").

# Associative arrays are declared here, outside any function: Bash 4.2 does not create the
# global for "declare -gA name=()" run inside a function (decision 0011). Functions only
# reset them with "name=()", which keeps the associative type.
declare -gA _CB_F_SHORT=() _CB_F_TYPE=() _CB_F_DESC=() _CB_F_DEFAULT=() _CB_F_REQ=() _CB_F_CHOICES=() _CB_F_BYSHORT=()
declare -gA _CB_F_CHFROM=() _CB_F_STRICT=()
declare -gA _CB_A_DESC=() _CB_A_OPT=() _CB_A_VAR=() _CB_A_CHOICES=() _CB_A_CHFROM=() _CB_A_STRICT=()
declare -gA _CB_R_OPT=() _CB_R_PKG=() # requires: tool -> 1 if optional; "<manager>/<tool>" -> package

cb::spec_reset() {
  _CB_ABOUT= _CB_DESC= _CB_SPEC_FILE=
  _CB_EXAMPLES=() _CB_FLAGS=() _CB_ARGS=()
  _CB_F_SHORT=() _CB_F_TYPE=() _CB_F_DESC=() _CB_F_DEFAULT=() _CB_F_REQ=() _CB_F_CHOICES=() _CB_F_BYSHORT=()
  _CB_F_CHFROM=() _CB_F_STRICT=()
  _CB_A_DESC=() _CB_A_OPT=() _CB_A_VAR=() _CB_A_CHOICES=() _CB_A_CHFROM=() _CB_A_STRICT=()
  _CB_REQS=() _CB_R_OPT=() _CB_R_PKG=()
}

# Canonical form of a 64-bit integer, in REPLY ("08" -> 8, "-0" -> 0); returns 1 if <value>
# is not an integer in [-9223372036854775808, 9223372036854775807]. Bash arithmetic reads
# "010" as octal and fails on "08": commands receive the canonical decimal.
cb::int_canon() {
  local v=$1 sign= max=9223372036854775807
  [[ $v =~ $_CB_RE_INT ]] || return 1
  [[ $v == -* ]] && sign=- v=${v#-} max=9223372036854775808
  v=${v#"${v%%[!0]*}"}
  [[ -z $v ]] && v=0 sign=
  if ((${#v} > 19)) || { ((${#v} == 19)) && [[ $v > $max ]]; }; then return 1; fi
  REPLY=$sign$v
}

# Possible values of a flag (F) or an argument (A), one "value<TAB>description" per line.
# Static (--choices) or computed on the fly (--choices-from). Dynamic choices are
# evaluated in the user's current directory; functions defined in flags.sh and the
# CB_* variables are available.
cb::choices_of() {
  local kind=$1 name=$2 static from c
  if [[ $kind == F ]]; then static=${_CB_F_CHOICES[$name]:-} from=${_CB_F_CHFROM[$name]:-}; else static=${_CB_A_CHOICES[$name]:-} from=${_CB_A_CHFROM[$name]:-}; fi
  if [[ -n $from ]]; then
    (eval "$from") 2>/dev/null </dev/null # never the keys typed after Tab, nor the command's input
  else
    local -a list=()
    read -ra list <<<"$static" # split on blanks, never glob-expanded ("*.txt" stays itself)
    for c in "${list[@]}"; do printf '%s\t\n' "$c"; done
  fi
  return 0
}

# True if the value is allowed (no choices, non-strict dynamic choices, or listed value).
# Sets _CB_CHOICES_LIST = allowed values (for the error message).
cb::choice_ok() {
  local kind=$1 name=$2 val=$3 static strict line
  if [[ $kind == F ]]; then static=${_CB_F_CHOICES[$name]:-} strict=${_CB_F_STRICT[$name]:-}; else static=${_CB_A_CHOICES[$name]:-} strict=${_CB_A_STRICT[$name]:-}; fi
  _CB_CHOICES_LIST=()
  if [[ -n $static ]]; then
    read -ra _CB_CHOICES_LIST <<<"$static"
  elif [[ -n $strict && -z ${_CB_NO_DYNAMIC:-} ]]; then
    while IFS= read -r line; do
      [[ -n $line ]] && _CB_CHOICES_LIST+=("${line%%$'\t'*}")
    done < <(cb::choices_of "$kind" "$name")
  else
    return 0
  fi
  cb::in_list "$val" "${_CB_CHOICES_LIST[@]}"
}

# Options shared by flag and arg: --choices, --choices-from, --strict.
# Usage: cb::_spec_choice_opt "$@" ; the caller shifts by _CB_OPT_SHIFT.
cb::_spec_choice_opt() {
  _CB_OPT_SHIFT=0
  case $1 in
    --choices)
      (($# >= 2)) || cb::_spec_err "--choices expects a list"
      _o_choices=$2 _CB_OPT_SHIFT=2
      ;;
    --choices-from)
      (($# >= 2)) || cb::_spec_err "--choices-from expects a command"
      _o_from=$2 _CB_OPT_SHIFT=2
      ;;
    --strict) _o_strict=1 _CB_OPT_SHIFT=1 ;;
    *) return 1 ;;
  esac
}

cb::_spec_choice_check() {
  local label=$1
  [[ -n $_o_choices && -n $_o_from ]] && cb::_spec_err "$label: --choices and --choices-from are mutually exclusive"
  [[ -n $_o_strict && -z $_o_from ]] && cb::_spec_err "$label: --strict can only be used with --choices-from"
  return 0
}

# Loads the flags.sh of <dir>. It is plugin code run in the framework process, so what it
# may change is put back afterwards: shell options (set -euo pipefail is a common habit),
# failglob, IFS (local here), the current directory; what it prints goes to stderr, never
# into the command's output or its --help. Its variables and functions stay (snippets of
# --choices-from use them): callers must not keep unprefixed locals across this call
# (review of 2026-11-09, PAR-01), see cb::run and cb::complete.
cb::spec_load() {
  cb::spec_reset
  local f=$1/flags.sh _cb_pwd=$PWD IFS=$' \t\n'
  [[ -f $f ]] || return 0
  _CB_SPEC_FILE=$f
  # shellcheck disable=SC1090
  source "$f" >&2
  set +o errexit +o nounset +o pipefail
  shopt -u failglob
  [[ $PWD == "$_cb_pwd" ]] || builtin cd -- "$_cb_pwd" >/dev/null 2>&1
  # The status of the file's last command is meaningless (e.g. "cmd && flag ..."):
  # DSL errors exit with code 3 through cb::_spec_err.
  return 0
}

# Summary (about) of a command, without touching the current state.
cb::about_of() {
  (
    cb::spec_load "$1" >/dev/null 2>&1
    printf '%s' "$_CB_ABOUT"
  )
}

# Summaries of several commands, in _CB_ABOUTS (same order): one subshell for the whole list
# instead of one per command (root help and Tab with many plugins, review CMP-04). If a
# flags.sh ends that subshell early (exit), the missing ones are read one by one.
declare -ga _CB_ABOUTS=()
cb::abouts_of() { # dir...
  local i
  mapfile -t _CB_ABOUTS < <(
    for d; do
      cb::spec_load "$d" >/dev/null 2>&1
      printf '%s\n' "${_CB_ABOUT//$'\n'/ }"
    done
  )
  for ((i = ${#_CB_ABOUTS[@]}; i < $#; i++)); do
    _CB_ABOUTS[i]=$(cb::about_of "${@:i+1:1}")
  done
}

cb::_spec_err() {
  # Line of flags.sh that triggered the call, whatever the call depth.
  local i line=?
  for ((i = 0; i < ${#BASH_SOURCE[@]} - 1; i++)); do
    if [[ ${BASH_SOURCE[i + 1]} == "$_CB_SPEC_FILE" ]]; then
      line=${BASH_LINENO[i]}
      break
    fi
  done
  ui::die "${_CB_SPEC_FILE:-flags.sh}:$line: $1" 3
}

about()       { _CB_ABOUT=$*; }
description() { _CB_DESC=$*; }

example() {
  (($# >= 1)) || cb::_spec_err 'usage: example "command" ["explanation"]'
  _CB_EXAMPLES+=("$1" "${2:-}")
}

# A tool the command needs. The package has the name of the tool unless a package manager
# option says otherwise ("-": not packaged for that manager). Checked before the command
# runs, unless --optional (the command then checks it itself: command -v).
requires() {
  local usage='usage: requires <command> [--optional] [--apt|--dnf|--pacman|--zypper|--apk|--brew <package|->]'
  local tool=${1:-}
  [[ $tool =~ $_CB_RE_TOOL ]] || cb::_spec_err "invalid command name '$tool' ($usage)"
  shift
  [[ -n ${_CB_R_OPT[$tool]+x} ]] && cb::_spec_err "'$tool' is required twice"
  _CB_R_OPT[$tool]=
  while (($#)); do
    case $1 in
      --optional) _CB_R_OPT[$tool]=1 && shift ;;
      --apt | --dnf | --pacman | --zypper | --apk | --brew)
        [[ ${2:-} =~ $_CB_RE_PKG ]] || cb::_spec_err "$1 expects a package name or '-' ($usage)"
        _CB_R_PKG[${1#--}/$tool]=$2
        shift 2
        ;;
      *) cb::_spec_err "unknown option '$1' for requires $tool" ;;
    esac
  done
  _CB_REQS+=("$tool")
  return 0
}

flag() {
  local usage='usage: flag <name> [-x] <bool|string|int> "description" [--default v] [--required] [--choices "a b" | --choices-from cmd [--strict]]'
  local name=${1:-} short= type desc def= hasdef= req= choices= _o_choices= _o_from= _o_strict=
  local -a list=()
  [[ $name =~ $_CB_RE_FLAG ]] || cb::_spec_err "invalid flag name '$name' ($usage)"
  shift
  if [[ ${1:-} == -? ]]; then
    short=${1#-}
    shift
  fi
  (($# >= 2)) || cb::_spec_err "$usage"
  type=$1 desc=$2
  shift 2
  while (($#)); do
    case $1 in
      --default)
        (($# >= 2)) || cb::_spec_err "--default expects a value"
        def=$2 hasdef=1
        shift 2
        ;;
      --choices | --choices-from | --strict)
        cb::_spec_choice_opt "$@"
        shift "$_CB_OPT_SHIFT"
        ;;
      --required) req=1 && shift ;;
      *) cb::_spec_err "unknown option '$1' for flag --$name" ;;
    esac
  done

  choices=$_o_choices
  cb::_spec_choice_check "--$name"
  case $type in bool | string | int) ;; *) cb::_spec_err "unknown type '$type' for --$name (bool, string, int)" ;; esac
  [[ $name == help ]] && cb::_spec_err "--help is reserved"
  [[ -n ${_CB_F_TYPE[$name]+x} ]] && cb::_spec_err "--$name is declared twice"
  if [[ -n $short ]]; then
    [[ $short =~ $_CB_RE_SHORT ]] || cb::_spec_err "invalid short option '-$short'"
    [[ $short == h ]] && cb::_spec_err "-h is reserved for --help"
    [[ -n ${_CB_F_BYSHORT[$short]+x} ]] && cb::_spec_err "-$short is already used by --${_CB_F_BYSHORT[$short]}"
  fi
  if [[ $type == bool ]]; then
    [[ -n ${_CB_F_TYPE[no-$name]+x} ]] && cb::_spec_err "--$name: --no-$name is already a flag (it would not turn --$name off)"
    [[ -n $choices || -n $_o_from || -n $req ]] && cb::_spec_err "--$name is a bool: --choices, --choices-from and --required do not apply"
    [[ -z $hasdef || $def == 0 || $def == 1 ]] || cb::_spec_err "--$name is a bool: --default must be 0 or 1"
  fi
  [[ $name == no-* && ${_CB_F_TYPE[${name#no-}]:-} == bool ]] &&
    cb::_spec_err "--$name is reserved: it turns the bool --${name#no-} off"
  [[ -n $req && -n $hasdef ]] && cb::_spec_err "--$name: --required and --default exclude each other"
  if [[ -n $hasdef && $type == int ]]; then
    cb::int_canon "$def" || cb::_spec_err "--$name: default value '$def' is not a 64-bit integer"
    def=$REPLY
  fi
  read -ra list <<<"$choices"
  if [[ -n $hasdef && -n $choices ]] && ! cb::in_list "$def" "${list[@]}"; then
    cb::_spec_err "--$name: default value '$def' is not one of the choices ($choices)"
  fi

  _CB_FLAGS+=("$name")
  _CB_F_TYPE[$name]=$type
  _CB_F_DESC[$name]=$desc
  _CB_F_SHORT[$name]=$short
  _CB_F_REQ[$name]=$req
  _CB_F_CHOICES[$name]=$choices
  _CB_F_CHFROM[$name]=$_o_from
  _CB_F_STRICT[$name]=$_o_strict
  [[ -n $hasdef ]] && _CB_F_DEFAULT[$name]=$def
  [[ -n $short ]] && _CB_F_BYSHORT[$short]=$name
  return 0
}

arg() {
  local usage='usage: arg <name> "description" [--optional] [--variadic] [--choices "a b" | --choices-from cmd [--strict]]'
  (($# >= 2)) || cb::_spec_err "$usage"
  local name=$1 desc=$2 opt= var= last _o_choices= _o_from= _o_strict=
  [[ $name =~ $_CB_RE_ARG ]] || cb::_spec_err "invalid argument name '$name'"
  shift 2
  while (($#)); do
    case $1 in
      --optional) opt=1 && shift ;;
      --variadic) var=1 && shift ;;
      --choices | --choices-from | --strict)
        cb::_spec_choice_opt "$@"
        shift "$_CB_OPT_SHIFT"
        ;;
      *) cb::_spec_err "unknown option '$1' for arg $name" ;;
    esac
  done
  cb::_spec_choice_check "<$name>"
  [[ -n ${_CB_A_DESC[$name]+x} ]] && cb::_spec_err "argument '$name' is declared twice"
  # Guarded by the count: under a "set -u" of flags.sh, Bash < 4.4 calls an empty "${a[@]}" unbound.
  if ((${#_CB_ARGS[@]})); then
    for last in "${_CB_ARGS[@]}"; do
      [[ ${last//-/_} == "${name//-/_}" ]] && cb::_spec_err "'$name' and '$last' would both be ARG_${name//-/_}: rename one"
    done
    last=${_CB_ARGS[-1]}
    [[ -n ${_CB_A_VAR[$last]} ]] && cb::_spec_err "'$last' is variadic: it must be the last argument"
    [[ -n ${_CB_A_OPT[$last]} && -z $opt ]] && cb::_spec_err "'$name' is required but follows an optional argument"
  fi
  _CB_ARGS+=("$name")
  _CB_A_DESC[$name]=$desc
  _CB_A_OPT[$name]=$opt
  _CB_A_VAR[$name]=$var
  _CB_A_CHOICES[$name]=$_o_choices
  _CB_A_CHFROM[$name]=$_o_from
  _CB_A_STRICT[$name]=$_o_strict
  return 0
}
