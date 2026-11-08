# 0005. Parsed values as environment variables, in a fresh process

- Status: Accepted
- Date: 2026-11-08

## Context
Commands should need as little code as possible to read their options, and some commands
will eventually be written in other languages (e.g. Python for heavy work).

## Decision
After parsing, the framework exports `FLAG_<NAME>` and `ARG_<NAME>` (plus `CB_*` context)
and `exec`s the command in a new process with the positionals as `"$@"`: `cmd.sh` through
`lib/run.sh` (which preloads the `ui::` helpers), or `cmd` directly. Inherited `FLAG_*` /
`ARG_*` from a parent invocation are cleared first.

## Alternatives considered
- *Sourcing `cmd.sh` into the framework process*: framework globals and functions would
  leak into and collide with plugin code.
- *Passing values as arguments or JSON*: requires parsing code in every command and every
  language.

## Consequences
Any language can read the values. Variadic values are flattened in `ARG_*` (use `"$@"`).
The env var names are part of the public contract.
