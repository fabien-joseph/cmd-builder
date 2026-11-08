# Handoff

Snapshot of the project state for the next agent (any tool, no prior context).
**Rewritten at every wrap-up** ("Fais le point", see `AGENTS.md`) — not a log.

- Date: 2026-11-08
- Last wrap-up commit: `f09ef9f`
  (the work listed below was committed on `feat/core`, on top of this commit)

## What the last session did

First session: the project was designed with the owner and built from scratch.

- Core framework in `lib/`: routing by directory, `flags.sh` DSL, generated `--help`,
  parser with validation, bash/zsh completion engine.
- Built-ins `self update | new | plugins [enable|disable] | doctor | completion`.
- Example official plugin `core/system` (`system info [-s]`).
- `init.sh <name>` install and idempotent `init.sh --uninstall <name>`.
- Dynamic choices `--choices-from` / `--strict`, with bash completion fixed for `:` in words.
- Contributor docs for any AI agent: `AGENTS.md` (+ pointers `CLAUDE.md`, `GEMINI.md`,
  `.github/copilot-instructions.md`), `docs/`, 7 decision records.
- `tests/run.sh`: end-to-end tests + doc consistency checks (`--docs` for docs only).

## Current state

- All tests pass (`./tests/run.sh`).
- All the work is committed on branch **`feat/core`** (not pushed, not merged into `main`),
  so the owner can review it (`/ultrareview`) before merging.
- Not installed on the owner's real account yet (`./init.sh <name>` never run outside tests).
- zsh completion is untested (zsh not available on the dev machine).

## Next steps

1. Owner reviews `feat/core`; fix the findings, then merge into `main` and push.
2. Owner to try a real install (`./init.sh mu`) and give feedback.
3. See `docs/roadmap.md` → *Next*.

## Owner preferences (learned so far)

- Talks to agents in French, but the whole repository is in English (code, messages, docs).
- Wants to be asked before structural choices; likes proposals with a recommendation.
- Requires idempotent, resumable operations on the user's system, and confirmation before
  updates (`self update` always asks).
- macOS: Bash ≥ 4 required, no effort for Bash 3.2.
- Wants everything to stay usable by any AI tool, not only Claude.
