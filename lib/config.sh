# Local configuration: $CB_CONFIG_DIR/config
#
#   disable <source>:<plugin>            disables a plugin
#   rename  <source>:<plugin> <name>     exposes the plugin under another name
#   package-manager <manager>            installs plugin dependencies (repeatable, in order
#                                        of preference; apt dnf pacman zypper apk brew)
#
# <source> is "core" (official plugins, core/) or "user" (plugins/).

declare -gA _CB_DISABLED=() _CB_RENAME=()
declare -ga _CB_CONFIG_ERRORS=()
declare -ga _CB_PMS=()                                     # configured package managers
declare -ga _CB_PM_ALL=(apt dnf pacman zypper apk brew) # supported ones (decision 0014)

cb::valid_id() { [[ $1 =~ ^(core|user):[a-zA-Z0-9][a-zA-Z0-9_-]*$ || $1 =~ ^user:\+[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; }

cb::config_load() {
  local f=$CB_CONFIG_DIR/config line n=0 kw a b extra
  _CB_DISABLED=() _CB_RENAME=() _CB_CONFIG_ERRORS=() _CB_PMS=()
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
        if [[ $a == user:+* ]]; then
          _CB_CONFIG_ERRORS+=("line $n: '$a' is an extension, it takes the name of the plugin it extends: it cannot be renamed")
        elif cb::valid_id "$a" && cb::valid_name "$b" && [[ -z $extra ]]; then
          _CB_RENAME[$a]=$b
        else
          _CB_CONFIG_ERRORS+=("line $n: expected 'rename <core|user>:<plugin> <new-name>'")
        fi
        ;;
      package-manager)
        if cb::in_list "$a" "${_CB_PM_ALL[@]}" && [[ -z $b ]]; then
          cb::in_list "$a" "${_CB_PMS[@]}" || _CB_PMS+=("$a")
        else
          _CB_CONFIG_ERRORS+=("line $n: expected 'package-manager <$(IFS='|'; printf '%s' "${_CB_PM_ALL[*]}")>'")
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
#
# Package managers used to install the tools your plugins need, in order of preference
# (see "$CB_NAME self deps"):
#   package-manager apt
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

# Replaces the package-manager lines of the config file by the given managers, in order.
cb::config_set_package_managers() {
  local f=$CB_CONFIG_DIR/config line kw pm
  local -a out=()
  cb::config_ensure
  while IFS= read -r line || [[ -n $line ]]; do
    kw=
    read -r kw _ <<<"${line%%#*}"
    [[ $kw == package-manager ]] && continue
    out+=("$line")
  done <"$f"
  for pm; do out+=("package-manager $pm"); done
  f=$(cb::realpath "$f") || f=$CB_CONFIG_DIR/config
  printf '%s\n' "${out[@]}" >"$f.tmp" && mv "$f.tmp" "$f"
  _CB_PMS=("$@")
}
