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

cb::valid_id() { [[ $1 =~ $_CB_RE_ID ]]; }

cb::config_load() {
  local f=$CB_CONFIG_DIR/config line n=0 kw a b extra
  _CB_DISABLED=() _CB_RENAME=() _CB_CONFIG_ERRORS=() _CB_PMS=()
  [[ -f $f ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    ((n++))
    line=${line%$'\r'} # a config edited on Windows (WSL): CRLF line endings
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
  [[ -e $f && ! -f $f ]] && ui::die "$f exists but is not a regular file: fix or remove it"
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

# Rewrites the config file with the given lines, atomically (temp file + mv). A symlinked
# config (dotfiles) gets its target rewritten, the link stays. The mode is kept (a chmod 600
# config stays private): the temp file is a copy (cp -p) whose content is then replaced.
cb::_config_rewrite() { # line...
  local f=$CB_CONFIG_DIR/config
  f=$(cb::realpath "$f") || f=$CB_CONFIG_DIR/config
  [[ -f $f ]] || ui::die "$f is not a regular file: fix or remove it, then run the command again"
  cp -p -- "$f" "$f.tmp" 2>/dev/null && printf '%s\n' "$@" >"$f.tmp" && mv -f -- "$f.tmp" "$f" ||
    ui::die "cannot rewrite $f (permissions? disk full?): nothing was changed"
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
  cb::_config_rewrite "${out[@]}"
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
  cb::_config_rewrite "${out[@]}"
  _CB_PMS=("$@")
}
