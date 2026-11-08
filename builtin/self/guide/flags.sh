about "Print a guide that lets an AI assistant help you write commands"
description "Prints a self-contained Markdown document for an AI chat (ChatGPT, Claude,
Gemini...) without access to this machine: how to answer, your setup, your existing
commands and the full reference. Give it to the AI with your request, for example
\"I want a command '$CB_NAME test hello' that prints hello\": it answers with the commands
to paste, step by step."
flag output -o string "Write the guide to this file instead of stdout"
flag commands bool "Include the list of your commands" --default 1
example "self guide -o ~/$CB_NAME-guide.md" "Write the guide to a file, to attach to the conversation"
example "self guide --no-commands" "Do not share the list of your commands"
