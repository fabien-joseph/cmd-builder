# Dependencies of user plugins (decision 0014): the tools declared with "requires" in
# flags.sh, and the package managers that install them. Not loaded by lib/core.sh: sourced
# by "self deps", "self doctor", "self update" and init.sh, after lib/core.sh.
#
# Only the managers listed in the config (package-manager lines) are ever used, and only
# after a confirmation; the framework itself never needs any of these tools.

declare -ga _CB_DEP_TOOLS=()                               # every declared tool, sorted
declare -gA _CB_DEP_REQ=() _CB_DEP_USERS=() _CB_DEP_PKG=() # tool -> 1 if required by one
#                                      command / commands using it / "<pm>/<tool>" -> package

# Managers found on this machine, best suggestion first (one per line).
cb::pm_detect() {
  local darwin=0 pm
  [[ $(uname -s 2>/dev/null) == Darwin ]] && darwin=1
  ((darwin)) && command -v brew >/dev/null 2>&1 && echo brew
  for pm in apt-get dnf pacman zypper apk; do
    command -v "$pm" >/dev/null 2>&1 && printf '%s\n' "${pm%-get}"
  done
  ((!darwin)) && command -v brew >/dev/null 2>&1 && echo brew
  return 0
}

# Asks which manager to use (suggestion: the best detected one) and saves the answer in
# the config. Without a terminal the suggestion is kept. Returns 1 for "none".
cb::pm_ask() {
  local best pm
  local -a found=()
  mapfile -t found < <(cb::pm_detect)
  best=${found[0]:-none}
  pm=$(ui::select "Package manager for the tools your plugins need (detected: ${found[*]:-none})?" \
    -d "$best" "${_CB_PM_ALL[@]}" none) || return 1
  if [[ $pm == none ]]; then
    ui::info "no package manager: add one later with '$CB_NAME self deps managers add <manager>'"
    return 1
  fi
  cb::config_set_package_managers "$pm"
  ui::success "package manager: $pm (change it with '$CB_NAME self deps managers')"
}

# Package of <tool> for <pm>: its own name unless flags.sh says otherwise ("-": none).
cb::pm_package() { printf '%s' "${_CB_DEP_PKG[$1/$2]:-$2}"; }

# First configured manager that packages <tool> (empty if none).
cb::pm_for() {
  local pm
  for pm in "${_CB_PMS[@]}"; do
    [[ $(cb::pm_package "$pm" "$1") != - ]] && printf '%s' "$pm" && return 0
  done
  return 1
}

# Shell commands that install or update packages with <pm>, one per line.
# Package names are validated by "requires", and quoted again here.
cb::pm_commands() { # pm install|update package...
  local pm=$1 action=$2 sudo= p list=
  shift 2
  for p; do list+=" $(printf '%q' "$p")"; done
  ((EUID == 0)) || sudo='sudo '
  case $pm/$action in
    apt/install) printf '%s\n' "${sudo}apt-get update" "${sudo}apt-get install$list" ;;
    apt/update) printf '%s\n' "${sudo}apt-get update" "${sudo}apt-get install --only-upgrade$list" ;;
    dnf/install) printf '%s\n' "${sudo}dnf install$list" ;;
    dnf/update) printf '%s\n' "${sudo}dnf upgrade$list" ;;
    pacman/install) printf '%s\n' "${sudo}pacman -S --needed$list" ;;
    pacman/update) printf '%s\n' "${sudo}pacman -Syu" ;; # Arch: no partial upgrades
    zypper/install) printf '%s\n' "${sudo}zypper install$list" ;;
    zypper/update) printf '%s\n' "${sudo}zypper update$list" ;;
    apk/install) printf '%s\n' "${sudo}apk add$list" ;;
    apk/update) printf '%s\n' "${sudo}apk add --upgrade$list" ;;
    brew/install) printf '%s\n' "brew install$list" ;; # never with sudo
    brew/update) printf '%s\n' "brew upgrade$list" ;;
  esac
}

# Fills _CB_DEP_* from the "requires" of every active command (plugins and extensions).
cb::deps_collect() {
  local name dir d words tool opt pkgs kv display
  _CB_DEP_TOOLS=() _CB_DEP_REQ=() _CB_DEP_USERS=() _CB_DEP_PKG=()
  for name in "${_CB_PLUGIN_NAMES[@]}"; do
    dir=${_CB_PLUGINS[$name]}
    while IFS=$'\t' read -r d words; do
      display="$CB_NAME $name${words:+ $words}"
      while IFS=$'\t' read -r tool opt pkgs; do
        [[ -n $tool ]] || continue
        [[ -n ${_CB_DEP_USERS[$tool]+x} ]] || _CB_DEP_TOOLS+=("$tool")
        _CB_DEP_USERS[$tool]+="${_CB_DEP_USERS[$tool]:+, }$display"
        [[ $opt == 1 ]] || _CB_DEP_REQ[$tool]=1
        for kv in $pkgs; do # "pm=package" words; the first command that says it wins
          [[ -n ${_CB_DEP_PKG[${kv%%=*}/$tool]+x} ]] || _CB_DEP_PKG[${kv%%=*}/$tool]=${kv#*=}
        done
      done < <(
        [[ -n $(cb::executable "$d") ]] || exit 0 # a router never runs: its requires are never checked
        cb::spec_load "$d" >/dev/null 2>&1 || exit 0
        for tool in "${_CB_REQS[@]}"; do
          pkgs=
          for kv in "${!_CB_R_PKG[@]}"; do
            [[ ${kv#*/} == "$tool" ]] && pkgs+=" ${kv%%/*}=${_CB_R_PKG[$kv]}"
          done
          printf '%s\t%s\t%s\n' "$tool" "${_CB_R_OPT[$tool]:-0}" "$pkgs" # no empty field: IFS tabs would merge
        done
      )
    done < <(cb::walk "$dir")
  done
  if ((${#_CB_DEP_TOOLS[@]})); then
    mapfile -t _CB_DEP_TOOLS < <(printf '%s\n' "${_CB_DEP_TOOLS[@]}" | sort)
  fi
}

# True if <tool> is installed.
cb::dep_ok() { type -P "$1" >/dev/null 2>&1; }
