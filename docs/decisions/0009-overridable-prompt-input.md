# 0009. Prompt input overridable for tests (`_CB_TTY`)

- Status: Accepted
- Date: 2026-11-08

## Context
`ui::confirm` and `ui::ask` read the answer from `/dev/tty`, so that piped stdin never
answers a question by accident, and "no terminal" always means "no" (rule 5 of
`AGENTS.md`). The test suite assumed it never has a terminal. That holds for agents, but
not when the owner runs `./tests/run.sh` from their terminal: a test reaching a prompt
(output captured by `check`) then waited forever on an invisible question. This happened
with the `init.sh` install tests.

## Decision
Prompts read `${_CB_TTY:-/dev/tty}`. `_CB_TTY` is **internal** (the `_CB_` prefix, not part
of the plugin contract, not documented for users). `tests/run.sh` exports
`_CB_TTY=/dev/null`, so every prompt answers "no" (or its default) whether or not a
terminal exists. Pointing it to a file containing `y` tests the "yes" path.

## Alternatives considered
- *`setsid` to detach the suite from the terminal*: util-linux only, missing on macOS.
- *`</dev/null` on the suite*: does not help, prompts read `/dev/tty`, not stdin.
- *A public variable like `CB_ASSUME_YES` / `CB_NO_PROMPT`*: extends the public API and makes
  auto-accepting destructive actions easy, against rule 5. Not wanted for now.

## Consequences
New prompts must go through `ui::confirm` / `ui::ask` (never `read </dev/tty` directly).
Check that the suite does not hang from a terminal with `script -qec ./tests/run.sh /dev/null`.
