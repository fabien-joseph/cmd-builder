source "$CB_ROOT/lib/core.sh"
cb::config_load
cb::plugins_load

tpl=$CB_ROOT/templates/ai-guide.md
ref=$CB_ROOT/docs/plugin-authoring.md
[[ -f $tpl ]] || ui::die "template not found: $tpl"

# Replaces every occurrence of $2 by $3 in $1, result in REPLY (no pattern, no special "&").
sub() {
  local s=$1 out=
  while [[ $s == *"$2"* ]]; do
    out+=${s%%"$2"*}$3
    s=${s#*"$2"}
  done
  REPLY=$out$s
}

# The reference is the part of docs/plugin-authoring.md between the guide markers.
reference() {
  local line in=0 found=0
  [[ -f $ref ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      '<!-- guide:begin -->') in=1 ;;
      '<!-- guide:end -->') ((in)) && found=1 in=0 ;;
      *) ((in)) && printf '%s\n' "$line" ;;
    esac
  done <"$ref"
  ((found))
}

commands() {
  local id dir name d sub kind about
  if ((!FLAG_COMMANDS)); then
    echo "Not shared by the user. Ask them whether the command (or its plugin) already exists."
    return
  fi
  if ((${#_CB_IDS[@]} == 0)); then
    echo "None yet: every name is free (except \`self\`)."
    return
  fi
  for id in "${_CB_IDS[@]}"; do
    dir=${_CB_ID_DIR[$id]} name=${_CB_ID_NAME[$id]}
    printf '### Plugin `%s` (id `%s`, %s)\n\n' "$name" "$id" "${_CB_ID_STATE[$id]}"
    while IFS= read -r d; do
      sub=${d#"$dir"}
      kind=command
      [[ -z $(cb::executable "$d") ]] && kind=group
      about=$(cb::about_of "$d")
      printf -- '- `%s %s%s` (%s, `%s/`)%s\n' "$CB_NAME" "$name" "${sub//\// }" "$kind" \
        "${d#"$CB_ROOT"/}" "${about:+: $about}"
    done < <(cb::walk "$dir")
    echo
  done
}

self_new_help() (
  UI_BOLD= UI_DIM= UI_CYAN= UI_RESET=
  cb::spec_load "$CB_ROOT/builtin/self/new"
  cb::help "$CB_ROOT/builtin/self/new" "$CB_NAME self new"
)

# Kernel name and release; WSL kernels are named "...-microsoft-standard-WSL2".
system=$(uname -sr 2>/dev/null) || system=unknown
[[ $system == *[Mm]icrosoft* ]] && system+=" (WSL: Linux under Windows)"
[[ $(uname -s 2>/dev/null) == Darwin ]] && system+=" (macOS)"

refs=$(reference) ||ui::die "cannot read the reference: $ref (with its guide:begin/end markers)"
list=$(commands)
help=$(self_new_help)

guide() {
  local line
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in
      __CB_REFERENCE__) printf '%s\n' "$refs" ;;
      __CB_COMMANDS__) printf '%s\n' "$list" ;;
      __CB_SELF_NEW_HELP__) printf '%s\n' "$help" ;;
      *)
        sub "$line" __CB_NAME__ "$CB_NAME"
        sub "$REPLY" __CB_ROOT__ "$CB_ROOT"
        sub "$REPLY" __CB_BASH__ "$BASH_VERSION"
        sub "$REPLY" __CB_SYSTEM__ "$system"
        printf '%s\n' "$REPLY"
        ;;
    esac
  done <"$tpl"
  (($# == 0)) && return 0
  printf "\n## The user's request\n\nAnswer this request, following this guide:\n\n"
  while IFS= read -r line || [[ -n $line ]]; do
    printf '> %s\n' "$line"
  done <<<"$*"
}

if [[ -z $FLAG_OUTPUT ]]; then
  guide "$@"
  exit 0
fi

if [[ -e $FLAG_OUTPUT ]]; then
  ui::confirm "$FLAG_OUTPUT already exists. Overwrite it?" || ui::die "cancelled: $FLAG_OUTPUT left untouched"
fi
content=$(guide "$@") || exit 1
printf '%s\n' "$content" >"$FLAG_OUTPUT" || ui::die "cannot write $FLAG_OUTPUT"
ui::success "Guide written to $FLAG_OUTPUT"
ui::info "Attach it to a conversation with an AI assistant, then describe the command you want."
