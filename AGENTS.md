# AGENTS.md

Entry point for AI coding agents (and humans) working on **cmd-builder**.
This file follows the [AGENTS.md](https://agents.md) convention. Tool-specific files
(`CLAUDE.md`, `GEMINI.md`, `.github/copilot-instructions.md`) only point here: keep all
guidance in this file and in `docs/`, never in the tool-specific files.

## What this project is

cmd-builder is a **pure Bash framework to build and manage personal Linux commands**.
A user installs it under a root command name of their choice (`./init.sh mu`), then every
directory under `core/` or `plugins/` becomes a subcommand (`mu system info`). Each command
declares its flags and arguments in a small DSL (`flags.sh`); the framework generates
`--help`, argument parsing, validation and bash/zsh completion. Built-in `mu self …`
commands handle updates, plugin management, scaffolding and diagnostics.

**Everything in the repository is in English**: code, identifiers, comments, user-facing
messages, `--help`, README.md and docs. The owner talks to agents in French, though.

## Repository map

```
init.sh              install / uninstall (./init.sh <name>, ./init.sh --uninstall <name>)
main.sh              entry point, symlinked as ~/.local/bin/<name>
lib/                 the framework (sourced, never executed directly; lib/run.sh is the exception)
builtin/self/        built-in commands "<name> self …", written with the framework itself
core/                official plugins, versioned in this repo (id core:<plugin>)
plugins/             user plugins, git-ignored, often their own git repos (id user:<plugin>)
templates/           completion script templates and the AI guide of "self guide" (placeholders __CB_*__)
tests/run.sh         all tests: end-to-end + doc consistency checks (--docs: docs only)
.github/workflows/   CI (GitHub Actions): Linux, macOS, Bash 4.2 / 4.1 (decision 0011)
docs/                contributor documentation (English); plugin-authoring.md also ships in "self guide"
README.md            user documentation
```

## Non-negotiable rules

1. **Pure Bash ≥ 4.2, no dependencies.** Only Bash builtins and POSIX tools present on Linux
   and macOS (`sed`, `sort`, `grep`, `git` for updates). No `jq`, `yq`, `python`, GNU-only
   flags (`readlink -f`, `sed -i` without care), no `bash` ≥ 5 features.
   macOS users must install Bash 4.2+ — see [decisions 0004](docs/decisions/0004-require-bash-4.md) and [0008](docs/decisions/0008-require-bash-4-2.md).
2. **The plugin contract is a public API.** `flags.sh` DSL, the `FLAG_*` / `ARG_*` / `CB_*`
   environment variables, `"$@"`, the `ui::` helpers and the directory layout are used by
   plugins we do not control. Never break them; extend them compatibly.
3. **Never touch `plugins/` content** from framework code except through explicit user
   commands (`self new`, `self update`). It belongs to the user.
4. **Anything that modifies the user's system must be idempotent** and safe to re-run after
   an interruption (see `init.sh`, [decision 0007](docs/decisions/0007-idempotent-uninstall.md)).
5. **Destructive or network actions ask for confirmation** (`ui::confirm`), and without a
   terminal the answer is always "no".
6. **Every behaviour change comes with tests** in `tests/run.sh`.
7. **Record architectural choices** as a new file in `docs/decisions/`.

## Commands

```bash
./tests/run.sh                    # all tests: end-to-end + doc consistency (must stay green)
bash -n lib/*.sh main.sh init.sh  # syntax check
script -qec ./tests/run.sh /dev/null  # Linux: same under a pseudo-terminal, must not hang on a prompt
gh run list / gh run view --log-failed   # CI results (GitHub Actions, decision 0011)
```

Try changes without touching your real setup — use an isolated `HOME`:

```bash
T=$(mktemp -d); mkdir -p "$T/bin"; ln -s "$PWD/main.sh" "$T/bin/mu"
HOME=$T XDG_CONFIG_HOME=$T/.config PATH=$T/bin:$PATH mu self doctor
```

Anything you create under `plugins/` while testing must be removed afterwards
(the test suite works on a temporary copy and cleans up by itself).

## Before you finish a task

- [ ] `./tests/run.sh` passes (it also checks that docs mention every DSL option,
      `CB_*` variable, `ui::` helper, `self` command, config directive and `lib/` file).
- [ ] CI is green on the pull request (Linux, macOS, Bash 4.2), see `docs/testing.md`.
- [ ] New behaviour has tests.
- [ ] Docs updated: `docs/` **and** `README.md` if users see the change.
- [ ] Plugin contract or `self new` changed → the guide still reads well:
      `mu self guide` (built from `templates/ai-guide.md` + `docs/plugin-authoring.md`).
- [ ] A new `docs/decisions/NNNN-*.md` exists if you made an architectural choice, and it is
      listed in `docs/decisions/README.md`.
- [ ] `docs/roadmap.md` updated (move done items, add discovered follow-ups).
- [ ] No test leftovers in `plugins/`.

## Starting a session

You may have no memory of previous sessions (new tool, cleared context). Before working:

1. Read **[docs/handoff.md](docs/handoff.md)**: current state, work in progress, next steps,
   open questions. It is written for an agent with zero context.
2. Run `git status --short` and `git log --oneline -10` to see what changed since.
3. Read the docs relevant to your task (table below).

## Session wrap-up — when the owner says "Fais le point"

The owner ends each session with **"Fais le point"** (French for "take stock") and will
then usually clear the context. Your job is to make sure **nothing learned in the session is
lost**: the next agent (any tool, any model) must be able to continue from the files alone.

1. **Collect what changed.** Read the `Last wrap-up commit` in `docs/handoff.md`, then:
   ```bash
   git log --oneline <sha>..HEAD     # commits since the last wrap-up
   git diff --stat <sha>             # all changes since then, committed or not
   git status --short                # uncommitted work
   ```
   If the sha is missing or unknown, review the whole history. Also use the conversation
   itself: decisions, rejected ideas, owner preferences and open questions often never
   reach the code.
2. **Update every doc concerned** by those changes:

   | What changed | Update |
   |---|---|
   | `lib/`, `main.sh`, routing, globals, exit codes, completion, config, install layout | `docs/architecture.md` |
   | DSL, `FLAG_*` / `ARG_*` / `CB_*`, `ui::` helpers, plugin layout | `docs/plugin-authoring.md` **and** `README.md` |
| How an AI should answer users, the worked example, `self new` | `templates/ai-guide.md` (output of `self guide`) |
   | A coding rule, a portability constraint, a naming convention | `docs/conventions.md` |
   | Test infrastructure or how to test something | `docs/testing.md` |
   | A structural choice (taken *or* rejected, even only in discussion) | new `docs/decisions/NNNN-*.md` + index |
   | Repository map, rules, commands, this procedure | `AGENTS.md` |
   | Anything | `docs/roadmap.md` (done / next / ideas / limitations) |

3. **Rewrite `docs/handoff.md`** entirely (it is a snapshot, not a log): date, new
   `Last wrap-up commit` (= current `HEAD`), what this session did, current state including
   uncommitted work, next steps, open questions for the owner.
4. **Run `./tests/run.sh`**: it must pass (doc checks included).
5. **Report to the owner in French**: which files were updated and why, then *propose* a
   commit (`docs: session wrap-up`). Do not commit without their approval.

Tool-specific memories (if your tool has any) are not a substitute: everything that matters
must be in these files.

## Where to read next

| Read this | When |
|---|---|
| [docs/handoff.md](docs/handoff.md) | At the start of every session |
| [docs/architecture.md](docs/architecture.md) | Before changing anything in `lib/`, `main.sh` or `builtin/` |
| [docs/plugin-authoring.md](docs/plugin-authoring.md) | Writing a command or changing the DSL / plugin contract |
| [docs/conventions.md](docs/conventions.md) | Before writing any code |
| [docs/testing.md](docs/testing.md) | Writing or running tests |
| [docs/decisions/](docs/decisions/README.md) | Before proposing a structural change ("why is it like this?") |
| [docs/roadmap.md](docs/roadmap.md) | Looking for what to do next, or known limitations |
