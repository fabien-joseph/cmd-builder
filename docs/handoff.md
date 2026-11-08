# Handoff

Snapshot of the project state for the next agent (any tool, no prior context).
**Rewritten at every wrap-up** ("Fais le point", see `AGENTS.md`) — not a log.

- Date: 2026-11-08
- Last wrap-up commit: `bbef6bc` (merge of PR #2 into `main`)

## What the last session did

1. **Review of `feat/core`** (cloud multi-agent review): 10 findings, all fixed with tests
   (commit `4369631`, merged as PR #1):
   - `init.sh` without a name printed nothing useful and could install/uninstall under
     `~/.config/` itself → now prints usage, exit 2, touches nothing.
   - `--uninstall` dropped the end of an rc file whose end marker was missing → file left
     untouched, warning, exit 1.
   - bash completion lost candidates under `nullglob`/`failglob` → `mapfile`.
   - completion: `--flag=<TAB>` now offers choices; `-5` counts as a positional.
   - `cb::spec_load` returns 0 (doctor flagged valid `flags.sh` ending with `x && flag …`).
   - `self new` wrote a stub `flags.sh` before refusing → checks first.
   - symlinked config kept on enable/disable.
   - Minimum **Bash 4.2** (`declare -g`, `${a[-1]}`) — decision 0008.
   - Last French comment translated; a test checks comments for French.
2. **Owner installed it for real** (`./init.sh mu`). Tab completion did not work in the
   install terminal (the rc file is only read by new terminals). → `init.sh` now prints
   `source ~/.bashrc` (or `~/.zshrc`, by `$SHELL`) at the end (`6dccb71`, PR #2).
3. **Test suite hung when the owner ran it from a terminal**: an install test reached
   `ui::confirm`, which reads `/dev/tty`, and waited invisibly. Agents never saw it (no
   tty). → prompts read `${_CB_TTY:-/dev/tty}`, the suite exports `_CB_TTY=/dev/null`,
   "yes" paths are now tested (`15a3dd5`, PR #2, decision 0009).

## Current state

- `main` = `bbef6bc`, pushed; **all tests pass** (181 with this wrap-up's docs), also under a pseudo-terminal
  (`script -qec ./tests/run.sh /dev/null`).
- Installed on the owner's machine as `mu` (bash, WSL2), completion works.
- Merged branches `feat/core` and `feat/source-hint` still exist locally and on GitHub.
- zsh completion still untested (no zsh on the dev machine).
- Uncommitted: this wrap-up (docs only), to be committed as `docs: session wrap-up`.

## Next steps

1. Owner uses `mu` day to day and writes a first real plugin (`mu self new …`); collect
   feedback.
2. See `docs/roadmap.md` → *Next* (CI on Linux + macOS, zsh completion test,
   `--choices-from` timeout).

## Open questions for the owner

- Delete the merged branches `feat/core` / `feat/source-hint`?
- Install `gh` (`gh auth login`) so agents can open pull requests themselves?

## Owner preferences (learned so far)

- Talks to agents in French, but the whole repository is in English (code, messages, docs).
- Wants to be asked before structural choices; likes proposals with a recommendation.
- Requires idempotent, resumable operations on the user's system, and confirmation before
  updates (`self update` always asks).
- macOS: Bash ≥ 4.2 required, no effort for Bash 3.2.
- Wants everything to stay usable by any AI tool, not only Claude.
- **Git workflow**: work on a feature branch, merged into `main` through a GitHub pull
  request that the owner reviews and merges. The owner now **keeps control of commits'
  push**: give them the git commands (commit message included) rather than pushing.
  `gh` is not installed, so PRs are opened from the link printed by `git push`.
- Pastes several commands at once in the terminal: avoid commands that open a pager or wait
  for input in suggested blocks (`git --no-pager diff`), or tell them to run step by step.
