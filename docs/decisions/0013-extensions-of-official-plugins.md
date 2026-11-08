# 0013. Extensions of official plugins: `plugins/+<plugin>/`

- Status: Accepted
- Date: 2026-11-08

## Context
A user plugin with the name of an official one shadows it entirely (decision 0003): to get
`mu system disk` next to the official `mu system info`, the AI guide had to steer users to
another plugin name, or to `self new --core` (which writes into the cmd-builder repository).
Worse, `mu self new system disk` created `plugins/system/flags.sh` and hid `mu system info`.

## Decision
- A directory **`plugins/+<plugin>/`** extends the official plugin `core:<plugin>`: its
  subcommands are added to it. The owner wanted the extension to be **visible in the
  tree, by its name**. The same `+` works at every level (`plugins/+system/+net/` extends
  the official group `system net`). Names with `+` were ignored before, so nothing that
  worked changes; `plugins/<plugin>/` still shadows.
- Inside an extension, a plain directory with the name of an official subcommand replaces
  it: the user wins, and it is reported (same rule as 0003).
- An extension follows its official plugin by id (`core:<plugin>`): renamed with it;
  **inactive and reported** when it is disabled, shadowed or missing (owner's choice). It
  can be disabled (`disable user:+<plugin>`), not renamed (a config error). Files at its
  root are ignored and reported: the official plugin keeps its `about` and `cmd.sh`.
- `CB_PLUGIN_ROOT` of an extension command is the extension root, so it has its own `_lib/`.
- `self new system disk` creates the extension when `core:system` exists and the user has
  no `plugins/system/`; it refuses an official command or plugin as the target.
- Implementation: `_CB_OVL[<official dir>]=<extension dir>` filled at plugin load; every
  traversal uses `cb::children` / `cb::is_child` / `cb::child_dir`.

## Alternatives considered
- *Implicit extension by a root without files* (`plugins/system/` with only
  subdirectories): no syntax, but invisible in the tree, and adding a `flags.sh` there
  would silently switch to shadowing. Rejected by the owner.
- *An `extends` keyword in `flags.sh`*: discovery would have to source files at every call
  and every Tab, and it extends the DSL.
- *A config directive*: per machine, so a shared plugin would not carry it.
- *`system.extend/`, `system@core/`*: longer at every level; `+system` reads "adds to
  system" and needs no quoting in a shell.
- *Automatic merge of same-name plugins*: breaks existing shadowing setups (rule 2).

## Consequences
Any new code walking command trees must go through the extension-aware helpers. User
extensions can only extend official plugins (`core/`), not other user plugins.
