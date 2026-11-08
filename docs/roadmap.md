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

## Next

In this order (owner's choice, 2026-11-08):

- [ ] **CI** (GitHub Actions, `.github/workflows/tests.yml`, decision 0011): Linux and macOS
      (Homebrew Bash), both also under a pseudo-terminal; Bash 4.2 tests and the Bash 4.1
      guard in the official `bash:*` Docker images. Written, **first run pending**: the
      `bash-versions` job is `continue-on-error` until it has passed once.
- [ ] **`self rename <new-name>`**: rename the root command (`mu` → `xx`) without breaking
      anything: link in `~/.local/bin`, `~/.config/<name>/` (config kept), completion
      files, rc blocks. Today `./init.sh xx` installs a second, independent command (new
      empty config) and `./init.sh --uninstall mu` removes the old one: nothing breaks, but
      the config (`disable` / `rename` lines) is not carried over. Must be idempotent and
      resumable (rule 4).

Accepted, not scheduled yet:

- [ ] `self doctor` checks every `example` of a `flags.sh` against its own declarations
      (unknown option, missing required argument), like the parser would. An AI-written
      plugin had a `--help` example with undeclared flags.
- [ ] A user plugin can *extend* an official one instead of shadowing it
      (`plugins/system/disk/` adds `mu system disk` next to `mu system info`). Today the AI
      guide has to steer users to another plugin name, or to `self new --core`.
- [ ] Repeatable flags (`--tag a --tag b`) / list type.
- [ ] Inherited flags: a flag declared on a parent available to all its subcommands,
      **opt-in** per flag (not always relevant).
- [ ] Command aliases (`mu backup ls` for `mu backup list`).
- [ ] Hidden commands (not listed in help and completion, still runnable): for commands
      still in development in a plugin that is already shared.
- [ ] `self plugins install <git-url>`: clone a plugin into `plugins/`, with a **big
      warning** that the plugin is not official and runs code on the machine, and a
      confirmation (rule 5).
- [ ] `self guide [request]`: optional request appended at the end of the guide, ready to
      paste as a single message.
- [ ] Automated test for zsh completion (needs zsh in the test environment).
- [ ] Optional timeout for `--choices-from` (a slow command currently blocks <kbd>Tab</kbd>).

## Ideas (not decided)

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
