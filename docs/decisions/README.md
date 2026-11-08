# Decision records

Why the project is the way it is. One file per decision, numbered, never renumbered.
**Read the relevant record before proposing to change a structural choice**; if you still
think it should change, write a new record that supersedes the old one (and mark the old one
`Superseded by NNNN`).

| # | Decision | Status |
|---|---|---|
| [0001](0001-one-directory-per-command.md) | One directory per command, `flags.sh` + `cmd.sh` side by side | Accepted |
| [0002](0002-core-and-user-plugins.md) | Official plugins in `core/`, user plugins in a git-ignored `plugins/` | Accepted |
| [0003](0003-name-conflicts.md) | User plugin shadows core plugin; `rename` / `disable` in config; `self` reserved | Accepted |
| [0004](0004-require-bash-4.md) | Require Bash ≥ 4, pure Bash, no dependencies | Accepted (minimum amended to 4.2 by 0008) |
| [0005](0005-values-as-environment-variables.md) | Parsed values passed as `FLAG_*` / `ARG_*` env vars to a fresh process | Accepted |
| [0006](0006-dynamic-choices-not-strict-by-default.md) | `--choices-from` suggests only, `--strict` to validate | Accepted |
| [0007](0007-idempotent-uninstall.md) | Uninstall in `init.sh`, as independent idempotent steps | Accepted |
| [0008](0008-require-bash-4-2.md) | Minimum Bash version raised to 4.2 (amends 0004) | Accepted |

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
