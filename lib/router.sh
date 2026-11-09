# Routing: <name> <plugin> [subcommand...] [options/arguments]
#
# Words naming a subcommand are consumed as long as there are some; the first
# word that is not one (or an option) is passed on to the command reached.

cb::main() {
  cb::config_load
  cb::plugins_load

  case ${1:-} in
    __complete)
      shift
      [[ ${1:-} == -- ]] && shift
      cb::complete "$@"
      return 0
      ;;
    '' | -h | --help)
      cb::help_root
      return 0
      ;;
    -*)
      ui::error "unknown option '$1'"
      printf "See '%s --help'.\n" "$CB_NAME" >&2
      return 2
      ;;
  esac

  local name=$1 top
  shift
  top=$(cb::plugin_dir "$name") || cb::_unknown_plugin "$name"
  cb::descend "$top" "$@"
  local -a path=("$CB_NAME" "$name" "${@:1:_CB_ROUTE_N}")
  shift "$_CB_ROUTE_N"
  cb::run "$_CB_ROUTE_DIR" "$(cb::plugin_root_of "$_CB_ROUTE_DIR" "$top")" "${path[*]}" "$@"
}

cb::_unknown_plugin() {
  local name=$1 id s
  ui::error "unknown command '$name'"
  for id in "${_CB_IDS[@]}"; do
    if [[ ${_CB_ID_NAME[$id]} == "$name" && ${_CB_ID_STATE[$id]} == disabled ]]; then
      printf "  Plugin %s is disabled: '%s self plugins enable %s'\n" "$id" "$CB_NAME" "$id" >&2
    fi
  done
  s=$(cb::suggest "$name" "${_CB_PLUGIN_NAMES[@]}" self)
  [[ -n $s ]] && printf '  Did you mean: %s?\n' "$s" >&2
  printf "See '%s --help'.\n" "$CB_NAME" >&2
  exit 2
}

# Stops before running a command whose required tools are missing (decision 0014).
cb::_check_requires() {
  local t list
  local -a missing=()
  for t in "${_CB_REQS[@]}"; do
    [[ -n ${_CB_R_OPT[$t]} ]] && continue
    command -v "$t" >/dev/null 2>&1 || missing+=("$t")
  done
  ((${#missing[@]})) || return 0
  list=$(printf "'%s', " "${missing[@]}")
  ui::error "'$1' needs ${list%, }, not installed"
  printf "  Install: %s self deps install\n" "$CB_NAME" >&2
  exit 1
}

# cb::run <dir> <plugin dir> <display> args...
cb::run() {
  # The spec is loaded before any local exists: assignments at the top of flags.sh then
  # cannot overwrite them (they only reach the locals of cb::main, unused afterwards).
  # CB_COMMAND* are exported first, so flags.sh and --choices-from --strict see them.
  export CB_COMMAND=$3 CB_COMMAND_DIR=$1 CB_PLUGIN_ROOT=$2
  cb::spec_load "$1"
  local dir=$1 top=$2 display=$3 exe s
  shift 3
  exe=$(cb::executable "$dir")

  if [[ -z $exe ]]; then
    # Pure router: no executable, only subcommands.
    if (($# == 0)) || [[ $1 == -h || $1 == --help ]]; then
      cb::help "$dir" "$display"
      exit 0
    fi
    if [[ $1 == -* ]]; then
      ui::error "unknown option '$1'"
    else
      ui::error "unknown subcommand '$1'"
      s=$(cb::suggest "$1" $(cb::children "$dir"))
      [[ -n $s ]] && printf '  Did you mean: %s?\n' "$s" >&2
    fi
    printf "See '%s --help'.\n" "$display" >&2
    exit 2
  fi

  cb::parse "$dir" "$display" "$@"
  cb::_check_requires "$display"
  cb::export_values
  if [[ $exe == */cmd.sh ]]; then
    # A fresh Bash with the ui:: helpers, then cmd.sh sourced: "$0" is cmd.sh itself,
    # "$@" the positionals, and a top-level "return" sets the exit code.
    exec "$BASH" -c 'source "$CB_ROOT/lib/ui.sh" && source "$0"' "$exe" "${_CB_POS[@]}"
  else
    exec "$exe" "${_CB_POS[@]}"
  fi
}
