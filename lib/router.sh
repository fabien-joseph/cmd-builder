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

  local name=$1 dir top
  shift
  dir=$(cb::plugin_dir "$name") || cb::_unknown_plugin "$name"
  top=$dir
  local -a path=("$CB_NAME" "$name")
  while (($#)) && cb::is_child "$dir" "$1"; do
    dir=$(cb::child_dir "$dir" "$1")
    path+=("$1")
    shift
  done
  cb::run "$dir" "$(cb::plugin_root_of "$dir" "$top")" "${path[*]}" "$@"
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

# cb::run <dir> <plugin dir> <display> args...
cb::run() {
  local dir=$1 top=$2 display=$3 exe s
  shift 3
  cb::spec_load "$dir"
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

  # Exported before parsing: --choices-from --strict snippets may use them.
  export CB_COMMAND=$display CB_COMMAND_DIR=$dir CB_PLUGIN_ROOT=$top
  cb::parse "$dir" "$display" "$@"
  cb::export_values
  if [[ $exe == */cmd.sh ]]; then
    exec "$BASH" "$CB_ROOT/lib/run.sh" "$exe" "${_CB_POS[@]}"
  else
    exec "$exe" "${_CB_POS[@]}"
  fi
}
