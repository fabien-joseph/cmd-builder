# Output helpers. Available in every cmd.sh.
#   ui::info / ui::success / ui::warn / ui::error "message"   (on stderr)
#   ui::die "message" [code]                                   (error + exit)
#   ui::title "text"                                            (stdout, bold)
#   ui::confirm "Question?" [y|n]                               (0 = yes)
#   ui::ask "Question" [default]                                (prints the answer)
#   ui::select "Question" [-d default] option...                (prints the chosen option)
# Colours usable on stdout: UI_BOLD UI_DIM UI_RED UI_GREEN UI_YELLOW UI_BLUE UI_CYAN UI_RESET

if [[ -z ${NO_COLOR:-} && -t 1 ]]; then
  UI_BOLD=$'\e[1m' UI_DIM=$'\e[2m' UI_RED=$'\e[31m' UI_GREEN=$'\e[32m'
  UI_YELLOW=$'\e[33m' UI_BLUE=$'\e[34m' UI_CYAN=$'\e[36m' UI_RESET=$'\e[0m'
else
  UI_BOLD= UI_DIM= UI_RED= UI_GREEN= UI_YELLOW= UI_BLUE= UI_CYAN= UI_RESET=
fi
if [[ -z ${NO_COLOR:-} && -t 2 ]]; then
  _UI_RED=$'\e[31m' _UI_GREEN=$'\e[32m' _UI_YELLOW=$'\e[33m' _UI_BLUE=$'\e[34m' _UI_RESET=$'\e[0m'
else
  _UI_RED= _UI_GREEN= _UI_YELLOW= _UI_BLUE= _UI_RESET=
fi

ui::info()    { printf '%s›%s %s\n' "$_UI_BLUE" "$_UI_RESET" "$*" >&2; }
ui::success() { printf '%s✓%s %s\n' "$_UI_GREEN" "$_UI_RESET" "$*" >&2; }
ui::warn()    { printf '%s!%s %s\n' "$_UI_YELLOW" "$_UI_RESET" "$*" >&2; }
ui::error()   { printf '%s✗%s %s\n' "$_UI_RED" "$_UI_RESET" "$*" >&2; }
ui::die()     { ui::error "$1"; exit "${2:-1}"; }
# Bold only if stdout is a terminal now ("ui::title Report > file" writes plain text).
ui::title() {
  if [[ -z ${NO_COLOR:-} && -t 1 ]]; then printf '\e[1m%s\e[0m\n' "$*"; else printf '%s\n' "$*"; fi
}

# Prompts are printed where the answer is read: on stderr normally, but on the terminal
# itself when stderr is redirected ("cmd 2>/dev/null" would otherwise wait on an invisible
# question). With _CB_TTY (tests), always stderr.
_ui_prompt() {
  if [[ -z ${_CB_TTY:-} && ! -t 2 ]] && { : >/dev/tty; } 2>/dev/null; then
    printf "$@" >/dev/tty
  else
    printf "$@" >&2
  fi
}

# Asks for confirmation on the terminal. Without a terminal: always "no".
# Prompts read /dev/tty; _CB_TTY (internal, set by tests/run.sh) overrides it.
ui::confirm() {
  local q=$1 def=${2:-n} hint ans
  [[ $def == y ]] && hint='[Y/n]' || hint='[y/N]'
  _ui_prompt '%s?%s %s %s ' "$_UI_BLUE" "$_UI_RESET" "$q" "$hint"
  if ! { read -r ans <"${_CB_TTY:-/dev/tty}"; } 2>/dev/null; then
    _ui_prompt '\n'
    return 1
  fi
  ans=${ans,,}
  [[ -z $ans ]] && ans=$def
  [[ $ans == y || $ans == yes ]]
}

# Asks a question and prints the answer (or the default value).
ui::ask() {
  local q=$1 def=${2:-} ans
  if [[ -n $def ]]; then
    _ui_prompt '%s?%s %s [%s] ' "$_UI_BLUE" "$_UI_RESET" "$q" "$def"
  else
    _ui_prompt '%s?%s %s ' "$_UI_BLUE" "$_UI_RESET" "$q"
  fi
  { read -r ans <"${_CB_TTY:-/dev/tty}"; } 2>/dev/null || _ui_prompt '\n'
  printf '%s\n' "${ans:-$def}"
}

# Lets the user pick one option with the arrow keys (or j/k, or its number), then Enter.
# Prints the chosen option on stdout. Esc or q cancels (status 1). Without a terminal:
# prints the default (-d) if given, otherwise returns 1. Pure Bash, no dependency.
ui::select() {
  local q=$1 def= i n cur=0 key rest fd ofd=2 draw=0 first=1 found=0 num
  shift
  if [[ ${1:-} == -d ]]; then
    def=${2:-}
    shift 2
  fi
  local -a opts=("$@")
  n=${#opts[@]}
  ((n)) || return 1
  for i in "${!opts[@]}"; do [[ ${opts[i]} == "$def" ]] && cur=$i found=1; done
  if [[ -n $def ]] && ((!found)); then
    ui::error "ui::select: the default '$def' is not one of the options"
    return 1
  fi
  # Drawn where the keys are read: stderr, or the terminal when stderr is redirected.
  if [[ -t 2 ]]; then
    draw=1
  elif [[ -z ${_CB_TTY:-} ]] && { exec {ofd}>/dev/tty; } 2>/dev/null; then
    draw=1
  else
    ofd=2
  fi
  printf '%s?%s %s\n' "$_UI_BLUE" "$_UI_RESET" "$q" >&"$ofd"
  if ! { exec {fd}<"${_CB_TTY:-/dev/tty}"; } 2>/dev/null; then
    ((ofd == 2)) || exec {ofd}>&-
    [[ -n $def ]] && printf '%s\n' "$def"
    [[ -n $def ]]
    return
  fi
  while :; do
    if ((draw)); then
      ((first)) || printf '\e[%dA' "$n" >&"$ofd"
      for i in "${!opts[@]}"; do
        num=; ((n <= 9)) && num="$((i + 1)). "
        if ((i == cur)); then
          printf '\e[2K  %s›%s %s%s\n' "$_UI_BLUE" "$_UI_RESET" "$num" "${opts[i]}" >&"$ofd"
        else
          printf '\e[2K    %s%s\n' "$num" "${opts[i]}" >&"$ofd"
        fi
      done
    elif ((first)); then
      for i in "${!opts[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${opts[i]}" >&"$ofd"; done
    fi
    first=0
    if ! IFS= read -rsn1 key <&"$fd" 2>/dev/null; then
      # No terminal (or end of input): the default, if any.
      exec {fd}<&-; ((ofd == 2)) || exec {ofd}>&-
      [[ -n $def ]] && printf '%s\n' "$def"
      [[ -n $def ]]
      return
    fi
    case $key in
      $'\e')
        rest=
        IFS= read -rsn2 -t 0.1 rest <&"$fd" 2>/dev/null
        case $rest in
          '[A' | OA) cur=$(((cur - 1 + n) % n)) ;;
          '[B' | OB) cur=$(((cur + 1) % n)) ;;
          '') exec {fd}<&-; ((ofd == 2)) || exec {ofd}>&- && return 1 ;;
        esac
        ;;
      k) cur=$(((cur - 1 + n) % n)) ;;
      j) cur=$(((cur + 1) % n)) ;;
      [1-9])
        if ((key <= n)); then
          cur=$((key - 1))
          break
        fi
        ;;
      q) exec {fd}<&-; ((ofd == 2)) || exec {ofd}>&- && return 1 ;;
      '') break ;;
    esac
  done
  exec {fd}<&-; ((ofd == 2)) || exec {ofd}>&-
  printf '%s\n' "${opts[cur]}"
}
