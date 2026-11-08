# Argument parsing against the loaded spec.
#
# Supports: --name, --name=val, --name val, --no-name (bool), -x, -x val, -xval,
# -abc (grouped bools), "--" (end of options). Options may appear anywhere among
# the arguments.
#
# Result: _CB_VAL[flag], _CB_AVAL[arg], _CB_POS (positional arguments).

cb::_parse_err() {
  ui::error "$1"
  [[ -n ${2:-} ]] && printf '  %s\n' "$2" >&2
  printf "See '%s --help'.\n" "$_CB_DISPLAY" >&2
  exit 2
}

cb::_choice_err() {
  local label=$1 val=$2 list
  if ((${#_CB_CHOICES_LIST[@]} == 0)); then
    cb::_parse_err "$label: invalid value '$val' (no value is currently possible)"
  fi
  list=$(printf '%s, ' "${_CB_CHOICES_LIST[@]:0:10}")
  list=${list%, }
  ((${#_CB_CHOICES_LIST[@]} > 10)) && list+=", … (Tab to see all)"
  cb::_parse_err "$label: invalid value '$val' (choices: $list)"
}

cb::_set_flag() {
  local name=$1 val=$2 label=$3
  if [[ ${_CB_F_TYPE[$name]} == int && ! $val =~ ^-?[0-9]+$ ]]; then
    cb::_parse_err "$label expects an integer (got '$val')"
  fi
  cb::choice_ok F "$name" "$val" || cb::_choice_err "$label" "$val"
  _CB_VAL[$name]=$val
}

cb::_check_choice() {
  cb::choice_ok A "$1" "$2" || cb::_choice_err "<$1>" "$2"
}

# cb::parse <dir> <display> args...
cb::parse() {
  _CB_DIR=$1 _CB_DISPLAY=$2
  shift 2
  declare -gA _CB_VAL=() _CB_AVAL=()
  _CB_POS=()
  local a name val c rest has endopts=0

  while (($#)); do
    a=$1
    shift
    if ((endopts)) || [[ $a != -?* ]]; then
      _CB_POS+=("$a")
      continue
    fi
    case $a in
      --) endopts=1 ;;
      --help)
        cb::help "$_CB_DIR" "$_CB_DISPLAY"
        exit 0
        ;;
      --*)
        name=${a#--} val= has=0
        if [[ $name == *=* ]]; then
          val=${name#*=} name=${name%%=*} has=1
        fi
        if [[ -z ${_CB_F_TYPE[$name]+x} ]]; then
          if [[ $name == no-* && ${_CB_F_TYPE[${name#no-}]:-} == bool ]] && ((!has)); then
            _CB_VAL[${name#no-}]=0
            continue
          fi
          cb::_parse_err "unknown option '--$name'" \
            "$(s=$(cb::suggest "$name" "${_CB_FLAGS[@]}") && [[ -n $s ]] && echo "Did you mean: --${s//, /, --}?")"
        fi
        if [[ ${_CB_F_TYPE[$name]} == bool ]]; then
          ((has)) && cb::_parse_err "--$name does not take a value"
          _CB_VAL[$name]=1
        else
          if ((!has)); then
            (($#)) || cb::_parse_err "--$name expects a value"
            val=$1
            shift
          fi
          cb::_set_flag "$name" "$val" "--$name"
        fi
        ;;
      *)
        rest=${a#-}
        # "-5" is a negative number, unless -5 is a declared short option.
        if [[ $rest =~ ^[0-9] && -z ${_CB_F_BYSHORT[${rest:0:1}]:-} ]]; then
          _CB_POS+=("$a")
          continue
        fi
        while [[ -n $rest ]]; do
          c=${rest:0:1} rest=${rest:1}
          if [[ $c == h ]]; then
            cb::help "$_CB_DIR" "$_CB_DISPLAY"
            exit 0
          fi
          name=${_CB_F_BYSHORT[$c]:-}
          [[ -n $name ]] || cb::_parse_err "unknown option '-$c'"
          if [[ ${_CB_F_TYPE[$name]} == bool ]]; then
            _CB_VAL[$name]=1
          else
            if [[ -n $rest ]]; then
              val=$rest rest=
            else
              (($#)) || cb::_parse_err "-$c expects a value"
              val=$1
              shift
            fi
            cb::_set_flag "$name" "$val" "-$c"
          fi
        done
        ;;
    esac
  done

  # Required flags and default values.
  for name in "${_CB_FLAGS[@]}"; do
    [[ -n ${_CB_VAL[$name]+x} ]] && continue
    [[ -n ${_CB_F_REQ[$name]} ]] && cb::_parse_err "--$name is required"
    if [[ ${_CB_F_TYPE[$name]} == bool ]]; then
      _CB_VAL[$name]=${_CB_F_DEFAULT[$name]:-0}
    else
      _CB_VAL[$name]=${_CB_F_DEFAULT[$name]:-}
    fi
  done

  # Positional arguments.
  local i=0 n=${#_CB_POS[@]} variadic=0
  for name in "${_CB_ARGS[@]}"; do
    if ((i >= n)); then
      [[ -n ${_CB_A_OPT[$name]} ]] || cb::_parse_err "missing argument: <$name>"
      continue
    fi
    if [[ -n ${_CB_A_VAR[$name]} ]]; then
      for val in "${_CB_POS[@]:i}"; do cb::_check_choice "$name" "$val"; done
      _CB_AVAL[$name]="${_CB_POS[*]:i}"
      i=$n variadic=1
      break
    fi
    cb::_check_choice "$name" "${_CB_POS[i]}"
    _CB_AVAL[$name]=${_CB_POS[i]}
    ((i++))
  done
  if ((!variadic && i < n)); then
    val=${_CB_POS[i]}
    if cb::is_child "$_CB_DIR" "$val"; then
      cb::_parse_err "unexpected argument '$val'" "'$val' is a subcommand: put the options after it."
    fi
    cb::_parse_err "unexpected argument '$val'"
  fi
  return 0
}

# Exports FLAG_* and ARG_* for the command. Clears those inherited from a parent call.
cb::export_values() {
  local name v
  unset "${!FLAG_@}" "${!ARG_@}"
  for name in "${_CB_FLAGS[@]}"; do
    v=FLAG_${name^^}
    export "${v//-/_}=${_CB_VAL[$name]}"
  done
  for name in "${_CB_ARGS[@]}"; do
    v=ARG_${name^^}
    export "${v//-/_}=${_CB_AVAL[$name]:-}"
  done
}
