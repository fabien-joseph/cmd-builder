# 0006. Dynamic choices suggest by default, validate with `--strict`

- Status: Accepted
- Date: 2026-11-08

## Context
Fixed `--choices` cannot express lists that depend on the machine or the moment
(installed plugins, git branches, running containers).

## Decision
`--choices-from "<snippet>"` evaluates a shell snippet (in a subshell, in the user's current
directory, with `flags.sh` functions in scope) at completion time. Its values are
**suggestions only** unless `--strict` is given, in which case the given value is validated
against the list at run time too. `--choices` and `--choices-from` are mutually exclusive;
`--strict` requires `--choices-from`.

## Alternatives considered
- *Always validate*: wrong for lists that are legitimately incomplete (a remote branch not
  fetched yet) and runs a possibly slow command on every invocation.
- *Only function names*: less flexible than any snippet; functions remain possible.

## Consequences
Completion speed depends on the snippet (no timeout yet, see roadmap). Snippets run on each
<kbd>Tab</kbd> and must be side-effect free.
