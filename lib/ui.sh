# Output helpers. Available in every cmd.sh.
#   ui::info / ui::success / ui::warn / ui::error "message"   (on stderr)
#   ui::die "message" [code]                                   (error + exit)
#   ui::title "text"                                            (stdout, bold)
#   ui::confirm "Question?" [y|n]                               (0 = yes)
#   ui::ask "Question" [default]                                (prints the answer)
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
ui::success() { printf '%s✔%s %s\n' "$_UI_GREEN" "$_UI_RESET" "$*" >&2; }
ui::warn()    { printf '%s⚠%s %s\n' "$_UI_YELLOW" "$_UI_RESET" "$*" >&2; }
ui::error()   { printf '%s✖%s %s\n' "$_UI_RED" "$_UI_RESET" "$*" >&2; }
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
