# 0012. `self rename`, with the install code shared with `init.sh`

- Status: Accepted
- Date: 2026-11-08

## Context
Changing the root name (`mu` → `xx`) used to mean `./init.sh xx` then
`./init.sh --uninstall mu`: it worked, but the new install started with an empty config
(`disable` / `rename` lines lost). The owner wanted a real rename, idempotent and resumable
(rule 4), with confirmation (rule 5).

## Decision
- **A `self` command**, `<name> self rename <new-name>`: `self` already knows its own name,
  link and config directory. The install layout knowledge (rc markers and block, atomic rc
  rewrite, "is this link ours", config-dir cleanup) moves from `init.sh` to
  **`lib/install.sh`**, used by both `init.sh` and `self rename`. Not loaded by
  `lib/core.sh`: only these two need it.
- **All checks first, then one plan and one confirmation** (`[y/N]`, "no" without a
  terminal). Refused without changing anything: invalid or builtin name, the current name
  not installed as a link to this checkout, `~/.local/bin/<new>` existing and not ours, both
  config files existing with different contents, an rc block of the old name without its
  end marker.
- **Steps in a resumable order**, each checking whether it is already done: new link;
  config file moved (`mv`, so a dotfile symlink stays a symlink); completion regenerated for
  the new name; in each rc file the old block replaced **in place** by the new one (one
  atomic rewrite, so there is never zero or two blocks); old config dir cleaned; **old link
  last**, so the old name keeps working, and the command can be run again, until the end.
- **`--keep-old`** (owner's choice): the old name stays installed (link, rc block,
  completion); the config moves to the new name and `~/.config/<old>/config` becomes a
  symlink to it, so both names share one config (`self plugins` already writes through
  symlinks). `init.sh --uninstall <old>` then removes that link without asking: the target
  belongs to the other name.

## Alternatives considered
- *`./init.sh --rename <old> <new>`*: works even when the command is broken, but `self`
  already has all the context, and the rename is not needed to recover a broken install.
- *Duplicating the rc code in `self rename`*: two copies of the marker handling, which must
  never drift (decision 0007).
- *One confirmation per rc file, like the install*: the plan already lists every file.
- *Asking which config to keep when both exist*: rare (the new name was installed
  separately) and easy to get wrong; refusing with a hint is safer.
- *Always removing the old name*: the owner wanted an option to keep it for scripts and
  aliases.

## Consequences
`init.sh` and `self rename` must keep using `lib/install.sh` for anything that knows the
install layout. The header comment of the moved config still names the old command; it is
only a comment.
