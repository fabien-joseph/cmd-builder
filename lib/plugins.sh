# Plugin discovery (core/ then plugins/), disables, renames and conflicts.
#
# Rules:
#   - a user plugin (user:x) shadows an official plugin (core:x) with the same name;
#   - "self" is reserved for the root command;
#   - "rename" in the config allows keeping both.

declare -gA _CB_PLUGINS=()   # exposed name -> directory
declare -gA _CB_PLUGIN_ID=() # exposed name -> id (source:directory)
declare -ga _CB_PLUGIN_NAMES=()
declare -ga _CB_IDS=()        # every plugin found
declare -gA _CB_ID_DIR=() _CB_ID_NAME=() _CB_ID_STATE=()
declare -ga _CB_CONFLICTS=()

cb::plugins_load() {
  local src base d name id exposed prev
  _CB_PLUGINS=() _CB_PLUGIN_ID=() _CB_PLUGIN_NAMES=() _CB_IDS=()
  _CB_ID_DIR=() _CB_ID_NAME=() _CB_ID_STATE=() _CB_CONFLICTS=()

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

  if ((${#_CB_PLUGINS[@]})); then
    mapfile -t _CB_PLUGIN_NAMES < <(printf '%s\n' "${!_CB_PLUGINS[@]}" | sort)
  fi
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
