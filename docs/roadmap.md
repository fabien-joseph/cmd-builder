# Roadmap

Keep this file current: move items to **Done** when shipped, add follow-ups you discover.

## Done

- Core: routing by directory, `flags.sh` DSL, generated `--help`, parser, validation.
- Official (`core/`) vs user (`plugins/`) plugins, shadowing, `disable` / `rename` config.
- Built-ins: `self update`, `self new`, `self plugins [enable|disable]`, `self doctor`,
  `self completion`.
- bash + zsh completion through a single engine (`__complete`).
- `init.sh` install and idempotent `--uninstall`.
- Dynamic choices: `--choices-from` with optional `--strict`.
- Contributor docs for any AI agent (`AGENTS.md`, `docs/`), doc consistency tests.
- Review fixes (ultrareview of `feat/core`): `init.sh` usage without a name, rc block
  without end marker left untouched, bash completion immune to `nullglob`/`failglob`,
  `--flag=<TAB>` completion, negative numbers in completion, `self doctor` no longer
  flags `flags.sh` by their last command status, `self new` writes nothing when refused,
  symlinked config kept, Bash 4.2 minimum (decision 0008).
- `init.sh` prints the `source <rc file>` line to load completion in the current terminal.
- Tests never wait on the real terminal (`_CB_TTY`, decision 0009); "yes" paths tested.
- `self guide`: Markdown guide for AI chats without access to the machine, built from
  `templates/ai-guide.md` + `docs/plugin-authoring.md`; its worked example is run by the
  tests (decision 0010). Rules refined by three evaluation rounds with small models
  (method in `docs/testing.md`).
- CI on GitHub Actions (decision 0011): Linux, macOS (Homebrew Bash), both also under a
  pseudo-terminal, Bash 4.2 tests and the Bash 4.1 guard in Docker. Its first runs fixed two
  real Bash 4.2 bugs (`declare -g` inside functions, `\~` in replacements).
- `self rename <name> [--keep-old]` (decision 0012): moves link, config, completion and rc
  blocks to a new root name, resumable, one confirmation; install code shared with
  `init.sh` in `lib/install.sh`.
- `self doctor` checks every `example` like the parser would (warnings). CI on
  `actions/checkout` (Node.js 20 deprecation).
- Extensions of official plugins (decision 0013): `plugins/+system/disk/` adds
  `mu system disk` next to `mu system info`; `self new` creates them; the AI guide no
  longer steers users to another plugin name.
- Plugin dependencies (decision 0014): `requires` in `flags.sh`, checked before running;
  `self deps` / `install` / `update` / `managers`; package manager asked by `init.sh`.
  `ui::select`, an arrow-key menu in pure Bash (no `fzf` needed).
- `self guide [request]`: the request is appended at the end of the guide, to paste
  everything as a single message.

## Next

Next step (2026-11-08):

1. [ ] **Global review** of the project: a session where the agent acts as a software
   architect leading sub-agents (owner's prompt, review only, report + correction plan
   to validate before any change).
2. [ ] Then agree with the owner on the order of the *Accepted* list below (and of the
   review's correction plan).

Accepted, not scheduled yet:

- [ ] Repeatable flags (`--tag a --tag b`) / list type.
- [ ] Inherited flags: a flag declared on a parent available to all its subcommands,
      **opt-in** per flag (not always relevant).
- [ ] Command aliases (`mu backup ls` for `mu backup list`).
- [ ] Hidden commands (not listed in help and completion, still runnable): for commands
      still in development in a plugin that is already shared.
- [ ] `self plugins install <git-url>`: clone a plugin into `plugins/`, with a **big
      warning** that the plugin is not official and runs code on the machine, and a
      confirmation (rule 5).
- [ ] Automated test for zsh completion (needs zsh in the test environment).
- [ ] Optional timeout for `--choices-from` (a slow command currently blocks <kbd>Tab</kbd>).

## Ideas (not decided)

- `requires` with a minimal version (`--min 0.40`): needs reading each tool's `--version`.
- Other dependency sources (pip, cargo, npm, install scripts), restricted like the
  package managers.

- Plugins in other languages with a helper library (Python) for `ui::`-like output. Kept,
  not urgent.

Rejected: the guide of `self guide` in French or other languages (it stays in English; the
AI talks in the user's language, see decision 0010).

## Known limitations

- `ARG_<NAME>` of a variadic arg joins values with spaces; use `"$@"` for values containing
  spaces.
- `printf` padding counts bytes: accented characters in the *left* column of aligned output
  (help rows, `system info`) break alignment. Keep left columns ASCII.
- Bash completion re-splits the line on whitespace only: quoted words containing spaces are
  not handled.
- `requires` checks a command name: a package that installs it under another name
  (Debian `fd-find` → `fdfind`) shows as "still not found" after `self deps install`.
- `self deps update` on pacman is a full system upgrade (`pacman -Syu`): Arch does not
  support partial upgrades.
- Extensions (`plugins/+x/`) can only extend official plugins, not other user plugins.
- A mistyped subcommand after a command that has its own `cmd.sh` gives "unexpected
  argument" without a "Did you mean" suggestion (`mu self deps manager`).

## Manual recipe: testing `self update`

```bash
S=$(mktemp -d); cd "$S"
mkdir src && cp -R <checkout>/{main.sh,init.sh,lib,builtin,core,templates,docs} src/ && mkdir src/plugins
git -C src init -q -b main && git -C src add -A && git -C src commit -qm init
git clone -q --bare src core.git && git clone -q core.git install
git clone -q core.git w && echo '# x' >> w/core/system/flags.sh && git -C w commit -qam change && git -C w push -q
mkdir -p home/bin && ln -s "$S/install/main.sh" home/bin/mu
HOME=$S/home PATH=$S/home/bin:$PATH mu self update --check
```
