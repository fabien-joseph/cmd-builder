# 0001. One directory per command

- Status: Accepted
- Date: 2026-11-08

## Context
Commands can have subcommands, which can have their own subcommands. The owner wanted a
command such as `mu system` to be executable on its own while still having subcommands,
and wanted flag declarations in a dedicated file next to the command entry point.

## Decision
Each command is a directory. It may contain `flags.sh` (declarations, DSL), `cmd.sh`
(Bash entry point) or `cmd` (any executable), and child directories for subcommands, with
no depth limit. A directory without an executable is a router that shows its help.
Directories starting with `_` or `.` are ignored. Routing consumes child names greedily;
a child name wins over a positional argument with the same value.

## Alternatives considered
- *One file per command* (`commands/info.sh`): cannot make a node both executable and a
  parent without naming tricks.
- *Declarations inside the script header*: mixes metadata and code, and the framework would
  have to parse or source the whole script just to build help/completion.
- *A central manifest (YAML/JSON)*: needs a parser (dependency) and drifts from the code.

## Consequences
Discovery is a directory walk, adding a command never touches a registry, and `flags.sh` can
be sourced cheaply for help/completion. `flags.sh` must stay side-effect free.
