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
ui::title()   { printf '%s%s%s\n' "$UI_BOLD" "$*" "$UI_RESET"; }

# Asks for confirmation on the terminal. Without a terminal: always "no".
# Prompts read /dev/tty; _CB_TTY (internal, set by tests/run.sh) overrides it.
ui::confirm() {
  local q=$1 def=${2:-n} hint ans
  [[ $def == y ]] && hint='[Y/n]' || hint='[y/N]'
  printf '%s?%s %s %s ' "$_UI_BLUE" "$_UI_RESET" "$q" "$hint" >&2
  if ! { read -r ans <"${_CB_TTY:-/dev/tty}"; } 2>/dev/null; then
    printf '\n' >&2
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
    printf '%s?%s %s [%s] ' "$_UI_BLUE" "$_UI_RESET" "$q" "$def" >&2
  else
    printf '%s?%s %s ' "$_UI_BLUE" "$_UI_RESET" "$q" >&2
  fi
  { read -r ans <"${_CB_TTY:-/dev/tty}"; } 2>/dev/null || printf '\n' >&2
  printf '%s\n' "${ans:-$def}"
}

# Lets the user pick one option with the arrow keys (or j/k, or its number), then Enter.
# Prints the chosen option on stdout. Esc or q cancels (status 1). Without a terminal:
# prints the default (-d) if given, otherwise returns 1. Pure Bash, no dependency.
ui::select() {
  local q=$1 def= i n cur=0 key rest fd draw=0 first=1
  shift
  if [[ ${1:-} == -d ]]; then
    def=${2:-}
    shift 2
  fi
  local -a opts=("$@")
  n=${#opts[@]}
  ((n)) || return 1
  for i in "${!opts[@]}"; do [[ ${opts[i]} == "$def" ]] && cur=$i; done
  [[ -t 2 ]] && draw=1
  printf '%s?%s %s\n' "$_UI_BLUE" "$_UI_RESET" "$q" >&2
  if ! { exec {fd}<"${_CB_TTY:-/dev/tty}"; } 2>/dev/null; then
    [[ -n $def ]] && printf '%s\n' "$def"
    [[ -n $def ]]
    return
  fi
  while :; do
    if ((draw)); then
      ((first)) || printf '\e[%dA' "$n" >&2
      for i in "${!opts[@]}"; do
        if ((i == cur)); then
          printf '\e[2K  %s›%s %s\n' "$_UI_BLUE" "$_UI_RESET" "${opts[i]}" >&2
        else
          printf '\e[2K    %s\n' "${opts[i]}" >&2
        fi
      done
    elif ((first)); then
      for i in "${!opts[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${opts[i]}" >&2; done
    fi
    first=0
    if ! IFS= read -rsn1 key <&"$fd" 2>/dev/null; then
      # No terminal (or end of input): the default, if any.
      exec {fd}<&-
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
          '') exec {fd}<&- && return 1 ;;
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
      q) exec {fd}<&- && return 1 ;;
      '') break ;;
    esac
  done
  exec {fd}<&-
  printf '%s\n' "${opts[cur]}"
}
