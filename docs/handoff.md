# Handoff

Snapshot of the project state for the next agent (any tool, no prior context).
**Rewritten at every wrap-up** ("Fais le point", see `AGENTS.md`) — not a log.

- Date: 2026-11-08
- Last wrap-up commit: `284d249` (merge of PR #13 `fix/ui-symbols` into `main`)

## What the last session did

Seven pull requests (#8 to #13), all merged by the owner, CI green on each:

1. **`self rename <name> [--keep-old]`** (PR #8, decision 0012): moves the link, the
   config, the completion and the rc blocks (replaced in place) to a new root name, after
   one confirmation, resumable (old link last). `--keep-old` keeps the old name, its config
   becoming a symlink to the new one. The install-layout code moved from `init.sh` to
   `lib/install.sh`, shared by both.
2. **`self doctor` checks every `example`** like the parser would (warnings), and the CI
   moved to `actions/checkout@v5` (PR #9). **`self guide [request]`** appends the request
   at the end of the guide, to paste everything as one message.
3. **Extensions of official plugins** (PR #10, decision 0013): `plugins/+system/disk/` adds
   `mu system disk` next to the official `mu system info`; `+` at every level for official
   groups. The owner wanted the extension visible in the directory name (rejected: a root
   without files, an `extends` keyword, a config directive, `system.extend`, `system@core`).
   `self new system disk` creates it. All tree walks go through `cb::children` /
   `cb::is_child` / `cb::child_dir`.
4. **`ui::select`** (PR #11): arrow-key menu in pure Bash (the owner's previous project
   needed `fzf` for that).
5. **Plugin dependencies** (PR #11, decision 0014): `requires <tool> [--optional]
   [--apt|--dnf|--pacman|--zypper|--apk|--brew <package|->]` in `flags.sh`, checked before
   running; `self deps`, `self deps install [--all]`, `self deps update`,
   `self deps managers [add|remove]`; `package-manager <pm>` config lines, asked once by
   `init.sh` (suggestion = detected manager). Restrictive by the owner's choice: only the
   configured managers, always after a confirmation. Official plugins never use `requires`
   (test).
6. **AI guide reviewed** against all of this (PR #12): it still advised
   `command -v … || ui::die` and would have written extension files in the wrong place.
   Fixed and pinned by tests.
7. **Status symbols** (PR #13): `✔ ✖ ⚠` overlapped the next character in Windows Terminal
   (emoji variants, two columns wide); now `✓ ✗ !`, enforced by a test.

## Current state

- `main` = `284d249`; **442 tests pass** locally (also under a pseudo-terminal); CI green.
- Branch `docs/wrap-up-features`: this wrap-up (docs only).
- Merged branch `fix/ui-symbols` still exists locally and on GitHub (deleting branches
  needs the owner's explicit go each time).
- Installed on the owner's machine as `mu` (bash, WSL2, Windows Terminal), updated with
  `git pull` only: that is enough (the link points to the checkout; completion files were
  checked identical). The owner added `package-manager apt` to the config afterwards.
- The user-level agent `~/.claude/agents/chat-ai-simulator.md` (tools `Read, Write`) is
  available for guide evaluations (method in `docs/testing.md`). The guide has **not** been
  evaluated with it since extensions and `requires`.

## Next steps

1. **Global review** (owner's plan): after a `/clear`, the owner starts a session (Opus,
   max effort) asking the agent to act as a software architect leading sub-agents and to
   review every aspect of the project (architecture, plugin contract, correctness,
   security, idempotence, portability, performance, CLI UX, tests, CI, docs, AI guide with
   a practical evaluation, maintainability, product). Review only: report in the
   scratchpad + a correction plan in batches, to validate with the owner before any change.
2. Then agree on the order of the *Accepted* list of `docs/roadmap.md` and of the review's
   plan. Suggested earlier: repeatable flags, then opt-in inherited flags (both extend the
   DSL), then aliases + hidden commands together.

## Open questions for the owner

- Delete the merged branch `fix/ui-symbols` (and `docs/wrap-up-features` once merged)?
- "Did you mean" for a mistyped subcommand after a command that has its own `cmd.sh`
  (`mu self deps manager`): small fix, left for the review.

## Owner preferences (learned so far)

- Talks to agents in French, but the whole repository is in English (code, messages, docs).
  Commands generated for the owner's own plugins also default to English texts.
- Wants to be asked before structural choices; likes proposals with a recommendation, and
  short numbered questions they can answer one by one (`AskUserQuestion` works well, with
  previews for naming choices). Sometimes rejects all options and proposes their own idea.
- Requires idempotent, resumable operations on the user's system, and confirmation before
  updates or installs. Prefers **restrictive** designs (only what the user configured).
- macOS: Bash ≥ 4.2 required, no effort for Bash 3.2.
- Wants everything to stay usable by any AI tool, not only Claude, including AI chats
  with no access to the machine (hence `self guide`), and wants the guide kept exact after
  every feature.
- Cares about docs never drifting from the code: prefers generated content and tests that
  execute the examples over hand-maintained copies.
- Likes empirical checks: test with weak models, run their output for real, report
  honestly what failed. Sub-agents playing an external AI must never access local services
  (databases...): only the evaluator does.
- Things should be readable in the tree itself (the `+` of extensions).
- Uses Windows Terminal on WSL2: avoid characters with an emoji variant in output.
- **Git workflow**: work on a feature branch; the **agent commits, pushes and opens the
  pull request** with `gh`; **the owner reviews and merges**. Wait for a green CI before
  saying a PR is ready (`gh run watch <id> --exit-status`). Several features may share one
  PR (one commit each). `gh pr edit` fails with gh 2.46 ("Projects (classic) is being
  deprecated"): update a PR body with
  `gh api -X PATCH repos/fabien-joseph/cmd-builder/pulls/<n> -F body=@<file>`.
  Delete merged branches only when the owner explicitly says so.
- Pastes several commands at once in the terminal: avoid commands that open a pager or wait
  for input in suggested blocks (`git --no-pager diff`), or tell them to run step by step.
