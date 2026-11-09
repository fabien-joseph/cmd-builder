# cmd-builder

A manager and generator of Linux commands in **pure Bash**. Your commands, on all your
machines, under the name of your choice, with `--help`, option parsing and completion
generated automatically.

```
$ mu system info -s
my-laptop · Linux 6.18 · up 50 min
```

## Installation

Requirements: **Bash ≥ 4.2** (on macOS: `brew install bash`; macOS terminals start login
shells, which read `~/.bash_profile`: make it `source ~/.bashrc`) and git. Clone it from WSL
(or keep `core.autocrlf` off): the repository forces LF line endings (`.gitattributes`).

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
to `~/.bashrc` / `~/.zshrc`, the completion scripts and, after confirmation (default: no), the config.
Each step is independent and checks whether it is already done: if the uninstall is
interrupted halfway, run it again and it finishes the job. The cmd-builder directory and your
plugins are left untouched.
If the `>>>` marker of the rc block is there but its `<<<` end marker is not (edited by
hand), the rc file is left untouched with a warning and the uninstall exits with code 1:
remove the block by hand. `./init.sh` without a name only prints the usage.

### Tools your plugins need

Official plugins need nothing beyond Bash. A personal command can declare the tools it
needs (`requires fzf` in its `flags.sh`, see [docs/plugin-authoring.md](docs/plugin-authoring.md)):
it then refuses to run while one is missing, and tells you to run `mu self deps install`.
`init.sh` asks once which package manager to use for them (the one detected on your system
is suggested); `mu self deps managers add|remove` changes it later. Only the managers
listed there are ever used, always after a confirmation (with `sudo` when needed). For a
security fix, `mu self deps update` updates them all; `mu self update` reminds you of it.

### Rename the root command

```bash
mu self rename xx              # "mu" becomes "xx"
mu self rename xx --keep-old   # "xx" is added, "mu" keeps working
```

Moves the `~/.local/bin/mu` link, `~/.config/mu/` (your config and the files your plugins
keep there; the completion scripts are regenerated for the new name) and the `mu` blocks of `~/.bashrc` / `~/.zshrc`
(replaced in place). It shows the plan and asks one confirmation first. If it is
interrupted, or a step fails (it then stops, the old name still works), run the same
command again and it finishes the job. It refuses, without
changing anything, if `~/.local/bin/xx` is not one of its links or if `~/.config/xx/config`
already exists with a different content (uninstall `xx` first, or merge the files by hand).
Scripts and aliases that call `mu` must then use `xx`, unless `--keep-old`: both names then
work and share one config (`~/.config/mu/config` becomes a link to `~/.config/xx/config`;
`./init.sh --uninstall mu` later removes only the link, `./init.sh --uninstall xx` gives the
file back to `mu`).

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

### `flags.sh` and `cmd.sh`

```bash
# plugins/backup/db/restore/flags.sh: declarations (--help, parsing and Tab come from it)
about "Restore a database"
flag verbose -v bool   "Verbose mode"
flag jobs    -j int    "Parallel jobs"    --default 2
arg  db         "Database to restore"     --choices "prod staging"
arg  branch     "Branch"                  --choices-from "git branch --format='%(refname:short)'"
example "backup db restore prod -j 4" "Restore prod with 4 jobs"
```

```bash
# plugins/backup/db/restore/cmd.sh: the code, values in FLAG_* / ARG_* / "$@"
[[ $FLAG_VERBOSE == 1 ]] && ui::info "Restoring $ARG_DB with $FLAG_JOBS jobs"
ui::confirm "Overwrite $ARG_DB?" n || ui::die "cancelled"
ui::success "Done"
```

The DSL (`about`, `description`, `flag`, `arg`, `example`, `requires`), the parsing rules, the
variables (`FLAG_*`, `ARG_*`, `CB_NAME`, `CB_COMMAND`, `CB_COMMAND_DIR`, `CB_PLUGIN_ROOT`,
`CB_ROOT`, `CB_CONFIG_DIR`, `CB_VERSION`) and the `ui::` helpers (`ui::confirm`, `ui::select`
for menus without `fzf`…) are described in **[docs/plugin-authoring.md](docs/plugin-authoring.md)**,
the single reference (also embedded in `mu self guide`). Changes of this contract are listed
in [CHANGELOG.md](CHANGELOG.md).

## Plugins: official, personal and conflicts

- `core/` holds the official plugins, shipped with cmd-builder (id `core:<name>`).
- `plugins/` holds your plugins (id `user:<name>`), ignored by the cmd-builder repository:
  each one can be its own git repository (`git clone … plugins/my-cmds`).
- **Name conflict**: a personal plugin shadows the official plugin with the same name.
  `mu self doctor` and `mu self plugins` report it. To keep both, rename one in the config.
- **Adding to an official plugin**: `plugins/+system/disk/` adds `mu system disk` next to
  the official `mu system info` (an *extension*, id `user:+system`); `mu self new system disk`
  creates it. Details in [docs/plugin-authoring.md](docs/plugin-authoring.md).
- `self` is reserved for the root command.
- **A plugin runs code as soon as it is installed**: its `flags.sh` is read at `mu --help`
  and at every <kbd>Tab</kbd>, before you ever run it. Clone only plugins you trust, after
  reading them.

`~/.config/mu/config`:

```
disable core:system                 # disables a plugin
rename  core:docker core-docker     # exposes it under another name
package-manager apt                 # installs the tools your plugins need (repeatable)
```

## Built-in commands

`mu --version` prints the version of cmd-builder (also in `mu self doctor`).

| Command | Role |
|---|---|
| `mu self update [--check]` | updates cmd-builder and every plugin that has a git repository (exit code 1 if one could not be checked or updated; `--check` exits 10 when there are updates): shows the new commits, asks for confirmation for each repository, then `git pull --ff-only` |
| `mu self new <path…>` | generates a command (`--core`, `--git`, `-a "summary"`) |
| `mu self plugins` | lists plugins and their state |
| `mu self plugins enable <plugin>` | re-enables a plugin (name or id, Tab offers the disabled plugins) |
| `mu self plugins disable <plugin>` | disables a plugin (name or id, Tab offers the active plugins) |
| `mu self rename <name> [--keep-old]` | renames the root command, keeping the config (see [Rename the root command](#rename-the-root-command)) |
| `mu self deps` | lists the tools your commands need (`requires` in `flags.sh`), their state and the commands using them |
| `mu self deps install [--all]` | installs the missing tools with your package manager, after one confirmation (`--all`: optional ones too) |
| `mu self deps update` | updates every installed tool your commands need (security fixes) |
| `mu self deps managers` | lists the package managers used (`mu self deps managers add <manager>` / `mu self deps managers remove <manager>`); supported: apt, dnf, pacman, zypper, apk, brew |
| `mu self doctor` | checks the installation, the config, conflicts, every `flags.sh` and every `example` |
| `mu self completion bash\|zsh` | prints the completion script |
| `mu self guide [request] [-o file]` | prints a guide for an AI assistant (ChatGPT, Claude…) that has no access to your machine, so it can tell you step by step how to create a command (`--no-commands`: do not list your commands). A request given on the command line is appended at the end, to paste everything as one message: `mu self guide "I want 'mu test hello', which prints hello"` |

## Contributing

Contributors (humans and AI agents) start with [`AGENTS.md`](AGENTS.md).

```bash
./tests/run.sh
```
