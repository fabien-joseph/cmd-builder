# Changelog

Changes of the **plugin contract** (`flags.sh` DSL, `FLAG_*` / `ARG_*` / `CB_*`, `ui::`
helpers, layout, exit codes) and of user-visible behaviour. The version is in `VERSION`,
printed by `<name> --version` and `self doctor`, and exported as `CB_VERSION`. A plugin that
uses something added in a version needs at least that version: say so in its README.

## 1.0.0 — 2026-11-09

First numbered version, after the global review (docs/reviews/2026-11-09-global-review/).

Added:
- `CB_VERSION`, `<name> --version`.
- `self update --check` exits 10 when updates are available.
- `cmd.sh` is sourced by `bash -c`: `$0` is the `cmd.sh` path (was `lib/run.sh`, now removed).
- `CB_COMMAND`, `CB_COMMAND_DIR`, `CB_PLUGIN_ROOT` are set when `flags.sh` is read.

Changed (may affect existing plugins):
- `int` values and defaults reach the command as canonical 64-bit decimals (`08` → `8`);
  values out of the 64-bit range are refused.
- An option followed by a subcommand name (`mu backup -v restore`) is a usage error (exit 2);
  `--` keeps a value with that name.
- New declaration errors (exit 3): a flag `no-<x>` next to a bool `<x>`; two args with the same
  `ARG_` name; `--required` with `--default`.
- `requires` checks an executable in `PATH` (a shell keyword, builtin or function no longer
  counts).
- `--choices` values are never glob-expanded.
- `flags.sh` cannot change the run any more: its shell options, `IFS`, current directory are
  put back, its output goes to stderr.
- The `-d` of `ui::select` must be one of the options; prompts are printed on the terminal
  when stderr is redirected; `ui::title` is bold only when stdout is a terminal.
- `self rename` moves every user file of the config directory (plugin data too).
