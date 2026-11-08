# 0003. Name conflicts between plugins

- Status: Accepted
- Date: 2026-11-08

## Context
With two plugin sources (0002), a user plugin can have the same name as an official one,
and an official plugin could later be added with a name a user already uses.

## Decision
- The user plugin **shadows** the official one: the user chose it on their machine.
- Conflicts are reported (never silently): `self doctor`, `self plugins`, and a warning
  under the root help.
- The config file allows `rename <id> <new-name>` to keep both, and `disable <id>`.
- `self` is reserved for the built-in commands; a plugin exposed as `self` is ignored and
  reported.

## Alternatives considered
- *Official wins*: an upstream update could silently replace a user's command.
- *Hard error on conflict*: an upstream update could break a working installation.
- *Automatic namespacing* (`mu core:system`): ugly for the common case of no conflict.

## Consequences
Resolution is deterministic (core loaded first, then user). Renames and disables are per
machine, in `~/.config/<name>/config`.
