# cmd-builder

A manager and generator of Linux commands in **pure Bash**. Your commands, on all your
machines, under the name of your choice, with `--help`, option parsing and completion
generated automatically.

```
$ mu system info -s
my-laptop · Linux 6.18 · up 50 min
```

## Installation

Requirements: **Bash ≥ 4.2** (on macOS: `brew install bash`) and git.

```bash
git clone git@github.com:fabien-joseph/cmd-builder.git
cd cmd-builder
./init.sh mu        # "mu" = the name of your root command, pick whatever you like
```

`init.sh` creates `~/.local/bin/mu` (a symlink to `main.sh`, no sudo), the config
`~/.config/mu/config`, and offers to enable completion in `~/.bashrc` / `~/.zshrc`.
Running it again is safe. The current terminal read its rc file before the install, so open a
new terminal or run the `source ~/.bashrc` (or `~/.zshrc`) line it prints to get completion.

### Uninstall

```bash
./init.sh --uninstall mu
```

Removes the `~/.local/bin/mu` link (only if it points to this cmd-builder), the block added
to `~/.bashrc` / `~/.zshrc`, the completion scripts and, after confirmation, the config.
Each step is independent and checks whether it is already done: if the uninstall is
interrupted halfway, run it again and it finishes the job. The cmd-builder directory and your
plugins are left untouched.
If the `>>>` marker of the rc block is there but its `<<<` end marker is not (edited by
hand), the rc file is left untouched with a warning and the uninstall exits with code 1:
remove the block by hand. `./init.sh` without a name only prints the usage.

### Rename the root command

```bash
mu self rename xx              # "mu" becomes "xx"
mu self rename xx --keep-old   # "xx" is added, "mu" keeps working
```

Moves the `~/.local/bin/mu` link, `~/.config/mu/` (your config is kept, the completion
scripts are regenerated for the new name) and the `mu` blocks of `~/.bashrc` / `~/.zshrc`
(replaced in place). It shows the plan and asks one confirmation first. If it is
interrupted, run the same command again and it finishes the job. It refuses, without
changing anything, if `~/.local/bin/xx` is not one of its links or if `~/.config/xx/config`
already exists with a different content (uninstall `xx` first, or merge the files by hand).
Scripts and aliases that call `mu` must then use `xx`, unless `--keep-old`: both names then
work and share one config (`~/.config/mu/config` becomes a link to `~/.config/xx/config`;
`./init.sh --uninstall mu` later removes only the link).

## Layout

```
cmd-builder/
├── init.sh            install / uninstall
├── main.sh            entry point
├── lib/               the core: routing, parsing, help, completion, ui:: helpers
├── builtin/self/      the "mu self …" commands
├── core/              official plugins (can be disabled)
└── plugins/           YOUR plugins: ignored by git, one git repository per plugin if you like
```

## One command = one directory

```
plugins/backup/            → mu backup
├── flags.sh               options, arguments and help of "mu backup"
├── cmd.sh                 optional: without it, "mu backup" only routes
└── db/                    → mu backup db
    ├── flags.sh
    ├── cmd.sh
    └── restore/           → mu backup db restore   (no depth limit)
```

- A directory is a command if it contains `flags.sh`, `cmd.sh` or `cmd`.
- Directories starting with `_` or `.` are ignored (`_lib/`, `.git/`…).
- `cmd.sh` is run with bash, with the `ui::` helpers loaded.
- `cmd` is any executable (Python, binary…), and receives the same variables.
- Words matching a subcommand are consumed as long as there are some; the rest goes to the
  command reached. If a subcommand and an argument have the same name, the subcommand wins.

To create the skeleton:

```bash
mu self new backup db restore -a "Restore a database"
mu self new my-plugin --git      # new plugin with its own git repository
```

With an AI chat (ChatGPT, Claude, Gemini…) that cannot see your machine, generate a guide and
attach it to the conversation with your request (for example *"I want a command `mu test
hello` that prints hello"*): it answers with the commands to paste, step by step.

```bash
mu self guide -o ~/mu-guide.md   # your setup, your commands and the full reference
mu self guide --no-commands      # without the list of your commands
```

### `flags.sh`

```bash
about       "Restore a database"                   # summary (--help, lists, completion)
description "Longer text shown in --help"

#    name    short type    description            options
flag verbose -v    bool    "Verbose mode"
flag output  -o    string  "Output file"          --default "-"
flag level         int     "Level"                --choices "1 2 3" --default 1
flag token         string  "Access token"         --required

#   name    description                options
arg db      "Database to restore"      --choices "prod staging"
arg files   "Files to import"          --optional --variadic

example "backup db restore prod dump.sql" "Restore prod"
```

Everything is optional (even `flags.sh` itself), except the fields of the lines you write:
`flag` needs a name, a type and a description, `arg` a name and a description, and their
options come after the description. An `arg` is required unless `--optional`.
See [docs/plugin-authoring.md](docs/plugin-authoring.md) for the complete reference.

| `flag` option | Effect |
|---|---|
| `bool` / `string` / `int` | type (an `int` is validated) |
| `--default v` | default value (`0` or `1` for a bool) |
| `--required` | mandatory option |
| `--choices "a b"` | allowed values, offered by completion |
| `--choices-from "cmd"` | values computed on the fly (see below) |
| `--strict` | with `--choices-from`: rejects values outside the list |

| `arg` option | Effect |
|---|---|
| `--optional` | may be omitted (required ones come first) |
| `--variadic` | takes all remaining arguments (always the last one) |
| `--choices "a b"` | allowed values |
| `--choices-from "cmd"` / `--strict` | same as for `flag` |

#### Dynamic choices: `--choices-from`

When the list depends on the machine or the moment (git branches, containers, files…), give
a command instead of a fixed list. It runs at each <kbd>Tab</kbd> and must print one value
per line, optionally followed by a tab and a description:

```bash
# an external command, run in the user's current directory
arg branch "Branch to deploy" --choices-from "git branch --format='%(refname:short)'"

# or a function defined in the flags.sh itself
_containers() { docker ps --format '{{.Names}}\t{{.Image}}'; }
flag container -c string "Container" --choices-from _containers --strict

# or a script of the plugin
arg host "Server" --choices-from '"$CB_COMMAND_DIR/_hosts.sh"'
```

- By default, values are only **suggested**: any other value is still accepted (useful for
  a remote branch not fetched yet, for example).
- With `--strict`, the typed value is **validated** against the list (the command then also
  runs at launch).
- The command must be fast (it runs at each <kbd>Tab</kbd>); its errors are ignored.
- Available variables: `CB_NAME`, `CB_ROOT`, `CB_CONFIG_DIR`, `CB_COMMAND_DIR`, `CB_PLUGIN_ROOT`.

Parsing accepts `--name`, `--name=val`, `--name val`, `--no-name`, `-x`, `-x val`, `-xval`,
`-abc` (grouped bools), `--` (end of options); options may be placed anywhere.
`-h` / `--help` are reserved.

### `cmd.sh`

```bash
[[ $FLAG_VERBOSE == 1 ]] && ui::info "Restoring $ARG_DB to $FLAG_OUTPUT"
ui::confirm "Overwrite $ARG_DB?" n || ui::die "cancelled"
for f in "${@:2}"; do ...; done       # "$@" = all positional arguments
ui::success "Done"
```

| Variable | Content |
|---|---|
| `FLAG_<NAME>` | value of the option (`--dry-run` → `FLAG_DRY_RUN`, bool = `0`/`1`) |
| `ARG_<NAME>` | value of the argument (variadic: values separated by spaces) |
| `"$@"` | positional arguments, options removed |
| `CB_NAME` | name of the root command (`mu`) |
| `CB_COMMAND` | full command (`mu backup db restore`) |
| `CB_COMMAND_DIR` / `CB_PLUGIN_ROOT` | directory of the command / of the plugin |
| `CB_ROOT` / `CB_CONFIG_DIR` | cmd-builder root / `~/.config/mu` |

Helpers: `ui::info`, `ui::success`, `ui::warn`, `ui::error` (on stderr), `ui::die "msg" [code]`,
`ui::title`, `ui::confirm "Question?" [y|n]`, `ui::ask "Question" [default]`, and the colours
`UI_BOLD`, `UI_GREEN`, `UI_RESET`… (disabled when `NO_COLOR` is set or when the output is not a terminal).

## Plugins: official, personal and conflicts

- `core/` holds the official plugins, shipped with cmd-builder (id `core:<name>`).
- `plugins/` holds your plugins (id `user:<name>`), ignored by the cmd-builder repository:
  each one can be its own git repository (`git clone … plugins/my-cmds`).
- **Name conflict**: a personal plugin shadows the official plugin with the same name.
  `mu self doctor` and `mu self plugins` report it. To keep both, rename one in the config.
- `self` is reserved for the root command.

`~/.config/mu/config`:

```
disable core:system                 # disables a plugin
rename  core:docker core-docker     # exposes it under another name
```

## Built-in commands

| Command | Role |
|---|---|
| `mu self update [--check]` | updates cmd-builder and every plugin that has a git repository: shows the new commits, asks for confirmation for each repository, then `git pull --ff-only` |
| `mu self new <path…>` | generates a command (`--core`, `--git`, `-a "summary"`) |
| `mu self plugins` | lists plugins and their state |
| `mu self plugins enable <plugin>` | re-enables a plugin (name or id, Tab offers the disabled plugins) |
| `mu self plugins disable <plugin>` | disables a plugin (name or id, Tab offers the active plugins) |
| `mu self rename <name> [--keep-old]` | renames the root command, keeping the config (see [Rename the root command](#rename-the-root-command)) |
| `mu self doctor` | checks the installation, the config, conflicts, every `flags.sh` and every `example` |
| `mu self completion bash\|zsh` | prints the completion script |
| `mu self guide [request] [-o file]` | prints a guide for an AI assistant (ChatGPT, Claude…) that has no access to your machine, so it can tell you step by step how to create a command (`--no-commands`: do not list your commands). A request given on the command line is appended at the end, to paste everything as one message: `mu self guide "I want 'mu test hello', which prints hello"` |

## Contributing

Contributors (humans and AI agents) start with [`AGENTS.md`](AGENTS.md).

```bash
./tests/run.sh
```
