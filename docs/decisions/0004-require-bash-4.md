# 0004. Require Bash ≥ 4, pure Bash, no dependencies

- Status: Accepted
- Date: 2026-11-08

## Context
The tool must run on personal machines, work machines and servers, including macOS, which
ships Bash 3.2 (2007). Bash 3.2 lacks associative arrays, `mapfile`, case conversion, etc.

## Decision
Require Bash 4 or later (macOS users install it with Homebrew; `#!/usr/bin/env bash` picks
it up). Entry scripts check the version first and print how to fix it. The framework uses
only Bash and POSIX tools common to Linux and macOS; `git` is needed only for `self update`.
Plugins may use whatever they want (including other languages).

## Alternatives considered
- *Bash 3.2 compatibility*: much more complex code everywhere (no associative arrays) for a
  one-time `brew install bash`. The owner explicitly chose Bash 4.
- *Another language (Python, Go)*: dependency or build step on every machine, and commands
  are mostly shell glue anyway.
- *Helpers like `jq`/`yq`*: not installed everywhere.

## Consequences
Avoid GNU-only tool flags (see `docs/conventions.md`). Bash 5-only features are forbidden.
