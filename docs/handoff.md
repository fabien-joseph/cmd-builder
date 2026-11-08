# Handoff

Snapshot of the project state for the next agent (any tool, no prior context).
**Rewritten at every wrap-up** ("Fais le point", see `AGENTS.md`) — not a log.

- Date: 2026-11-08
- Last wrap-up commit: `b9ccfcc` (merge of PR #6 `feat/ci` into `main`)

## What the last session did

1. **Roadmap triaged with the owner** (`docs/roadmap.md`): *Next*, in this order, was CI
   then `self rename`. Accepted but not scheduled: `self doctor` checking `example` lines,
   user plugins extending official ones, repeatable flags, opt-in inherited flags, command
   aliases, hidden commands, `self plugins install <git-url>` (big "not official" warning +
   confirmation), optional `self guide [request]`, zsh completion test, `--choices-from`
   timeout. Kept as an idea: plugins in other languages. Rejected: translating the guide.
2. **CI on GitHub Actions** (PR #6, decision 0011, `.github/workflows/tests.yml`): Linux and
   macOS (Homebrew Bash), both also under a pseudo-terminal; `tests/run.sh` on a real Bash
   4.2 and the Bash 4.1 guard in the official `bash:*` Docker images. All green.
3. **Two real Bash 4.2 bugs found by the CI and fixed** (the project claimed 4.2 support but
   had never run on it):
   - `declare -gA name=()` inside a function does not set the global in 4.2, so commands got
     empty `FLAG_*` / `ARG_*`. Arrays now declared at the top level of `lib/spec.sh` and
     `lib/parse.sh`.
   - `"${rc/#$HOME/\~}"` keeps the backslash in 4.2 (`source \~/.bashrc`): `init.sh` uses a
     `tilde` helper.
   Both are rules in `docs/conventions.md`, each enforced by a static test (mutation-checked).
4. macOS: the test sandbox uses the physical path of `mktemp -d` (`/var` → `/private/var`).
5. Guide evaluations: a Claude Code user-level agent `~/.claude/agents/chat-ai-simulator.md`
   (tools `Read, Write`, no shell) was created for the next evaluation rounds (method in
   `docs/testing.md`). It is outside the repository, available from a new session.
6. `gh` is now installed and logged in (`fabien-joseph`, ssh).

## Current state

- `main` = `b9ccfcc`; **261 tests pass** locally (also under a pseudo-terminal); CI green on
  the three jobs (260 in the Bash 4.2 container: the commit check of the docs is skipped
  there, most likely because git refuses the ownership of the mounted checkout).
- Branch `docs/wrap-up-ci`: this wrap-up (docs only).
- Merged branch `feat/ci` still exists locally and on GitHub.
- Installed on the owner's machine as `mu` (bash, WSL2).

## Next steps

1. **`self rename <new-name>`** (roadmap *Next*): rename the root command without losing the
   config. Today `./init.sh xx` + `./init.sh --uninstall mu` works but the new install starts
   with an empty `~/.config/xx/config`. To move: `~/.local/bin/<name>` link,
   `~/.config/<name>/` (config + completion files, regenerated for the new name), the rc
   blocks `# >>> cmd-builder: <name> >>>` in `~/.bashrc` / `~/.zshrc`. Idempotent and
   resumable (rule 4), confirmation (rule 5), a decision record, tests with `zz`-style names
   in the sandbox like the `init.sh` tests. Probably share code with `init.sh` rather than
   duplicate it (to be decided with the owner).
2. Then the *Accepted* list of the roadmap, in an order to agree with the owner.

## Open questions for the owner

- Delete the merged branch `feat/ci` (and `docs/wrap-up-ci` once merged)?
- `self rename`: a `self` command calling shared code with `init.sh`, or `./init.sh --rename
  <old> <new>`? (Recommendation: `self rename`, since `self` already knows its own name.)

## Owner preferences (learned so far)

- Talks to agents in French, but the whole repository is in English (code, messages, docs).
  Commands generated for the owner's own plugins also default to English texts.
- Wants to be asked before structural choices; likes proposals with a recommendation, and
  short numbered questions they can answer one by one.
- Requires idempotent, resumable operations on the user's system, and confirmation before
  updates (`self update` always asks).
- macOS: Bash ≥ 4.2 required, no effort for Bash 3.2.
- Wants everything to stay usable by any AI tool, not only Claude, including AI chats
  with no access to the machine (hence `self guide`).
- Cares about docs never drifting from the code: prefers generated content and tests that
  execute the examples over hand-maintained copies.
- Likes empirical checks: test with weak models, run their output for real, report
  honestly what failed. Sub-agents playing an external AI must never access local services
  (databases...): only the evaluator does.
- **Git workflow** (updated this session): work on a feature branch; the **agent commits,
  pushes and opens the pull request** with `gh`; **the owner reviews and merges**. Wait for
  a green CI before saying a PR is ready. `gh pr edit` fails with gh 2.46 ("Projects
  (classic) is being deprecated"): update a PR body with
  `gh api -X PATCH repos/fabien-joseph/cmd-builder/pulls/<n> -F body=@<file>`.
- Pastes several commands at once in the terminal: avoid commands that open a pager or wait
  for input in suggested blocks (`git --no-pager diff`), or tell them to run step by step.
