# Plugin discovery (core/ then plugins/), disables, renames and conflicts.
#
# Rules:
#   - a user plugin (user:x) shadows an official plugin (core:x) with the same name;
#   - "self" is reserved for the root command;
#   - "rename" in the config allows keeping both;
#   - plugins/+x/ extends core:x: its subcommands are added to it (decision 0013).

declare -gA _CB_PLUGINS=()   # exposed name -> directory
declare -gA _CB_PLUGIN_ID=() # exposed name -> id (source:directory)
declare -ga _CB_PLUGIN_NAMES=()
declare -ga _CB_IDS=()        # every plugin found
declare -gA _CB_ID_DIR=() _CB_ID_NAME=() _CB_ID_STATE=()
declare -ga _CB_CONFLICTS=()
declare -gA _CB_OVL=() # official command directory -> directory of its extension

cb::plugins_load() {
  local src base d name id exposed prev
  _CB_PLUGINS=() _CB_PLUGIN_ID=() _CB_PLUGIN_NAMES=() _CB_IDS=()
  _CB_ID_DIR=() _CB_ID_NAME=() _CB_ID_STATE=() _CB_CONFLICTS=() _CB_OVL=()

  for src in core user; do
    [[ $src == core ]] && base=$CB_ROOT/core || base=$CB_ROOT/plugins
    for d in "$base"/*/; do
      d=${d%/}
      name=${d##*/}
      cb::valid_name "$name" && cb::is_command_dir "$d" || continue
      id=$src:$name
      exposed=${_CB_RENAME[$id]:-$name}
      _CB_IDS+=("$id")
      _CB_ID_DIR[$id]=$d
      _CB_ID_NAME[$id]=$exposed

      if [[ -n ${_CB_DISABLED[$id]:-} ]]; then
        _CB_ID_STATE[$id]=disabled
        continue
      fi
      if [[ $exposed == self ]]; then
        _CB_ID_STATE[$id]=reserved
        _CB_CONFLICTS+=("$id: 'self' is reserved for $CB_NAME → add 'rename $id <name>' to the config")
        continue
      fi
      if [[ -n ${_CB_PLUGINS[$exposed]:-} ]]; then
        prev=${_CB_PLUGIN_ID[$exposed]}
        _CB_ID_STATE[$prev]=shadowed:$id
        _CB_CONFLICTS+=("'$exposed': $id shadows $prev → add 'rename $prev <name>' to the config to keep both")
      fi
      _CB_PLUGINS[$exposed]=$d
      _CB_PLUGIN_ID[$exposed]=$id
      _CB_ID_STATE[$id]=active
    done
  done

  cb::_extensions_load

  if ((${#_CB_PLUGINS[@]})); then
    mapfile -t _CB_PLUGIN_NAMES < <(printf '%s\n' "${!_CB_PLUGINS[@]}" | sort)
  fi
}

# Extensions: plugins/+<x>/ adds its subcommands to the official plugin core:<x>, which
# must be active. Ids "user:+<x>", names "+<exposed name of core:x>".
cb::_extensions_load() {
  local d name id core st
  for d in "$CB_ROOT"/plugins/+*/; do
    [[ -d $d ]] || continue
    d=${d%/}
    name=${d##*/+}
    cb::valid_name "$name" || continue
    id=user:+$name core=core:$name
    _CB_IDS+=("$id")
    _CB_ID_DIR[$id]=$d
    _CB_ID_NAME[$id]=+${_CB_ID_NAME[$core]:-$name}
    if [[ -n ${_CB_DISABLED[$id]:-} ]]; then
      _CB_ID_STATE[$id]=disabled
      continue
    fi
    st=${_CB_ID_STATE[$core]:-}
    if [[ -z $st ]]; then
      _CB_ID_STATE[$id]=orphan
      _CB_CONFLICTS+=("$id extends $core, which does not exist: it is inactive (rename plugins/+$name to plugins/$name for a plugin of its own)")
    elif [[ $st != active ]]; then
      _CB_ID_STATE[$id]=inactive:$core
      _CB_CONFLICTS+=("$id extends $core, which is ${st%%:*}: it is inactive too")
    else
      _CB_ID_STATE[$id]=extends:$core
      cb::_overlay "$CB_ROOT/core/$name" "$d" "${_CB_ID_NAME[$core]}"
    fi
  done
}

# Registers <ext> as the extension of the official command directory <dir> (shown as
# <words>), then its "+<sub>" subdirectories as extensions of the official subcommands.
cb::_overlay() { # dir ext words
  local dir=$1 ext=$2 words=$3 x n f
  _CB_OVL[$dir]=$ext
  for f in flags.sh cmd.sh cmd; do
    [[ -e $ext/$f ]] && _CB_CONFLICTS+=("${ext#"$CB_ROOT"/}/$f is ignored: an extension keeps the official '$words' (remove the + of the directory to replace it)")
  done
  for x in "$ext"/*/; do
    [[ -d $x ]] || continue
    x=${x%/}
    n=${x##*/}
    if [[ $n == +* ]]; then
      n=${n#+}
      if cb::valid_name "$n" && cb::is_command_dir "$dir/$n"; then
        cb::_overlay "$dir/$n" "$x" "$words $n"
      else
        _CB_CONFLICTS+=("${x#"$CB_ROOT"/} extends '$words $n', which does not exist: it is ignored")
      fi
    elif cb::valid_name "$n" && cb::is_command_dir "$x" && cb::is_command_dir "$dir/$n"; then
      _CB_CONFLICTS+=("'$words $n': ${x#"$CB_ROOT"/} shadows ${dir#"$CB_ROOT"/}/$n (name it +$n to add to it instead)")
    fi
  done
}

# Directory of a top-level command (plugin or "self").
cb::plugin_dir() {
  if [[ $1 == self ]]; then
    printf '%s' "$CB_ROOT/builtin/self"
  elif [[ -n ${_CB_PLUGINS[$1]:-} ]]; then
    printf '%s' "${_CB_PLUGINS[$1]}"
  else
    return 1
  fi
}
