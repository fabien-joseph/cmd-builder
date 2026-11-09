# 0008. Require Bash ≥ 4.2

- Status: Accepted (amended by 0011: `declare -g` only at the top level of a file)
- Date: 2026-11-08
- Amends: [0004](0004-require-bash-4.md) (the minimum version only; the rest still applies)

## Context
Decision 0004 required "Bash ≥ 4" and the entry scripts only rejected 3.x. The framework
already relies on two features introduced in Bash 4.2: `declare -g` / `declare -gA` (global
arrays declared from sourced files and functions) and negative array subscripts
(`${array[-1]}`). On Bash 4.0 / 4.1 (e.g. RHEL/CentOS 6) the version check passed and the
tool then broke with cryptic errors instead of the friendly upgrade message.

## Decision
The minimum is **Bash 4.2** (2011). `main.sh` and `init.sh` reject `[0-3].*` and `4.[01].*`
with the message "requires Bash >= 4.2".

## Alternatives considered
- *Stay compatible with 4.0*: replace every `declare -g` (declare globals at top level
  only, never inside functions) and `[-1]` subscripts. Doable, but for platforms that have
  been end-of-life for years, and an easy rule to break again unnoticed.

## Consequences
`declare -g` (at the top level of a file only: inside a function, Bash 4.2 does not create
the global, decision 0011) and negative subscripts are allowed (see `docs/conventions.md`). macOS users
still just `brew install bash` (5.x).
