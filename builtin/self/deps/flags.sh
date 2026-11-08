about "List the tools your plugins need, and whether they are installed"
description "Commands of your plugins declare the tools they need with 'requires' in their
flags.sh (official plugins need none). A command whose required tool is missing stops with
a message. Install them with '$CB_NAME self deps install', update them (security fixes)
with '$CB_NAME self deps update', using the package managers of
'$CB_NAME self deps managers'."
example "self deps" "List the tools, their state and the commands that need them"
example "self deps install" "Install the missing ones"
