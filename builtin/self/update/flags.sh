about "Update $CB_NAME and the plugins (confirmation for each repository)"
description "Fetches the news of the main repository (core + official plugins) and of every
plugin in plugins/ that has its own git repository, shows the new commits, then asks for
confirmation before each update (git pull --ff-only)."
flag check -c bool "Only show the available updates, install nothing (exit code 10 if there are some)"
example "self update" "Update, with confirmation"
example "self update --check" "Only check whether there is something new"
