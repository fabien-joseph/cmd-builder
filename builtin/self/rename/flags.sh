about "Rename the root command '$CB_NAME', keeping its configuration"
description "Moves ~/.local/bin/$CB_NAME, ~/.config/$CB_NAME/ and the '$CB_NAME' blocks of
~/.bashrc / ~/.zshrc to the new name, after one confirmation. If it is interrupted, run the
same command again to finish. Scripts and aliases calling '$CB_NAME' must then be updated,
unless --keep-old keeps both names (they share the configuration)."
arg name "New name of the root command"
flag keep-old bool "Keep '$CB_NAME' working too, sharing the configuration with the new name"
example "self rename xx" "Rename '$CB_NAME' to 'xx'"
example "self rename xx --keep-old" "Add the name 'xx', keep '$CB_NAME'"
