# 0002. Official plugins in `core/`, user plugins in `plugins/`

- Status: Accepted
- Date: 2026-11-08

## Context
The repository ships common commands, and users add their own (sometimes work-specific,
sometimes in private repositories). The first idea was a single `plugins/` directory holding
both.

## Decision
Official plugins live in `core/` and are versioned with cmd-builder. User plugins live in
`plugins/`, which is entirely git-ignored (except its README); each user plugin may be its
own git repository, updated by `self update`. Ids are `core:<name>` and `user:<name>`.

## Alternatives considered
- *Single `plugins/` directory*: the day an official plugin `docker` is added upstream, a
  user's own `plugins/docker` (with its own `.git`) makes `git pull` fail with an
  "untracked working tree files would be overwritten" conflict.
- *Git submodules for plugins*: heavy for users, and private plugins would leak into the
  main repo's history.

## Consequences
Updates of the framework and of user plugins are independent. Name clashes between the two
sources are possible and must be handled (see 0003). Official plugins can be disabled.
