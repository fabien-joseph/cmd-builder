# Completion engine, shared by bash and zsh.
#
#   <name> __complete -- <word1> <word2> ... <current word>
#
# Prints one candidate per line: "value<TAB>description".
# No output = the shell adapter falls back to file completion.

cb::_cand() {
  [[ $2 == "$1"* ]] && printf '%s\t%s\n' "$2" "$3"
  return 0
}

# Offers the choices (static or dynamic) of a flag (F) or an argument (A).
cb::_choice_cands() {
  local cur=$1 v d
  while IFS=$'\t' read -r v d; do
    [[ -n $v ]] && cb::_cand "$cur" "$v" "$d"
  done < <(cb::choices_of "$2" "$3")
}

# True if the option word $1 expects a value in the next word.
# Sets _CB_TV_FLAG = name of the flag concerned.
cb::_takes_value() {
  local w=$1 rest c name
  _CB_TV_FLAG=
  case $w in
    --*=*) return 1 ;;
    --*)
      name=${w#--}
      [[ -n ${_CB_F_TYPE[$name]+x} && ${_CB_F_TYPE[$name]} != bool ]] || return 1
      _CB_TV_FLAG=$name
      return 0
      ;;
    -*)
      rest=${w#-}
      while [[ -n $rest ]]; do
        c=${rest:0:1} rest=${rest:1}
        name=${_CB_F_BYSHORT[$c]:-}
        [[ -z $name ]] && return 1
        if [[ ${_CB_F_TYPE[$name]} != bool ]]; then
          [[ -n $rest ]] && return 1
          _CB_TV_FLAG=$name
          return 0
        fi
      done
      return 1
      ;;
  esac
  return 1
}

cb::complete() {
  local -a words=("$@")
  (($#)) || words=('')
  local n=$((${#words[@]} - 1))
  local cur=${words[n]} dir name i start w pos=0 skip=0 endopts=0 c

  # First level: plugins + self.
  if ((n == 0)); then
    if [[ $cur == -* ]]; then
      cb::_cand "$cur" --help "Show help"
      return 0
    fi
    for name in "${_CB_PLUGIN_NAMES[@]}"; do
      cb::_cand "$cur" "$name" "$(cb::about_of "${_CB_PLUGINS[$name]}")"
    done
    cb::_cand "$cur" self "$(cb::about_of "$CB_ROOT/builtin/self")"
    return 0
  fi

  dir=$(cb::plugin_dir "${words[0]}") || return 0
  # Routing over the complete words only (not the one being typed).
  cb::descend "$dir" "${words[@]:1:n-1}"
  start=$((_CB_ROUTE_N + 1))
  cb::_complete_at "$_CB_ROUTE_DIR" "$(cb::plugin_root_of "$_CB_ROUTE_DIR" "$dir")" "$start" "${words[@]}"
}

# Second half of cb::complete, for the command directory <dir> reached by the words: the
# spec is loaded before any local exists, so flags.sh cannot overwrite them (see cb::run).
cb::_complete_at() { # dir plugin-root start word...
  export CB_COMMAND_DIR=$1 CB_PLUGIN_ROOT=$2
  cb::spec_load "$1" >/dev/null 2>&1
  local dir=$1 start=$3 name i w pos=0 skip=0 endopts=0
  shift 3
  local -a words=("$@")
  local n=$((${#words[@]} - 1))
  local cur=${words[n]}

  # Where are we among the options and arguments already typed?
  for ((i = start; i < n; i++)); do
    w=${words[i]}
    if ((skip)); then
      skip=0
      continue
    fi
    if ((!endopts)) && [[ $w == -- ]]; then
      endopts=1
      continue
    fi
    # "-5" is a positional (negative number) unless -5 is a declared short option,
    # same rule as the parser.
    if ((!endopts)) && [[ $w =~ ^-[0-9] && -z ${_CB_F_BYSHORT[${w:1:1}]:-} ]]; then
      ((pos++))
      continue
    fi
    if ((!endopts)) && [[ $w == -?* ]]; then
      cb::_takes_value "$w" && skip=1
      continue
    fi
    ((pos++))
  done

  # Value of an option (e.g. --format <TAB>): its choices, otherwise files.
  if ((skip)); then
    cb::_choice_cands "$cur" F "$_CB_TV_FLAG"
    return 0
  fi

  # Attached value (e.g. --format=<TAB>): the flag's choices, prefixed with "--format=".
  if ((!endopts)) && [[ $cur == --*=* ]]; then
    name=${cur%%=*}
    name=${name#--}
    if [[ -n ${_CB_F_TYPE[$name]+x} && ${_CB_F_TYPE[$name]} != bool ]]; then
      while IFS= read -r w; do
        printf -- '--%s=%s\n' "$name" "$w"
      done < <(cb::_choice_cands "${cur#*=}" F "$name")
    fi
    return 0
  fi

  if ((!endopts)) && [[ $cur == -* ]]; then
    if [[ -n $(cb::executable "$dir") ]]; then
      for name in "${_CB_FLAGS[@]}"; do cb::_cand "$cur" "--$name" "${_CB_F_DESC[$name]}"; done
    fi
    cb::_cand "$cur" --help "Show help"
    return 0
  fi

  if ((start == n)); then
    while IFS= read -r name; do
      [[ -n $name ]] && cb::_cand "$cur" "$name" "$(cb::about_of "$(cb::child_dir "$dir" "$name")")"
    done < <(cb::children "$dir")
  fi

  # Choices of the current positional argument.
  if [[ -n $(cb::executable "$dir") ]] && ((${#_CB_ARGS[@]})); then
    if ((pos < ${#_CB_ARGS[@]})); then
      name=${_CB_ARGS[pos]}
    else
      name=${_CB_ARGS[-1]}
      [[ -n ${_CB_A_VAR[$name]} ]] || name=
    fi
    if [[ -n $name ]]; then
      cb::_choice_cands "$cur" A "$name"
    fi
  fi
  return 0
}

# Completion script for a shell (bash|zsh), adapted to the command name.
cb::completion_script() {
  local f=$CB_ROOT/templates/completion.$1 tpl func
  [[ -f $f ]] || return 1
  func=_cb_complete_${CB_NAME//[^a-zA-Z0-9_]/_}
  tpl=$(<"$f")
  tpl=${tpl//__CB_FUNC__/$func}
  tpl=${tpl//__CB_NAME__/$CB_NAME}
  printf '%s\n' "$tpl"
}

# (Re)generates $CB_CONFIG_DIR/completion.{bash,zsh}.
cb::completion_install() {
  local s
  mkdir -p "$CB_CONFIG_DIR"
  for s in bash zsh; do
    cb::completion_script "$s" >"$CB_CONFIG_DIR/completion.$s"
  done
}
