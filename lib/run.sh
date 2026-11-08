# Runs a cmd.sh in a clean process, with the ui:: helpers loaded.
# Internal usage: bash run.sh <cmd.sh> [arguments...]

source "$CB_ROOT/lib/ui.sh"
_cb_cmd=$1
shift
# shellcheck disable=SC1090
source "$_cb_cmd"
