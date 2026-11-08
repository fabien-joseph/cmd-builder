# Handoff

Snapshot of the project state for the next agent (any tool, no prior context).
**Rewritten at every wrap-up** ("Fais le point", see `AGENTS.md`) — not a log.

- Date: 2026-11-08
- Last wrap-up commit: `e94bd9c` (merge of PR #4 `feat/self-guide` into `main`)

## What the last session did

1. **Explained the project to the owner** (French): `CB_*` variables, `ui::` helpers,
   `--choices-from`, `self new` (`plugins/` by default, `core/` with `--core`).
2. **New built-in `self guide`** (`2e411bd`, PR #4, decision 0010). It prints a Markdown
   guide for an AI chat **without access to the machine** (Gemini, Copilot Web, ChatGPT…):
   the user attaches it, describes a command, and the AI answers step by step
   (`mu self new …`, then paste-ready `cat > '<abs path>' <<'EOF'` blocks, then how to try
   it). `-o <file>` writes a file (confirmation before overwriting), `--no-commands` leaves
   out the list of the user's commands.
   - Built at run time from `templates/ai-guide.md` (AI instructions, rules, worked
     example) and the part of `docs/plugin-authoring.md` between `<!-- guide:begin -->`
     and `<!-- guide:end -->`: the reference is never duplicated.
   - Filled in: root name, install path, system (`uname -sr`, WSL / macOS flagged), Bash
     version, existing commands with their state, help of `self new`.
3. **Anti-drift tests** for the guide (owner's concern): `contract_checks` runs the same
   DSL / `CB_*` / `ui::` checks on the generated guide as on the docs; the worked example's
   bash blocks are **extracted from the generated guide and run**; the complete `flags.sh`
   example of `plugin-authoring.md` (`flags-example` / `flags-values` markers) is installed
   and must receive exactly the documented values. Mutation-checked (they do fail).
4. **`docs/plugin-authoring.md` completed**: required / optional fields table, complete
   commented `flags.sh`, missing rules (bool restrictions, `--choices` split on spaces,
   empty optional args, `ARG_*` name conversion, Bash quoting).
5. **Guide rules decided with the owner**: ask questions first when the request is
   unclear (one numbered list, a default for each); talk in the user's language but write
   the files' texts **in English** unless explicitly asked otherwise; assume nothing beyond
   the *Setup* table; never `sudo mu …` (use `sudo` inside `cmd.sh`, as an option when it
   only adds details); never shadow an official plugin (suggest another plugin name,
   `--core` only as an explained alternative); `example` lines use declared flags only;
   settings in a file under `$CB_CONFIG_DIR` covering every choice, `chmod 600` with
   secrets; at least one edge case in the *Try it* step.
6. **Evaluated the guide with real models** (owner request), 3 rounds, ~25 sub-agents,
   mostly Haiku (the smallest available), some Sonnet. Each answer was run in an isolated
   copy. Round 3: 5 Spring JPA entity generators run against real PostgreSQL 17 and
   MariaDB 11.8 started without root from Debian packages, every entity compiled with
   `javac` + JPA / Hibernate / Lombok / Spring Data jars. Every generated command worked;
   each round's weaknesses became the rules of point 5. Method in `docs/testing.md`.
   Sub-agents never had access to the databases (owner insisted: only the evaluator does).

## Current state

- `main` = `e94bd9c`, pushed; **257 tests pass**, also under a pseudo-terminal.
- Branch `docs/wrap-up-self-guide`: this wrap-up (docs only), uncommitted.
- Installed on the owner's machine as `mu` (bash, WSL2). `self guide` not yet tried by the
  owner with a real external AI.
- Merged branches still around: `feat/core`, `feat/source-hint`, `docs/wrap-up`,
  `feat/self-guide` (local and/or on GitHub).
- zsh completion still untested (no zsh on the dev machine).

## Next steps

1. Owner tries `mu self guide -o ~/mu-guide.md` with a real external AI and a real need.
2. Candidates from `docs/roadmap.md` *Ideas* that came out of the evaluation:
   `self doctor` validating `example` lines against their `flags.sh`; letting a user plugin
   extend an official one (`plugins/system/disk/` → `mu system disk`).
3. Roadmap *Next*: CI on Linux + macOS, zsh completion test, `--choices-from` timeout.

## Open questions for the owner

- Delete the merged branches (`feat/core`, `feat/source-hint`, `docs/wrap-up`,
  `feat/self-guide`)?
- Install `gh` (`gh auth login`) so agents can open pull requests themselves?
- For future guide evaluations: use a sub-agent type without shell access for strict
  isolation (two Haiku agents ran a harmless `echo` despite the instructions)?
- Promote one of the two evaluation ideas above to *Next*?

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
  honestly what failed.
- **Git workflow**: work on a feature branch, merged into `main` through a GitHub pull
  request that the owner reviews and merges. The owner **keeps control of commits and
  push**: give them the git commands (commit message included) rather than committing.
  `gh` is not installed, so PRs are opened from the link printed by `git push`.
- Pastes several commands at once in the terminal: avoid commands that open a pager or wait
  for input in suggested blocks (`git --no-pager diff`), or tell them to run step by step.
