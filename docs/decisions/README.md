# Decision records

Why the project is the way it is. One file per decision, numbered, never renumbered.
**Read the relevant record before proposing to change a structural choice**; if you still
think it should change, write a new record that supersedes the old one (and mark the old one
`Superseded by NNNN`).

| # | Decision | Status |
|---|---|---|
| [0001](0001-one-directory-per-command.md) | One directory per command, `flags.sh` + `cmd.sh` side by side | Accepted |
| [0002](0002-core-and-user-plugins.md) | Official plugins in `core/`, user plugins in a git-ignored `plugins/` | Accepted |
| [0003](0003-name-conflicts.md) | User plugin shadows core plugin; `rename` / `disable` in config; `self` reserved | Accepted (extensions added by 0013) |
| [0004](0004-require-bash-4.md) | Require Bash ≥ 4, pure Bash, no dependencies | Accepted (minimum amended to 4.2 by 0008) |
| [0005](0005-values-as-environment-variables.md) | Parsed values passed as `FLAG_*` / `ARG_*` env vars to a fresh process | Accepted |
| [0006](0006-dynamic-choices-not-strict-by-default.md) | `--choices-from` suggests only, `--strict` to validate | Accepted |
| [0007](0007-idempotent-uninstall.md) | Uninstall in `init.sh`, as independent idempotent steps | Accepted |
| [0008](0008-require-bash-4-2.md) | Minimum Bash version raised to 4.2 (amends 0004) | Accepted |
| [0009](0009-overridable-prompt-input.md) | Prompts read `${_CB_TTY:-/dev/tty}`; tests set it to `/dev/null` | Accepted |
| [0010](0010-ai-guide-built-from-the-docs.md) | `self guide` prints an AI guide built from a template + `plugin-authoring.md`, example run by tests | Accepted |
| [0011](0011-ci.md) | CI on GitHub Actions: Linux, macOS (Homebrew Bash), Bash 4.2 and the 4.1 guard in Docker | Accepted |
| [0012](0012-self-rename.md) | `self rename` (resumable, one confirmation, `--keep-old`); install code shared with `init.sh` in `lib/install.sh` | Accepted |
| [0013](0013-extensions-of-official-plugins.md) | `plugins/+<plugin>/` adds commands to an official plugin (`+` at every level), inactive if it is not active | Accepted |

## Template

Copy to `NNNN-short-title.md`:

```markdown
# NNNN. Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context
What problem, what constraints.

## Decision
What we do.

## Alternatives considered
What we rejected, and why.

## Consequences
What becomes easier, harder, or must be maintained.
```
