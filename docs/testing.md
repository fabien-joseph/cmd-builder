# Testing

## Running

```bash
./tests/run.sh
```

Exit code 0 when everything passes. Output lists only failures, then a summary.
It runs two suites:

| Suite | File | What it checks |
|---|---|---|
| End-to-end | `tests/run.sh` | real invocations of the installed command: routing, help, parsing, errors, plugins, config, generator, completion |
| Doc consistency | `tests/run.sh` (function `doc_checks`) | that the docs mention everything the code exposes (see below) |

Run only the doc checks with `./tests/run.sh --docs` (fast, no temp copy).

## How the end-to-end suite works

1. Copies `main.sh`, `lib/`, `builtin/`, `core/`, `templates/` into a temp directory
   (the real `plugins/` is never touched).
2. Creates an isolated `HOME`, `XDG_CONFIG_HOME` and `PATH`, with a symlink `tt` → `main.sh`
   (so the root command is named `tt`), and sets `NO_COLOR=1`.
3. Creates fixture plugins in the temp `plugins/`, runs assertions, deletes everything on exit.

### Writing a test

```bash
check "<description>" "<shell command>" "<expected substring of stdout+stderr>"
```

- The command is run with `eval`, so pipes, `cd` and `;` work.
- To test an exit code: `check "…" "status 'tt demo greet'" "2"`.
- To test absence: `check "…" "tt … | grep -c something" "0"`.
- Create fixtures with heredocs under `$P` (the temp `plugins/`) and remove them at the end
  of your block so later tests are not affected.
- Interactive prompts (`ui::confirm`, `ui::ask`) read `/dev/tty`, which exists when the
  suite is run from a terminal: a prompt would then wait, invisibly, for an answer. The
  suite exports `_CB_TTY=/dev/null` (internal override of `/dev/tty`), so every prompt
  answers "no" (or its default). To test the "yes" path, point it to a file:
  `echo y >"$TMP/yes"; check "…" "_CB_TTY='$TMP/yes' <command>" "…"`.
- Check a change does not hang from a terminal: `script -qec ./tests/run.sh /dev/null`.
- To test the bash adapter as an interactive shell would run it, use
  `bashcomp "<shopt options>" "<command line>"` (prints `COMPREPLY` as `[a][b]`), e.g.
  `check "…" "bashcomp nullglob 'tt demo '" "[greet]"`.
- `init.sh` is copied into the sandbox too (`$TMP/app/init.sh`); run it with an
  unused name (e.g. `zz`) so it does not affect the `tt` install used by other tests.
- The Bash version guard is tested by sourcing an entry script after setting
  `BASH_VERSION=4.1.17`.

Group new tests with the related section (`# Parsing`, `# Completion`, …).

## Doc consistency checks (`doc_checks` in `tests/run.sh`)

They extract facts from the code and fail when the docs do not mention them:

| Fact (from code) | Must appear in |
|---|---|
| DSL keywords (`about`, `flag`, …) and their options (`--default`, `--choices-from`, …) — `lib/spec.sh` | `docs/plugin-authoring.md` |
| Exported `CB_*` variables — `main.sh`, `lib/router.sh` | `docs/plugin-authoring.md` |
| `ui::` helpers — `lib/ui.sh` | `docs/plugin-authoring.md` |
| `self` commands — `builtin/self/` | `docs/architecture.md` and `README.md` |
| Config directives — `lib/config.sh` | `docs/architecture.md` and `README.md` |
| Files in `lib/` | `docs/architecture.md` |
| Decision records `docs/decisions/NNNN-*.md` | `docs/decisions/README.md` |
| Relative links in `AGENTS.md` and `docs/` | the target file exists |
| `Last wrap-up commit` marker | present in `docs/handoff.md`, and an existing commit (when run in a git checkout) |

When a check fails, document the new thing — do not weaken the check.

## Not covered yet

- zsh completion (`templates/completion.zsh`) is not exercised automatically (zsh was not
  available when it was written). Test it manually in zsh before changing it.
- `self update` against real remotes: tested manually with local bare repositories
  (see the recipe in `docs/roadmap.md`).
- macOS: never run in CI.
