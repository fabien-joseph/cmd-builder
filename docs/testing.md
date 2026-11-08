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

1. Copies `main.sh`, `init.sh`, `lib/`, `builtin/`, `core/`, `templates/` and
   `docs/plugin-authoring.md` (embedded by `self guide`) into a temp directory
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
| `guide:begin` / `guide:end` markers (part embedded by `self guide`), `flags-example` / `flags-values` markers (complete example, run by the tests) | `docs/plugin-authoring.md` |
| `self` commands — `builtin/self/` | `docs/architecture.md` and `README.md` |
| Config directives — `lib/config.sh` | `docs/architecture.md` and `README.md` |
| Files in `lib/` | `docs/architecture.md` |
| Decision records `docs/decisions/NNNN-*.md` | `docs/decisions/README.md` |
| Relative links in `AGENTS.md` and `docs/` | the target file exists |
| `Last wrap-up commit` marker | present in `docs/handoff.md`, and an existing commit (when run in a git checkout) |

When a check fails, document the new thing — do not weaken the check.

## The guide of `self guide`

The `# Guide for AI assistants` block of the end-to-end suite generates the guide and:

- runs `contract_checks` on it: the same DSL / `CB_*` / `ui::` facts as for
  `docs/plugin-authoring.md` must appear in the guide;
- extracts the ```` ```bash ```` blocks between `<!-- example:begin -->` and
  `<!-- example:end -->` of the **generated** guide and runs them in the sandbox, then
  checks the outputs. If you change the worked example of `templates/ai-guide.md`, keep it
  runnable as it is (no placeholder output, no prompt) and update the expected outputs.
- extracts the complete `flags.sh` example of `docs/plugin-authoring.md` (`flags-example`
  markers) from the guide, installs it as `tt backup db restore`, and checks that `cmd.sh`
  receives exactly the values listed between the `flags-values` markers.

## Continuous integration

`.github/workflows/tests.yml` (decision 0011) runs on every push to `main` and every pull
request: Linux, macOS with Homebrew Bash (both also under a pseudo-terminal), and Bash 4.2
plus the Bash 4.1 guard in the official `bash:*` Docker images. Keep tests portable to BSD
tools (macOS) and to BusyBox images with GNU tools added; the sandbox uses the physical
path of `mktemp -d` because macOS returns `/var/...`, a symlink to `/private/var/...`.
With `gh` installed: `gh run list`, `gh run watch`, `gh run view --log-failed`.

## Not covered yet

- zsh completion (`templates/completion.zsh`) is not exercised automatically (zsh was not
  available when it was written). Test it manually in zsh before changing it.
- `self update` against real remotes: tested manually with local bare repositories
  (see the recipe in `docs/roadmap.md`).

## Evaluating the guide with real AI models (manual)

The tests prove that the guide is complete and that its examples run; they cannot prove
that an AI *follows* it. After a significant change to `templates/ai-guide.md`, evaluate it
by hand with small models (the weakest available, e.g. Haiku):

1. Generate the guide in an isolated `HOME` (see `AGENTS.md`): `mu self guide -o <file>`.
2. Give it to several sub-agents that play a chat assistant without access to the machine,
   each with a different request. Use an agent that **only has file read and write tools,
   no shell** (with Claude Code: a user-level agent such as
   `~/.claude/agents/chat-ai-simulator.md` with `tools: Read, Write`), so that it cannot
   look at the machine even by mistake. Services the commands need (databases...) exist
   only on the evaluator's side. If they would ask questions, they write them, then a line
   `--- USER: ok ---`, then the full answer as if the user accepted their suggestions.
3. Run the `bash` blocks of each answer (after the `ok` line) in a fresh copy of the project
   with an isolated `HOME`, `_CB_TTY=/dev/null` and a timeout, with the install path
   replaced by the copy's path; then `mu self doctor` and try edge cases by hand.
4. Check: questions only when needed and each with a default; texts of the files in English;
   no assumption beyond the *Setup* table; existing and official plugins left alone;
   confirmation for destructive actions; the commands really work.

Requests worth keeping in the set: a destructive command (`git clean-branches`), a request
on an official plugin (`system disk`, which must not create `plugins/system/`), a vague
request ("my backups"), an external tool (`docker`), decimal or negative values (the DSL
has no float type), the editor format ("give me the file contents"), dynamic data stored in
`CB_CONFIG_DIR` (notes), and root privileges (ports with process names).

To check commands that need services the machine does not have (databases, a JDK), run
them **only on your side**, never in the sub-agents (they play a chat AI with no access
to anything). Without root, Debian packages can be used from a scratch directory:
`apt-get download <pkg>` then `dpkg-deb -x <pkg>.deb <root>` (PostgreSQL, MariaDB,
OpenJDK and their missing libraries, found with `ldd`), `LD_LIBRARY_PATH=<root>/usr/lib/...`,
PostgreSQL with `initdb` + `pg_ctl -o "-p <port> -c unix_socket_directories="` (socket
paths are limited to 107 bytes), MariaDB with `mariadb-install-db` + `mariadbd
--no-defaults --port=<port> --socket=<short path>`. Copy `/etc/java-*` into the JDK's
`conf/` (its files are symlinks to `/etc`). Jars for `javac -cp` come from Maven Central.
Stop the servers and delete the directory afterwards.
