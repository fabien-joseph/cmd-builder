# Architecture

How cmd-builder works internally. Read this before changing `lib/`, `main.sh`, `init.sh`
or `builtin/`. For the plugin-facing contract, see [plugin-authoring.md](plugin-authoring.md).

## Big picture

```
~/.local/bin/mu ──symlink──▶ main.sh
                                │  resolves CB_ROOT, CB_NAME (= symlink name), CB_CONFIG_DIR
                                ▼
                           lib/core.sh  (sources every lib/*.sh)
                                ▼
                           cb::main  (lib/router.sh)
                                │  1. cb::config_load    read ~/.config/mu/config
                                │  2. cb::plugins_load   discover core/ + plugins/, resolve names
                                │  3. route words → command directory
                                ▼
                           cb::run
                                │  4. cb::spec_load      source <dir>/flags.sh (DSL)
                                │  5. cb::parse          validate argv against the spec
                                │  6. cb::export_values  FLAG_* / ARG_* / CB_* env vars
                                ▼
   exec bash -c 'source lib/ui.sh; source "$0"' <dir>/cmd.sh <positionals>
                                         (or exec <dir>/cmd <positionals>)
```

The command runs in a **fresh process** (`exec`): framework globals never leak into plugin
code, and plugins written in any language receive the same environment.

## Key concepts

**Command directory.** A directory is a command if it contains `flags.sh`, `cmd.sh` or `cmd`
(`cb::is_command_dir`). Its subdirectories that are themselves commands are its subcommands
(`cb::children`). Names must match `^[a-zA-Z0-9][a-zA-Z0-9_-]*$`, so `_lib/`, `.git/` etc.
are ignored. A command without an executable is a pure *router*: it shows its help.

**Executable.** `cmd.sh` (sourced by a fresh `bash -c` that loads `lib/ui.sh` first, with `$0` = the `cmd.sh` path) wins over
`cmd` (any executable file). See `cb::executable`.

**Routing.** After the plugin name, words that name a child command are consumed greedily;
the first word that is not a child (or that starts with `-`) stops routing and everything
left goes to the reached command. A child name therefore always wins over a positional
argument with the same value. The rule lives in `cb::descend` (`_CB_ROUTE_DIR`,
`_CB_ROUTE_N`), used by `cb::main`, `cb::complete` and `self doctor`; `cb::parse` refuses an
option followed by a child name (`mu backup -v restore`) and suggests a child for an
unexpected first argument. `self new` resolves its first word through exposed names too
(renamed plugins), and `cb::walk` skips symlinked subcommands pointing to a parent.
`cb::help` shows examples of a renamed plugin under its exposed name (`cb::_example_line`).

**Plugin ids and exposed names.** Every top-level plugin has an id `core:<dir>` or
`user:<dir>` and an *exposed name* (the dir name, or the `rename` target from config).
`cb::plugins_load` processes `core/` first, then `plugins/`, so a user plugin with the same
exposed name **shadows** the core one. `self` is reserved. Conflicts are collected in
`_CB_CONFLICTS` and reported by `self doctor`, `self plugins` and the root help.
**Extensions** (decision 0013). `plugins/+<x>/` (id `user:+<x>`, name `+<exposed name>`)
adds subcommands to `core:<x>`. `cb::_extensions_load` (end of `cb::plugins_load`) fills
`_CB_OVL[<official command dir>]=<extension dir>`, recursively for `+<sub>` directories
(`cb::_overlay`), and reports orphans, ignored root files and shadowed subcommands in
`_CB_CONFLICTS`. Every tree walk goes through `cb::children` (merges the overlay),
`cb::is_child` and `cb::child_dir` (the user directory wins): never build `$dir/$name`
by hand. `cb::plugin_root_of` gives `CB_PLUGIN_ROOT` = the extension root for its commands.

Plugin states: `active`, `disabled`, `reserved`, `shadowed:<id>`; for extensions
`extends:<id>`, `inactive:<id>` (official plugin not active), `orphan`.

## Files in `lib/`

| File | Responsibility |
|---|---|
| `lib/core.sh` | Sources all libs in order; sets defaults for `CB_ROOT`, `CB_NAME`, `CB_CONFIG_DIR` when sourced outside `main.sh` |
| `lib/util.sh` | Generic helpers: `cb::realpath` (portable symlink resolution), name validation, command-dir detection, `cb::children` / `cb::is_child` / `cb::child_dir` (extension-aware), `cb::walk` (`dir<TAB>words`), `cb::plugin_root_of`, `cb::suggest`, `cb::dq` |
| `lib/ui.sh` | Public `ui::` helpers and `UI_*` colours (also loaded into every `cmd.sh`); prompts read `${_CB_TTY:-/dev/tty}` (decision 0009) |
| `lib/config.sh` | Reads/writes `$CB_CONFIG_DIR/config` (`disable`, `rename`); `cb::config_set_disabled` rewrites the file atomically |
| `lib/plugins.sh` | Plugin discovery, disable/rename application, shadowing, extensions (`_CB_OVL`), `cb::plugin_dir` |
| `lib/spec.sh` | The `flags.sh` DSL (`about`, `description`, `flag`, `arg`, `example`), spec state, static/dynamic choices (`cb::choices_of`, `cb::choice_ok`) |
| `lib/help.sh` | Generated `--help` for a command (`cb::help`) and for the root (`cb::help_root`) |
| `lib/parse.sh` | Argument parser (`cb::parse`) and env export (`cb::export_values`) |
| `lib/router.sh` | `cb::main` (entry), `cb::run` (spec → parse → exec), unknown-command errors |
| `lib/complete.sh` | Shell-agnostic completion engine (`cb::complete`) and completion script generation |
| `lib/install.sh` | Install helpers shared by `init.sh` and `self rename`: rc block markers, `cb::rc_block` / `cb::rc_append` / `cb::rc_replace` (atomic rewrite), `cb::link_is_ours` / `cb::link_remove`, config-dir entries and cleanup (`cb::config_dir_entries`, `cb::config_shared_with`), `cb::tilde`, `_CB_BIN_DIR`. Not loaded by `lib/core.sh` |
| `lib/deps.sh` | Plugin dependencies (decision 0014): `cb::pm_detect`, `cb::pm_ask` (`ui::select`, saved in the config), `cb::pm_for` / `cb::pm_package` / `cb::pm_commands` (install/update command lines per manager, `sudo` unless root, never for brew), `cb::deps_collect` (the `requires` of every active command into `_CB_DEP_*`). Not loaded by `lib/core.sh` |

## Global state

All framework globals are prefixed `_CB_` (never use that prefix in plugins).
Spec state is **reset by `cb::spec_reset`** each time a `flags.sh` is loaded; only one spec
is loaded at a time in the main process. To read another command's spec without clobbering
the current one, use a subshell (that is what `cb::about_of` does).
Associative arrays are declared once at the top level of their `lib/` file and only reset in
functions (`name=()`): Bash 4.2 ignores `declare -g` for an assignment inside a function
(see `docs/conventions.md`, decision 0011).

| Variable(s) | Filled by | Content |
|---|---|---|
| `_CB_DISABLED`, `_CB_RENAME`, `_CB_CONFIG_ERRORS` | `cb::config_load` | parsed config |
| `_CB_PLUGINS`, `_CB_PLUGIN_ID`, `_CB_PLUGIN_NAMES` | `cb::plugins_load` | active plugins by exposed name |
| `_CB_IDS`, `_CB_ID_DIR`, `_CB_ID_NAME`, `_CB_ID_STATE`, `_CB_CONFLICTS` | `cb::plugins_load` | every discovered plugin, by id (extensions included) |
| `_CB_OVL` | `cb::plugins_load` | official command directory → directory of its extension |
| `_CB_ABOUT`, `_CB_DESC`, `_CB_EXAMPLES`, `_CB_SPEC_FILE` | `flags.sh` | command metadata |
| `_CB_FLAGS` + `_CB_F_*` (assoc. by flag name) | `flag` | `TYPE`, `SHORT`, `DESC`, `DEFAULT`, `REQ`, `CHOICES`, `CHFROM`, `STRICT`; `_CB_F_BYSHORT` maps short → name |
| `_CB_ARGS` + `_CB_A_*` (assoc. by arg name) | `arg` | `DESC`, `OPT`, `VAR`, `CHOICES`, `CHFROM`, `STRICT` |
| `_CB_VAL`, `_CB_AVAL`, `_CB_POS` | `cb::parse` | parsed flag values, arg values, positionals |
| `_CB_REQS` + `_CB_R_OPT`, `_CB_R_PKG` | `requires` | required tools; optional flag; `<manager>/<tool>` → package |
| `_CB_PMS`, `_CB_PM_ALL` | `cb::config_load` | configured package managers; supported ones |
| `_CB_DEP_TOOLS`, `_CB_DEP_REQ`, `_CB_DEP_USERS`, `_CB_DEP_PKG` | `cb::deps_collect` | tools of every active command |
| `_CB_NO_DYNAMIC` | `self doctor` | when set, `cb::choice_ok` does not validate `--choices-from --strict` values |

## Exit codes

| Code | Meaning | Where |
|---|---|---|
| 0 | success, or help displayed | everywhere |
| 1 | generic failure (`ui::die` default) | commands, `self doctor` with errors, `init.sh --uninstall` that left an rc block in place, `self rename` refused, cancelled or incomplete, a command whose required tool is missing (`cb::_check_requires`, after parsing), `self deps install` that left a tool missing |
| 2 | usage error: unknown command/option, invalid or missing value | `lib/parse.sh`, `lib/router.sh`, `init.sh` without a name |
| 3 | invalid `flags.sh` (DSL error, reported as `file:line : message`) | `cb::_spec_err` |

## Completion protocol

Shell adapters (`templates/completion.bash`, `templates/completion.zsh`) call:

```
<name> __complete -- <word1> … <current word>
```

`cb::complete` prints one candidate per line as `value<TAB>description` (already filtered
by the current word's prefix). Empty output means "fall back to file completion".
The bash adapter re-splits `COMP_LINE` itself because `COMP_WORDS` also splits on `:` and
`=`, then strips the part bash will not replace. The engine reuses the real routing and
spec loading, so completion can never disagree with execution.
The bash adapter reads candidates with `mapfile` so the user's `nullglob` / `failglob` never
glob them. `--flag=<TAB>` returns the flag's choices as full `--flag=value` words, and a
`-<digit>…` word counts as a positional (negative number), exactly as in `cb::parse`.
`cb::spec_load` returns 0 whatever the last command of `flags.sh` returns: only DSL
errors (exit 3) make a `flags.sh` invalid.
`flags.sh` runs in the framework process: `cb::spec_load` sends its output to stderr and
puts back shell options (`set -e`, `-u`, `pipefail`, `failglob`), `IFS` and the current
directory. Its variables stay global for its `--choices-from` snippets, so a function that
loads a spec must not keep unprefixed locals across the call: `cb::run` and
`cb::_complete_at` load it before declaring theirs.

`--choices-from` commands are evaluated with `eval` in a subshell, in the user's current
directory, with `CB_COMMAND_DIR` / `CB_PLUGIN_ROOT` exported and the `flags.sh` functions
in scope; stderr is discarded.

## Configuration

`$CB_CONFIG_DIR/config` (default `~/.config/<name>/config`), one directive per line,
`#` comments:

```
disable <core|user>:<plugin>
rename  <core|user>:<plugin> <new-name>
package-manager <apt|dnf|pacman|zypper|apk|brew>   # repeatable, order of preference (`_CB_PMS`)
```

Invalid lines do not stop the program; they are collected in `_CB_CONFIG_ERRORS` and
reported by `self doctor`.
`self plugins enable|disable` rewrite the file atomically (temp file + `mv`); when the config
is a symlink (dotfiles), they rewrite its target and keep the link.

## Built-in commands (`builtin/self/`)

They are ordinary command directories, routed for the reserved name `self`, and are the
best examples of the framework in use. They source `lib/core.sh` to access internals.

| Command | Role |
|---|---|
| `self update` | `git fetch` the main repo and every `plugins/*` with a `.git`, show new commits, confirm per repo, `git pull --ff-only`; `--check` only reports |
| `self new` | scaffold a command path (`flags.sh` + `cmd.sh`), `--core`, `--git`, `--about`; below an official plugin not replaced by the user, writes into its extension `plugins/+<x>/` (`+<group>` for official groups); refuses an official command or plugin as the target |
| `self plugins` | list plugins with id and state |
| `self plugins enable` / `self plugins disable` | toggle a plugin in the config (name or id, dynamic completion) |
| `self rename` | rename the root command: plan + one confirmation, then new link, config and plugin files of the config dir moved, completion regenerated, rc blocks replaced in place, old config dir and old link last; stops at the first failed step; resumable; `--keep-old` keeps the old name with links to the moved files (decision 0012) |
| `self deps` | list the `requires` of every active command (state, package, users); `self deps install [--all]` / `self deps update`: commands per manager shown, one confirmation, then run (`_common.sh`); `self deps managers` lists configured / detected, `self deps managers add` / `self deps managers remove` rewrite the `package-manager` lines |
| `self doctor` | check environment, link, completion files, config, conflicts, every `flags.sh`, and every `example` (routed from the root like `cb::main`, the plugin also accepted under its directory name, then `cb::parse` in a subshell with `_CB_NO_DYNAMIC=1`; warnings) |
| `self completion` | print the bash or zsh completion script |
| `self guide` | print `templates/ai-guide.md` filled in: root name, paths, system, Bash version, existing commands (unless `--no-commands`), help of `self new`, and the part of `docs/plugin-authoring.md` between `<!-- guide:begin -->` and `<!-- guide:end -->` (decision 0010); an optional request (variadic arg) is appended as a final "The user's request" section, quoted with `> `; `-o` writes a file, confirm before overwriting |

`builtin/self/plugins/_resolve.sh` is a shared helper (ignored by routing thanks to `_`).

## Installation layout (`init.sh`)

| Path | Created by | Removed by `--uninstall` |
|---|---|---|
| `~/.local/bin/<name>` → `main.sh` | install | yes, only if it points to this checkout |
| `~/.config/<name>/config` | install (`cb::config_ensure`), moved by `self rename` | after confirmation (default no); without asking if it is a symlink (only the link goes); moved onto another name's link when it is shared (`--keep-old`) |
| `~/.config/<name>/completion.{bash,zsh}` | install, `self update` | yes |
| block `# >>> cmd-builder: <name> >>>` … `<<<` in `~/.bashrc`, `~/.zshrc` | install, after confirmation | yes (atomic rewrite, follows symlinked rc files; refused with a warning if the end marker is missing) |

Several installs under different names can coexist: everything is keyed by `CB_NAME`.
`self rename` moves all of it from one name to another (decision 0012); the code that
knows this layout lives in `lib/install.sh`, shared by `init.sh` and `self rename`.
