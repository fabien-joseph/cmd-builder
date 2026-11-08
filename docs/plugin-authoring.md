# Plugin authoring

The contract between cmd-builder and the commands it runs. **This is a public API**:
plugins written by users rely on it, so changes must stay backward compatible.
(A user-facing summary lives in `README.md`; keep both in sync.)

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
- Directories whose name starts with `_` or `.` are ignored.
- `cmd.sh` is run with Bash, with the `ui::` helpers loaded. `cmd` can be any executable
  (Python, binary…) with a shebang and the executable bit; it receives the same environment.
- Official plugins live in `core/` (id `core:<name>`), user plugins in `plugins/`
  (id `user:<name>`). `self` is reserved.
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
```

### `about`, `description`, `example`

- `about` — one line, shown everywhere the command is listed.
- `description` — free text, shown under the header in `--help`.
- `example` — repeatable; the root command name is prefixed automatically
  (`example "backup db restore prod"` renders as `mu backup db restore prod`).

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
| `--choices "a b c"` | fixed allowed values: validated, offered by completion |
| `--choices-from "<cmd>"` | values computed at completion time (see below) |
| `--strict` | with `--choices-from` only: also validate the given value |

`--help` and `-h` are reserved. A flag name or short form can only be declared once.

### `arg`

Name: `^[a-z0-9][a-z0-9_-]*$`. Positional, in declaration order.

| Option | Effect |
|---|---|
| `--optional` | may be omitted; required args cannot follow an optional one |
| `--variadic` | takes all remaining positionals; must be the last arg |
| `--choices "a b c"` | fixed allowed values |
| `--choices-from "<cmd>"` / `--strict` | same as for `flag` |

Without a variadic arg, extra positionals are an error.

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

### Parsing rules

`--name`, `--name=value`, `--name value`, `--no-name`, `-x`, `-x value`, `-xvalue`, `-abc`,
`--` (end of options). Options may appear anywhere among positionals. `-5` is a positional
unless `-5` is a declared short flag. `-` alone is a positional.

## What the command receives

| Variable | Content |
|---|---|
| `FLAG_<NAME>` | flag value; name upper-cased, `-` → `_` (`--dry-run` → `FLAG_DRY_RUN`); bools are `0`/`1`; unset string flags are empty |
| `ARG_<NAME>` | arg value (variadic: values joined with spaces — prefer `"$@"`) |
| `"$@"` | all positionals, options removed |
| `CB_NAME` | root command name (`mu`) |
| `CB_COMMAND` | full command path (`mu backup db restore`) |
| `CB_COMMAND_DIR` | directory of the running command |
| `CB_PLUGIN_ROOT` | directory of the top-level plugin |
| `CB_ROOT` | cmd-builder checkout |
| `CB_CONFIG_DIR` | `~/.config/<name>` |

`FLAG_*` / `ARG_*` inherited from a parent invocation are cleared, so nested calls
(`mu a` calling `mu b`) do not leak values.

## `ui::` helpers (available in `cmd.sh`)

| Helper | Effect |
|---|---|
| `ui::info "msg"` | `› msg` on stderr |
| `ui::success "msg"` | `✔ msg` on stderr |
| `ui::warn "msg"` | `⚠ msg` on stderr |
| `ui::error "msg"` | `✖ msg` on stderr |
| `ui::die "msg" [code]` | error then `exit code` (default 1) |
| `ui::title "text"` | bold line on stdout |
| `ui::confirm "Question ?" [y\|n]` | returns 0 for yes; reads `/dev/tty`; without a terminal always returns 1 |
| `ui::ask "Question" [default]` | prints the answer (or the default) on stdout |

Colours for stdout: `UI_BOLD`, `UI_DIM`, `UI_RED`, `UI_GREEN`, `UI_YELLOW`, `UI_BLUE`,
`UI_CYAN`, `UI_RESET` — empty when stdout is not a terminal or `NO_COLOR` is set.

Messages go to stderr so stdout stays pipeable.
