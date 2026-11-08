source "$CB_ROOT/lib/core.sh"

base=$CB_ROOT/plugins
[[ $FLAG_CORE == 1 ]] && base=$CB_ROOT/core

for p in "$@"; do
  cb::valid_name "$p" || ui::die "invalid name '$p' (letters, digits, - and _; not first)"
done
[[ $1 == self ]] && ui::die "'self' is reserved for $CB_NAME"

# Directory names on disk, one per word. Below an official plugin that the user has not
# replaced, the words go to its extension plugins/+<plugin>/ (decision 0013): "+<name>"
# (no files of its own) for every official group on the way.
segs=("$@") plus=()
official=
if [[ $FLAG_CORE != 1 ]] && ! cb::is_command_dir "$base/$1" && cb::is_command_dir "$CB_ROOT/core/$1"; then
  (($# > 1)) || ui::die "'$CB_NAME $1' is an official plugin: add a command to it ($CB_NAME self new $1 <name>), or choose another name"
  segs[0]=+$1 plus[0]=1 official=$CB_ROOT/core/$1
  udir=$base/+$1
  for ((i = 1; i < $#; i++)); do
    name=${segs[i]}
    [[ -n $official ]] || break
    if cb::is_command_dir "$udir/$name"; then
      official= # a user command of its own (it shadows the official one): below, plain names
    elif cb::is_command_dir "$official/$name"; then
      if ((i == $# - 1)); then
        ui::die "'$CB_NAME $*' is an official command: choose another name, or a subcommand of it"
      fi
      segs[i]=+$name plus[i]=1 official=$official/$name
    else
      official=
    fi
    udir=$udir/${segs[i]}
  done
  extends=$1
fi

# Refuse before writing anything: a refused run must leave existing commands untouched.
target=$base/$(IFS=/; printf '%s' "${segs[*]}")
exe=$(cb::executable "$target")
[[ -n $exe ]] && ui::die "'$CB_NAME $*' already has an executable: ${exe#"$CB_ROOT"/}"

plugin_new=0
[[ -d $base/${segs[0]} ]] || plugin_new=1
created=()
dir=$base
mkdir -p "$base"

i=0
for name in "${segs[@]}"; do
  dir=$dir/$name
  if [[ ! -d $dir ]]; then
    mkdir "$dir"
    created+=("$dir/")
  fi
  # An extension directory has no files of its own; an existing command (flags.sh,
  # cmd.sh or cmd) is left as is.
  ((${plus[i]:-0})) && { ((i++)); continue; }
  ((i++))
  cb::is_command_dir "$dir" && continue
  if ((i == $#)); then
    about=${FLAG_ABOUT:-TODO: describe this command}
    {
      printf 'about "%s"\n' "$(cb::dq "$about")"
      cat <<'TPL'

# Declare options and arguments here; --help, parsing and completion are generated.
#
# flag verbose -v bool   "Verbose mode"
# flag output  -o string "Output file" --default "-"
# flag level      int    "Level" --choices "1 2 3"
# arg  target            "Target to process" --optional
# arg  branch            "Branch" --choices-from "git branch --format='%(refname:short)'"
#
# example "my command -v" "What the example does"
TPL
    } >"$dir/flags.sh"
  else
    printf 'about "%s"\n' "$(cb::dq "TODO: describe '$name'")" >"$dir/flags.sh"
  fi
  created+=("$dir/flags.sh")
done

{
  printf '# %s %s\n' "$CB_NAME" "$*"
  cat <<'TPL'
#
# Options: FLAG_<NAME> (bool = 0/1) · Arguments: ARG_<NAME> and "$@"
# Variables: CB_NAME, CB_COMMAND, CB_COMMAND_DIR, CB_PLUGIN_ROOT, CB_CONFIG_DIR
# Helpers:   ui::info ui::success ui::warn ui::error ui::die ui::confirm ui::ask ui::title

ui::info "Hello from '$CB_COMMAND'!"
TPL
} >"$dir/cmd.sh"
created+=("$dir/cmd.sh")

if [[ $FLAG_GIT == 1 ]]; then
  if [[ $FLAG_CORE == 1 ]]; then
    ui::warn "--git ignored: official plugins live in the main repository"
  elif ((plugin_new)); then
    git -C "$base/${segs[0]}" init -q && created+=("$base/${segs[0]}/.git/")
  else
    ui::warn "--git ignored: plugin '$1' already existed"
  fi
fi

ui::success "Command '$CB_NAME $*' created${extends:+ (added to the official plugin '$extends', in plugins/+$extends/)}"
for f in "${created[@]}"; do printf '  + %s\n' "${f#"$CB_ROOT"/}"; done
echo
ui::info "Try: $CB_NAME $* --help"
