# Local configuration: $CB_CONFIG_DIR/config
#
#   disable <source>:<plugin>            disables a plugin
#   rename  <source>:<plugin> <name>     exposes the plugin under another name
#
# <source> is "core" (official plugins, core/) or "user" (plugins/).

declare -gA _CB_DISABLED=() _CB_RENAME=()
declare -ga _CB_CONFIG_ERRORS=()

cb::valid_id() { [[ $1 =~ ^(core|user):[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; }

cb::config_load() {
  local f=$CB_CONFIG_DIR/config line n=0 kw a b extra
  _CB_DISABLED=() _CB_RENAME=() _CB_CONFIG_ERRORS=()
  [[ -f $f ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    ((n++))
    kw= a= b= extra=
    read -r kw a b extra <<<"${line%%#*}"
    [[ -z $kw ]] && continue
    case $kw in
      disable)
        if cb::valid_id "$a" && [[ -z $b ]]; then
          _CB_DISABLED[$a]=1
        else
          _CB_CONFIG_ERRORS+=("line $n: expected 'disable <core|user>:<plugin>'")
        fi
        ;;
      rename)
        if cb::valid_id "$a" && cb::valid_name "$b" && [[ -z $extra ]]; then
          _CB_RENAME[$a]=$b
        else
          _CB_CONFIG_ERRORS+=("line $n: expected 'rename <core|user>:<plugin> <new-name>'")
        fi
        ;;
      *) _CB_CONFIG_ERRORS+=("line $n: unknown directive '$kw'") ;;
    esac
  done <"$f"
}

# Creates the config directory and file if they do not exist.
cb::config_ensure() {
  local f=$CB_CONFIG_DIR/config
  mkdir -p "$CB_CONFIG_DIR"
  [[ -f $f ]] && return 0
  cat >"$f" <<EOF
# Configuration of "$CB_NAME" (cmd-builder)
#
# Disable a plugin:
#   disable core:system
#
# Rename a plugin (e.g. to keep both in case of a name conflict):
#   rename core:docker core-docker
#
# Sources: "core" = official plugins (core/), "user" = your plugins (plugins/).
EOF
}

# Enables (0) or disables (1) a plugin in the config file.
cb::config_set_disabled() {
  local id=$1 on=$2 f=$CB_CONFIG_DIR/config line kw a rest
  local -a out=()
  cb::config_ensure
  while IFS= read -r line || [[ -n $line ]]; do
    kw= a= rest=
    read -r kw a rest <<<"${line%%#*}"
    [[ $kw == disable && $a == "$id" ]] && continue
    out+=("$line")
  done <"$f"
  ((on)) && out+=("disable $id")
  # If the config is a symlink (dotfiles), rewrite its target instead of replacing the link.
  f=$(cb::realpath "$f") || f=$CB_CONFIG_DIR/config
  printf '%s\n' "${out[@]}" >"$f.tmp" && mv "$f.tmp" "$f"
}
