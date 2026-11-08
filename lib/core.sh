# Loads every building block of the core.
# Expected variables (set by main.sh): CB_ROOT, CB_NAME, CB_CONFIG_DIR.

_cb_lib=${BASH_SOURCE[0]%/*}
: "${CB_ROOT:=$(cd -P "$_cb_lib/.." && pwd)}"
: "${CB_NAME:=cmd-builder}"
: "${CB_CONFIG_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/$CB_NAME}"

for _cb_f in util ui config plugins spec help parse complete router; do
  source "$_cb_lib/$_cb_f.sh"
done
unset _cb_f _cb_lib
