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
Running it again is safe.

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
| `mu self doctor` | checks the installation, the config, conflicts and every `flags.sh` |
| `mu self completion bash\|zsh` | prints the completion script |

## Contributing

Contributors (humans and AI agents) start with [`AGENTS.md`](AGENTS.md).

```bash
./tests/run.sh
```
