about "Create a new command (flags.sh + cmd.sh skeleton)"
description "Creates the missing directories of the given path. In plugins/ (your plugins) by
default, or in core/ with --core (official plugins). Below an official plugin, it creates
an extension instead (plugins/+<plugin>/...): the official commands stay."
arg  path "Path of the command, e.g.: backup db restore" --variadic
flag about -a string "Summary of the command (shown in --help)"
flag core      bool   "Create in core/ (official plugins) instead of plugins/"
flag git  -g   bool   "Initialise a git repository for a new plugin"
example "self new backup" "New executable plugin 'backup'"
example "self new backup db restore -a \"Restore a database\"" "Nested subcommand"
example "self new system disk" "Add 'system disk' to the official plugin 'system'"
