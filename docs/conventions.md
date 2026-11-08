# Conventions

## Language

- **Everything in the repository is English**: code, identifiers, comments, user-facing
  messages, `--help`, `about`, README.md and docs. Quote names in messages with `'…'`.
- Confirmation prompts accept `y` / `yes` (`[Y/n]`, `[y/N]`).
- The owner talks to agents in French; that does not change the repository language.

## Bash

- Target **Bash ≥ 4.2** (decision 0008). Allowed: associative arrays, `mapfile`, `${var,,}` / `${var^^}`,
  `declare -g`, negative subscripts `${a[-1]}`. Not allowed: Bash 5-only features (`${var@U}`, `EPOCHSECONDS`, `wait -p`…).
- **No external dependencies** beyond POSIX tools available on Linux and macOS. Avoid
  GNU-only flags: no `readlink -f` (use `cb::realpath`), no `sed -i` (write a temp file then
  `mv`), no `grep -P`, no `date -d`. When a GNU/BSD difference is unavoidable, try GNU then
  fall back to BSD (see `chmod --reference` / `stat -f` in `lib/install.sh`).
- Shebang `#!/usr/bin/env bash` (picks Homebrew Bash on macOS). Entry scripts check the
  Bash version before using any Bash 4 syntax, with a `case` that `sh` can parse.
- Bash 4.2: never `declare -g` inside a function (`declare -gA name=()` there does not
  create the global). Declare globals at the top level of the `lib/` file and reset them in
  functions with `name=()`. A test enforces it; the CI runs the suite on a real Bash 4.2.
- Bash 4.2: no `\~` in a `${var/pattern/replacement}` inside double quotes, the backslash
  is kept (`source \~/.bashrc`). Use `cb::tilde` (`lib/install.sh`) to display paths; a test enforces it.
- The framework does **not** use `set -e` / `set -u`: errors are handled explicitly.
  Plugins may enable them in their own `cmd.sh`.
- Quote every expansion unless word splitting is intended (and then say so, e.g.
  `for c in $choices` on a space-separated list).
- Prefer `[[ … ]]` and `(( … ))`. Use `printf`, not `echo`, for anything that may start
  with `-` or contain escapes.
- `local` for every function variable.

## Naming

| Prefix | Use |
|---|---|
| `cb::name` | framework function (public within the framework) |
| `cb::_name` | framework-internal helper of one file |
| `_CB_NAME` | framework global (spec, parse, plugin state) — never in plugins |
| `CB_NAME` | exported variable of the plugin contract |
| `ui::name` / `UI_NAME` | public UI helpers / colours, available to plugins |
| `FLAG_*`, `ARG_*` | parsed values exported to commands |
| `about`, `description`, `flag`, `arg`, `example` | DSL keywords (unprefixed on purpose, only meaningful inside `flags.sh`) |

Command trees are walked only through `cb::children`, `cb::is_child` and `cb::child_dir`
(never `$dir/$name` by hand): extensions merge two directories (decision 0013).

Functions defined in a `flags.sh` for `--choices-from` should be prefixed with `_` and
something plugin-specific (`_cb_enabled_plugins`, `_dyn_envs`) to avoid collisions.

## Output and errors

- Messages (`ui::info/success/warn/error`) go to **stderr**; data and help go to **stdout**.
- Usage errors: `ui::error` + optional hint line + `See '<command> --help'.`, exit 2.
- Never print colours when the stream is not a terminal; honour `NO_COLOR`.
- Error messages say what is wrong **and** how to fix it when possible
  (`→ add 'rename core:x <name>' to the config`).

## Safety

- Anything that changes the user's system (files outside the repo, rc files, config) must be
  **idempotent** and resumable after an interruption: check state first, act in small
  independent steps, rewrite files atomically (temp file + `mv`).
- Ask before destructive, network or rc-file actions (`ui::confirm`); without a terminal,
  `ui::confirm` returns "no" — never auto-accept.
- Prompts only through `ui::confirm` / `ui::ask`, never `read </dev/tty` directly: tests
  override the terminal with the internal `_CB_TTY` (decision 0009).
- Only remove what we created and can identify (e.g. the symlink only if it points to this
  checkout, the rc block only between its markers).

## Commits

Small, focused commits. The message explains *why*. Tests and docs in the same commit as
the change they describe.
