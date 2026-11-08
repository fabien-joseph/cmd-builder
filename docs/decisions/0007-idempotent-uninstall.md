# 0007. Uninstall in `init.sh`, as independent idempotent steps

- Status: Accepted
- Date: 2026-11-08

## Context
Uninstalling touches several places (symlink, rc files, config directory). The owner
required that a partially uninstalled system never makes the uninstaller fail, and that an
interrupted uninstall finishes on the next run.

## Decision
`./init.sh --uninstall <name>` (not a `self` command, so it works even if the command is
broken or already half removed). Each step checks first whether it is already done:
1. remove `~/.local/bin/<name>` only if it is a symlink to this checkout (even broken);
2. remove the marked block from `~/.bashrc` / `~/.zshrc` by rewriting the file atomically
   (temp file + `mv`, following symlinked rc files, cleaning a leftover temp file); if the
   end marker is missing, the file is left untouched (warning, exit code 1) rather than
   dropping everything after the begin marker;
3. remove config-dir files one by one (config only after confirmation), then the directory
   if empty.
The checkout and user plugins are never removed.

## Alternatives considered
- *`mu self uninstall`*: unusable once the symlink is gone, i.e. exactly when resuming an
  interrupted uninstall.
- *A single `rm -rf` of everything*: not resumable, and would delete things we did not
  create.

## Consequences
Install and uninstall share the rc markers (`# >>> cmd-builder: <name> >>>`), which must
never change format without a migration.
