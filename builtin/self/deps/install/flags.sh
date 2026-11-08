about "Install the missing tools your plugins need (one confirmation)"
description "Shows the package manager commands (with sudo when needed), asks once, then runs
them. Optional tools are installed too with --all."
flag all -a bool "Also install the missing optional tools"
example "self deps install" "Install the missing required tools"
