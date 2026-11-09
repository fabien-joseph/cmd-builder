# 0014. Dependencies of user plugins: `requires`, `self deps`, chosen package managers

- Status: Accepted
- Date: 2026-11-08

## Context
Personal commands sometimes need a tool that is not part of the system (the owner's
example: `fzf`, for menus). The framework and the official plugins must keep running on
Bash and POSIX tools only (rule 1), but user plugins should be able to say what they need,
and the user should be able to install and update it easily (a security fix in one of these
tools must be one command away).

## Decision
- **Declaration in `flags.sh`**, per command: `requires <tool> [--optional]
  [--apt|--dnf|--pacman|--zypper|--apk|--brew <package|->]`. The package defaults to the
  tool name; `-` means "not packaged for that manager". Official plugins and `self` never
  use it (a test enforces it).
- **Checked before running** (after parsing, so `--help` and completion still work): a
  missing required tool stops the command with `Install: <name> self deps install`
  (exit 1). `--optional` is not checked; the plugin writes its degraded behaviour itself
  with `command -v`.
- **Restrictive package managers**: a fixed supported list (apt, dnf, pacman, zypper, apk,
  brew); only the ones in the config (`package-manager <pm>` lines, in order of
  preference) are ever used. `init.sh` asks once, suggesting the best detected one
  (`ui::select`; without a terminal the suggestion is kept, it is only a preference);
  `self deps install` asks the same question if none is configured.
  `self deps managers add|remove` changes the list.
- **`self deps`** lists tools, state, package and the commands using them;
  **`self deps install [--all]`** and **`self deps update`** show the exact commands
  (`sudo` unless root, never for brew), ask once (no terminal = no), then run them. The
  package manager's own prompts are kept (no `-y`). A tool is installed with the first
  configured manager that packages it. `self update` only reminds the user of
  `self deps update` (no sudo there).
- Presence only, no versions: an executable in `PATH` (`type -P`, since 2026-11-09:
  `command -v` also accepted shell keywords such as `time`, builtins and functions).
- **`ui::select`**, an arrow-key menu in pure Bash, so that the most common reason to need
  `fzf` disappears.

## Alternatives considered
- *A dependency file per plugin*: further from the code that needs the tool.
- *Warning and running anyway / installing on the fly when a tool is missing*: a
  half-working command, or `sudo` in the middle of a command run.
- *Auto-detecting the package manager at every run*: not restrictive, surprising on
  machines with several (apt + brew on Linux).
- *Minimal versions (`--min`)*: needs parsing every tool's `--version`; kept as an idea.
- *pip / cargo / npm / install scripts*: later, if needed, under the same restrictions.
- *`ui::select` using `fzf` when present*: two behaviours depending on the machine.

## Consequences
New DSL keyword and options (plugin contract, documented and checked by the doc tests),
new config directive, new `ui::` helper. Package-manager command lines live in
`cb::pm_commands` and are tested without running any real package manager.
