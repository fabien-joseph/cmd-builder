# Plugin authoring

The contract between cmd-builder and the commands it runs. **This is a public API**:
plugins written by users rely on it, so changes must stay backward compatible.
(A user-facing summary lives in `README.md`; keep both in sync.)

Everything between the `guide:begin` / `guide:end` markers below is also embedded, as is,
in the guide printed by `mu self guide` (for AI assistants without access to the machine):
keep it self-contained (no relative links) and keep the markers.

<!-- guide:begin -->
## Layout

```
plugins/backup/              → mu backup          (plugin id: user:backup)
├── flags.sh                 declarations for "mu backup"
├── cmd.sh                   optional: without it, "mu backup" only routes to subcommands
├── _lib/                    ignored by routing (helpers, assets…)
└── db/                      → mu backup db
    ├── flags.sh
    ├── cmd.sh
    └── restore/             → mu backup db restore   (no depth limit)
```

- A directory is a command if it contains `flags.sh`, `cmd.sh` or `cmd`.
- Directories whose name starts with `_` or `.` are ignored; `+` marks an extension (below).
- `cmd.sh` is run with Bash, with the `ui::` helpers loaded. `cmd` can be any executable
  (Python, binary…) with a shebang and the executable bit; it receives the same environment.
- Official plugins live in `core/` (id `core:<name>`), user plugins in `plugins/`
  (id `user:<name>`). `self` is reserved. `plugins/system/` would **shadow** the official
  `system` plugin entirely.
- **Adding to an official plugin**: a directory `plugins/+<plugin>/` is an *extension*
  (id `user:+<plugin>`): its subcommands are added to the official plugin, which keeps
  its own commands. `mu self new system disk` creates it for you:
  ```
  plugins/+system/            extends core:system (no files of its own)
  ├── disk/                   → mu system disk       (next to the official mu system info)
  └── +net/                   extends the official group "mu system net"
      └── trace/              → mu system net trace
  ```
  The `+` works at every level. A plain directory with the name of an official
  subcommand (`plugins/+system/info/`) replaces it (reported, like a plugin conflict).
  For a command of an extension, `CB_PLUGIN_ROOT` is `plugins/+system` (its own `_lib/`).
  An extension follows its official plugin: renamed with it, inactive when it is
  disabled, shadowed or missing (reported by `self doctor` and `self plugins`). It can be
  disabled itself (`disable user:+system`), not renamed. Files at the root of an extension
  (`plugins/+system/flags.sh`) are ignored and reported.
- Scaffold with `mu self new <path…>` (see `mu self new --help`).

## `flags.sh` DSL

`flags.sh` is sourced by the framework (for help, parsing and completion), so it must only
declare things and stay fast: no side effects, no slow commands at top level.

```bash
about       "One-line summary"                 # help header, command lists, completion
description "Longer text shown in --help"

flag <name> [-x] <bool|string|int> "description" [options]
arg  <name> "description" [options]
example "<command line without the root name>" ["explanation"]
requires <tool> [--optional] [--apt|--dnf|--pacman|--zypper|--apk|--brew <package|->]
```

### Required and optional fields

`flags.sh` itself is optional: without it (a `cmd.sh` alone), the command takes no option
and no argument. Every line is optional too; only the fields of a line that is written are
checked.

| Line | Required fields, in this order | Optional |
|---|---|---|
| `about "text"` | the text | the whole line (no summary in lists and `--help`) |
| `description "text"` | the text (several lines allowed) | the whole line |
| `flag` | name, type, description | short form `-x` (between name and type), options |
| `arg` | name, description | options |
| `example` | command line, without the root name | explanation |
| `requires` | the command name of the tool | `--optional`, package names |

- Options of `flag` and `arg` come **after the description**, in any order.
- A description may be empty (`""`), but it cannot be left out: `flag verbose bool` is an
  error.
- Lines may come in any order, except that `arg` lines define the order of the positionals.
- An `arg` is **required unless `--optional`** is given.
- `flags.sh` is Bash: quote texts containing spaces, `#` starts a comment, `$` is expanded
  inside double quotes (use single quotes for a literal `$`), functions may be defined (for
  `--choices-from`).

### Complete example

Every kind of line, with the values `cmd.sh` receives:

<!-- flags-example:begin -->
```bash
# flags.sh of "mu backup db restore"
about "Restore a database"
description "Restores a dump file into a database.
Asks for confirmation before overwriting existing tables."

#    name     short  type    description              options
flag verbose  -v     bool    "Verbose output"
flag yes      -y     bool    "Do not ask for confirmation"
flag format   -f     string  "Dump format"            --choices "sql csv" --default sql
flag jobs     -j     int     "Parallel jobs"          --default 2
flag token           string  "Access token"           --required
flag host            string  "Database server"        --choices-from _hosts

#   name     description              options
arg db       "Database to restore"    --choices "prod staging"
arg dump     "Dump file"              --optional
arg tables   "Tables to restore"      --optional --variadic

example "backup db restore prod dump.sql --token T" "Restore prod from dump.sql"
example "backup db restore staging -y -j 4 --token T" "Without confirmation, 4 jobs"

# Values offered by Tab for --host (one per line, optional TAB + description).
_hosts() { printf '%s\t%s\n' db1 "Primary" db2 "Replica"; }
```
<!-- flags-example:end -->

`mu backup db restore prod dump.sql users orders --token T -v` runs `cmd.sh` with:

<!-- flags-values:begin -->
```text
FLAG_VERBOSE=1
FLAG_YES=0
FLAG_FORMAT=sql
FLAG_JOBS=2
FLAG_TOKEN=T
FLAG_HOST=
ARG_DB=prod
ARG_DUMP=dump.sql
ARG_TABLES=users orders
$@=prod dump.sql users orders
```
<!-- flags-values:end -->

### `about`, `description`, `example`

- `about` — one line, shown everywhere the command is listed.
- `description` — free text, shown under the header in `--help`.
- `example` — repeatable; the root command name is prefixed automatically
  (`example "backup db restore prod"` renders as `mu backup db restore prod`).
  `self doctor` checks each example like the parser would (unknown option, missing
  required flag or argument, unknown command, unbalanced quotes, root name written in it)
  and warns; values of `--choices-from --strict` are not checked there.

### `flag`

Name: `^[a-z0-9][a-z0-9-]*$`. Optional short form `-x` (one letter or digit). Types:

| Type | Value | Notes |
|---|---|---|
| `bool` | `1` when given, else `0` | `--no-<name>` sets `0`; `-abc` groups bools |
| `string` | any text | |
| `int` | `^-?[0-9]+$` | validated |

| Option | Effect |
|---|---|
| `--default <v>` | default value (`0` or `1` for a bool; validated against type and `--choices`) |
| `--required` | the flag must be given (not for bools) |
| `--choices "a b c"` | fixed allowed values, separated by spaces (a value cannot contain a space): validated, offered by completion |
| `--choices-from "<cmd>"` | values computed at completion time (see below) |
| `--strict` | with `--choices-from` only: also validate the given value |

`--help` and `-h` are reserved. A flag name or short form can only be declared once.
A `bool` accepts only `--default 0|1`: `--required`, `--choices` and `--choices-from` are
errors on it. Without `--default`, an absent `string` / `int` flag is empty.

### `arg`

Name: `^[a-z0-9][a-z0-9_-]*$`. Positional, in declaration order.

| Option | Effect |
|---|---|
| `--optional` | may be omitted; required args cannot follow an optional one |
| `--variadic` | takes all remaining positionals; must be the last arg |
| `--choices "a b c"` | fixed allowed values |
| `--choices-from "<cmd>"` / `--strict` | same as for `flag` |

Without a variadic arg, extra positionals are an error. An optional arg that is not given
is empty. A variadic arg without `--optional` needs at least one value.

### Dynamic choices: `--choices-from`

The value is a shell snippet evaluated with `eval` at each <kbd>Tab</kbd> (and at run time
when `--strict` is set). It must print one value per line, optionally followed by a TAB and
a description. It runs in the **user's current directory**, can call functions defined in the
same `flags.sh`, and sees `CB_COMMAND_DIR` and `CB_PLUGIN_ROOT`. Its stderr is discarded.

```bash
arg branch "Branch" --choices-from "git branch --format='%(refname:short)'"
_containers() { docker ps --format '{{.Names}}\t{{.Image}}'; }
flag container -c string "Container" --choices-from _containers --strict
arg host "Server" --choices-from '"$CB_COMMAND_DIR/_hosts.sh"'
```

Without `--strict`, values are suggestions only (any value is accepted). `--choices` and
`--choices-from` are mutually exclusive. Keep the snippet fast: there is no timeout.

### `requires`: tools the command needs

Only for **user plugins**: official plugins (`core/`) and `self` never need anything beyond
Bash and POSIX tools. Declare each extra tool (by the name of its command) on its own line:

```bash
requires fzf                               # package "fzf" with every package manager
requires fd --apt fd-find --brew fd        # the package has another name on apt
requires mytool --brew -                   # "-": not packaged for brew
requires jq --optional                     # the command works without it
```

- Before running the command, the framework checks with `command -v` that every required
  tool is installed. If one is missing, the command does not run:
  `✗ 'mu x' needs 'fzf', not installed` / `Install: mu self deps install` (exit code 1).
  `--help` and Tab completion still work.
- `--optional`: not checked. The command handles its absence itself, e.g.
  `if command -v jq >/dev/null; then … else … fi`. It is listed as optional by
  `mu self deps` and installed by `mu self deps install --all`.
- Package options (`--apt`, `--dnf`, `--pacman`, `--zypper`, `--apk`, `--brew`) give the
  package name for that manager when it differs from the tool name; `-` means it is not
  packaged there. Note that the package must provide a command with the declared name.
- The user installs and updates the tools with `mu self deps install` / `update`, with the
  package managers they chose (`mu self deps managers`), after one confirmation.
- To let the user pick in a list, you do not need `fzf`: use `ui::select` (pure Bash).

### Parsing rules

`--name`, `--name=value`, `--name value`, `--no-name`, `-x`, `-x value`, `-xvalue`, `-abc`,
`--` (end of options). Options may appear anywhere among positionals. `-5` is a positional
unless `-5` is a declared short flag. `-` alone is a positional.

## What the command receives

| Variable | Content |
|---|---|
| `FLAG_<NAME>` | flag value; name upper-cased, `-` → `_` (`--dry-run` → `FLAG_DRY_RUN`); bools are `0`/`1`; unset string flags are empty |
| `ARG_<NAME>` | arg value, same name conversion (`my-file` → `ARG_MY_FILE`); empty when an optional arg is not given; variadic: values joined with spaces — prefer `"$@"` |
| `"$@"` | all positionals, options removed |
| `CB_NAME` | root command name (`mu`) |
| `CB_COMMAND` | full command path (`mu backup db restore`) |
| `CB_COMMAND_DIR` | directory of the running command |
| `CB_PLUGIN_ROOT` | directory of the top-level plugin (for a command of an extension: `plugins/+<plugin>`) |
| `CB_ROOT` | cmd-builder checkout |
| `CB_CONFIG_DIR` | `~/.config/<name>` |

`FLAG_*` / `ARG_*` inherited from a parent invocation are cleared, so nested calls
(`mu a` calling `mu b`) do not leak values.

## `ui::` helpers (available in `cmd.sh`)

| Helper | Effect |
|---|---|
| `ui::info "msg"` | `› msg` on stderr |
| `ui::success "msg"` | `✓ msg` on stderr |
| `ui::warn "msg"` | `! msg` on stderr |
| `ui::error "msg"` | `✗ msg` on stderr |
| `ui::die "msg" [code]` | error then `exit code` (default 1) |
| `ui::title "text"` | bold line on stdout |
| `ui::confirm "Question ?" [y\|n]` | returns 0 for yes; reads `/dev/tty`; without a terminal always returns 1 |
| `ui::ask "Question" [default]` | prints the answer (or the default) on stdout |
| `ui::select "Question" [-d default] option...` | menu: arrow keys (or `j`/`k`, or the option number) then Enter; prints the chosen option on stdout. Esc or `q` cancels (returns 1). Without a terminal: prints the default if given, otherwise returns 1. Pure Bash, no `fzf` needed: `choice=$(ui::select "Environment?" dev staging prod) \|\| ui::die "cancelled"` |

Colours for stdout: `UI_BOLD`, `UI_DIM`, `UI_RED`, `UI_GREEN`, `UI_YELLOW`, `UI_BLUE`,
`UI_CYAN`, `UI_RESET` — empty when stdout is not a terminal or `NO_COLOR` is set.

Messages go to stderr so stdout stays pipeable.
<!-- guide:end -->
