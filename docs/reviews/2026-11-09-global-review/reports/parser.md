# parser — plugin contract (public API), DSL, parser, help, ui:: helpers

## Scope and method

- Read fully: lib/spec.sh, lib/parse.sh, lib/help.sh, lib/run.sh, lib/ui.sh, lib/router.sh,
  lib/util.sh, lib/core.sh, main.sh, builtin/self/doctor/cmd.sh; docs/plugin-authoring.md,
  README.md (layout, flags.sh, cmd.sh), docs/conventions.md, docs/architecture.md,
  docs/roadmap.md, docs/handoff.md, decisions 0001, 0005, 0006, 0009, 0014; the start of
  tests/run.sh (contract doc checks + parsing tests).
- Experiments: one sandbox (`mksandbox.sh parser`, root `tt`), ~20 fixture plugins
  (glob choices, `no-` bools, arg-name collisions, int edge values, required/default,
  `$0`/`return` in cmd.sh, flags.sh with `cd`/`echo`/`set -euo pipefail`/helper
  variables, `requires` of a keyword and of a function, router with flags, parse edge
  cases, help rendering, flags.sh environment in direct/nested/completion runs).
  `ui::confirm` / `ui::ask` / `ui::select` and colour detection driven through a real
  pseudo-terminal (`script -qec … /dev/null`, keys sent on the pty).
- Every hypothesis of the task was tested; refuted or harmless ones are listed in
  "What is good". Not covered: completion engine internals, routing/plugin discovery,
  install/rename/deps/update commands, CI (other reviewers); Ctrl-C terminal restore in
  `ui::select` and line wrapping (no terminal emulator); Bash 4.2 / macOS (not installed).

## Grade

| Aspect | Grade | Why |
|---|---|---|
| DSL design and declaration checks | B | Small, readable, strict: DSL errors stop with `file:line` (exit 3), defaults checked against type and choices, short/variadic/optional ordering enforced. Gaps: env-name and `no-` collisions, `--required --default`, glob in choices (PAR-05..07, 09). |
| Parser (rules of plugin-authoring.md) | B+ | Every documented rule behaves as written (`--x=v`, `-xv`, `-abc`, `--`, `-5`, `-`, `--no-x`, options anywhere, `-h` in a group, `--help` as a value). Weak spots: `int` values unsafe for arithmetic (PAR-04), `--=x` (PAR-14). |
| flags.sh isolation | D | Sourced inside framework functions in the main process: helper variables overwrite framework locals (PAR-01), `set -e` kills commands silently, `cd`/`echo` leak (PAR-02), stale `CB_*` at load time (PAR-11). The rule "no side effects" is only trusted. |
| cmd.sh runtime contract | C | Fresh process, values as env vars and `"$@"` work as documented; but `$0` is `lib/run.sh`, `_cb_cmd` leaks, "sourced" is undocumented for plugin authors (PAR-03). |
| Help | A- | `printf '%s'` everywhere (no `%`/backslash injection), choices/defaults/required rendered; only cosmetics (PAR-16). |
| ui:: helpers and colours | B | Pure Bash, no-terminal = no / default, `_CB_TTY` testability, `NO_COLOR` per no-color.org. Prompts invisible with stderr redirected (PAR-12), `ui::select` numbering and `-d` (PAR-13), colours fixed at load (PAR-15). |
| Contract docs vs code | B+ | Accurate on everything tested (and guarded by `contract_checks`), but silent on what flags.sh/cmd.sh may rely on (see "Undefined or missing"). |

## Findings

All reproductions run in a sandbox made with `mksandbox.sh parser` (root command `tt`,
`NO_COLOR=1`, `_CB_TTY=/dev/null` unless said otherwise). `$SB` = the sandbox, fixture
plugins written in `$SB/app/plugins/<name>/`. Paths in outputs shortened to `$SB`.

### PAR-01 A helper variable in flags.sh (`dir`, `top`, `display`) silently breaks the command
- Severity: major   - Status: VERIFIED
- Aspect: DSL / plugin contract   - Location: lib/spec.sh:99, lib/router.sh:72-75, lib/router.sh:95
- Evidence: `cb::run` declares `local dir top display exe s`, then calls `cb::spec_load`,
  which `source`s flags.sh **inside a function**: Bash dynamic scoping makes every top-level
  assignment of flags.sh write the caller's locals.
  ```bash
  # plugins/vars/flags.sh                      # plugins/vars2/flags.sh
  about "vars"                                 about "vars2"
  dir="$HOME/backups"                          display="Pretty name"
  flag target string "Target" \               top=1
       --choices-from 'ls "$dir"'              flag x bool "X"
  ```
  ```
  $ tt vars --target b1
  ✗ unknown option '--target'
  See 'tt vars --help'.            rc=2      (the declared flag is "unknown")
  $ tt vars
  tt vars — vars / Usage / (nothing)  rc=0   ($HOME/backups is treated as a pure router)
  $ tt vars2 --x
  ran CB_COMMAND=Pretty name CB_PLUGIN_ROOT=1   (contract variables corrupted)
  ```
- Impact: any plugin whose flags.sh keeps a helper variable for its `--choices-from`
  snippets under a common name (`dir`, `top`, `display`, `exe`, `s`; in other paths
  `name`, `path`, `f`, the doctor's locals) is misrouted or gets wrong `CB_*` values, with
  an error that points at the user, not at the cause. The docs say flags.sh "is Bash" and
  "functions may be defined"; nothing warns about variables.
- Fix: in `cb::run`, call `cb::spec_load "$1"` **before** declaring its locals (values come
  from `$1..$3`, which flags.sh cannot change), and use `_cb_`-prefixed locals in every
  function that sources a flags.sh (`cb::spec_load`, `cb::complete`, doctor's
  `check_example`, `cb::deps_collect`). Document: "variables of flags.sh: prefix them with
  `_` + plugin name, like functions". Add a test with `dir=`/`display=` in a fixture
  flags.sh. — Cost: S
- Decision: 0001 ("flags.sh can be sourced cheaply") stays; sourcing is fine, only the
  scope leak must be closed.

### PAR-02 `set -e` (e.g. `set -euo pipefail`) or `cd` / `echo` in flags.sh leak into the framework; `set -e` kills commands silently
- Severity: major   - Status: VERIFIED
- Aspect: DSL / parser robustness   - Location: lib/spec.sh:99, lib/parse.sh:147, lib/router.sh:96-100
- Evidence: flags.sh is sourced in the framework process, so its shell options, current
  directory and stdout are the framework's.
  ```bash
  # plugins/sete/flags.sh: "set -euo pipefail" + about + flag verbose + arg name --optional
  $ tt sete bob
                                      (no output at all)   rc=1
  $ PS4='+${BASH_SOURCE##*/}:${LINENO}: ' bash -x ~/.local/bin/tt sete bob 2>&1 | tail -2
  +parse.sh:146: _CB_AVAL[$name]=bob
  +parse.sh:147: (( i++ ))              <- returns 1 when i=0: errexit
  # set -u alone: works. --help, root help and completion: work (subshells / early exit).

  # plugins/side/flags.sh:  cd /   and   echo "noise-from-flags.sh"
  $ cd $SB/w/withtxt && tt side            # cmd.sh: echo "pwd=$PWD"
  noise-from-flags.sh
  pwd=/                                    (cmd.sh runs in flags.sh's directory)
  $ tt side --help
  noise-from-flags.sh                      (pollutes the help on stdout)
  tt side — side effects
  ```
- Impact: `set -euo pipefail` at the top of every Bash file is a widespread habit (and
  what many AIs write); the guide only says *cmd.sh* needs no `set -e`
  (templates/ai-guide.md:136). Every invocation with a positional argument then exits 1
  with no message. A stray `echo` breaks pipeability of the command's stdout; a `cd`
  changes the directory the user's command runs in.
- Fix: make `cb::spec_load` defensive: save `$-`/`shopt -po`, `$PWD` before `source`,
  restore them after (`set +euo pipefail`, `cd -- "$saved"`), and send flags.sh stdout to
  stderr (`source "$f" >&2`) — none of this changes valid plugins. Also replace
  `((i++))` by `((++i))`/`i=$((i + 1))` across `lib/` (robust even under `set -e`). Document
  in "flags.sh DSL": no `set -e`, no `cd`, no output. — Cost: S
- Decision: 0001 (flags.sh side-effect free) — keep the rule, but enforce it cheaply instead
  of trusting it.

### PAR-03 In cmd.sh, `$0` is `lib/run.sh`: the `$(dirname "$0")` idiom breaks; `_cb_cmd` leaks
- Severity: major   - Status: VERIFIED
- Aspect: plugin contract (cmd.sh environment)   - Location: lib/run.sh:4-8, lib/router.sh:100, docs/plugin-authoring.md:27
- Evidence:
  ```bash
  # plugins/zero/cmd.sh
  echo "0=$0"; echo "BASH_SOURCE0=${BASH_SOURCE[0]}"; echo "_cb_cmd=${_cb_cmd-unset}"
  source "$(dirname "$0")/_lib/h.sh"
  return 3
  ```
  ```
  $ tt zero; echo rc=$?
  0=$SB/app/lib/run.sh
  BASH_SOURCE0=$SB/app/plugins/zero/cmd.sh
  _cb_cmd=$SB/app/plugins/zero/cmd.sh
  $SB/app/plugins/zero/cmd.sh: line 2: $SB/app/lib/_lib/h.sh: No such file or directory
  rc=3                                   (top-level `return` works: cmd.sh is sourced)
  ```
  Prototype of a fix (`bash -c` sets `$0` to its first operand):
  ```
  $ CB_ROOT=$APP bash -c 'source "$CB_ROOT/lib/ui.sh"; source "$0"' $APP/plugins/zero/cmd.sh a b
  0=$SB/app/plugins/zero/cmd.sh   BASH_SOURCE0=…/zero/cmd.sh   _cb_cmd=unset   (no error)   rc=3
  ```
- Impact: `source "$(dirname "$0")/_lib/…"` and `basename "$0"` in usage messages are the
  most common Bash idioms, and the natural way to reuse the `_lib/` the layout advertises;
  anyone turning an existing script into a `cmd.sh` hits it. plugin-authoring.md says
  `cmd.sh` "is run with Bash" and never that it is *sourced* (only architecture.md:37 does);
  it never says how to reach `_lib/` (`$CB_COMMAND_DIR` / `$CB_PLUGIN_ROOT`).
- Fix: in `cb::run`, `exec "$BASH" -c 'source "$CB_ROOT/lib/ui.sh" && source "$0"' "$exe" "${_CB_POS[@]}"`
  (keep `lib/run.sh` as a thin compatibility wrapper or drop it), so `$0` = cmd.sh, no
  `_cb_cmd`. Document: cmd.sh is sourced by a fresh Bash (top-level `return` allowed,
  `BASH_SOURCE`), and "use `$CB_COMMAND_DIR` / `$CB_PLUGIN_ROOT` to source `_lib/`".
  Add a test. — Cost: XS
- Decision: 0005 (fresh process) is kept; only how `cmd.sh` is started changes.

### PAR-04 `int` accepts leading zeros and unbounded values: `08` crashes arithmetic, `010` is silently 8, overflow wraps
- Severity: major   - Status: VERIFIED
- Aspect: DSL types / parser   - Location: lib/parse.sh:32, lib/spec.sh:200, docs/plugin-authoring.md:156
- Evidence: `flag n int "N"`, cmd.sh `echo "n=$FLAG_N next=$((FLAG_N + 1))"`:
  ```
  $ tt num --n 08
  …/num/cmd.sh: line 1: 08: value too great for base (error token is "08")   rc=1
  $ tt num --n 010
  n=010 next=9                                  (octal!)
  $ tt num --n 99999999999999999999999999999
  n=99999999999999999999999999999 next=7886392056514347008
  $ tt num --n 9223372036854775808
  n=9223372036854775808 next=-9223372036854775807
  $ tt num --n -0      ->  n=-0 next=1 ;   tt num --n +5  ->  ✗ --n expects an integer (got '+5')
  ```
  `--default 08` is also accepted by `flag` (same regex, spec.sh:200).
- Impact: an `int` flag exists to be used in arithmetic; `--hour 08`, `--month 09`,
  `--port 0080` are natural inputs. The plugin crashes or silently computes with another
  value although the framework "validated" the integer.
- Fix: normalise accepted values to canonical decimal before export (strip leading zeros
  and `-0` → `0`, e.g. `val=$((10#${val#-}))` with the sign re-applied, after a length
  check) and reject values outside the 64-bit range (compare digit count / string against
  `9223372036854775807`), with the same message style ("expects an integer between …").
  Optionally accept `+5`. Apply the same to `--default`. Document "canonical decimal,
  64-bit". — Cost: S
- Decision: none.

### PAR-05 `--choices` values are glob-expanded: a flags.sh becomes invalid depending on the current directory
- Severity: minor   - Status: VERIFIED
- Aspect: DSL (choices) / help / completion   - Location: lib/spec.sh:203, lib/spec.sh:45
- Evidence: `flag pat string "Pattern" --choices "*.txt *.md" --default "*.txt"`
  ```
  $ cd $SB/w/empty && tt g             ->  pat=*.txt                rc=0
  $ cd $SB/w/withtxt && tt g           (directory containing notes.txt)
  ✗ $SB/app/plugins/g/flags.sh:2: --pat: default value '*.txt' is not one of the choices (*.txt *.md)   rc=3
  $ cd $SB/w/withtxt && tt g --help    ->  same error, rc=3
  $ tt self doctor (from that directory)  ->  ✗ plugins/g: ✗ …flags.sh:2: --pat: default value '*.txt' is not one of the choices
  # completion (cb::choices_of), without the default:
  $ cd $SB/w/empty   && tt __complete -- g --pat ''   ->  *.txt  *.md
  $ cd $SB/w/withtxt && tt __complete -- g --pat ''   ->  notes.txt  *.md
  ```
  (Run-time validation, lib/spec.sh:57 `read -ra`, is not affected: `--pat '*.txt'` works.)
- Impact: rare (choices containing `*`, `?`, `[`), but the failure is confusing: the same
  command works in one directory and is "invalid" (exit 3) in another, and Tab offers file
  names. Side note: doctor prints a double `✗` prefix (doctor's own + `ui::die`'s).
- Fix: split with `read -ra list <<<"$choices"` (as `cb::choice_ok` already does) in
  `flag` and `cb::choices_of`; or `local -; set -f` around the loops. Test with a `*`
  choice run from a directory containing a match. — Cost: XS
- Decision: none.

### PAR-06 `flag color bool` + `flag no-color bool`: `--no-color` sets the other flag, help lies
- Severity: minor   - Status: VERIFIED
- Aspect: DSL / parser / help   - Location: lib/spec.sh:190, lib/parse.sh:69-73, lib/help.sh:63
- Evidence: `flag color bool "Colour" --default 1` and `flag no-color bool "No colour"`
  ```
  $ tt col --no-color
  color=1 no_color=1
  $ tt col --help | grep -i color
        --color     Colour (on by default, --no-color to disable)
        --no-color  No colour
  ```
- Impact: the bool `color` can no longer be disabled although the help says how; no
  declaration error. Plausible when a plugin mirrors `NO_COLOR`.
- Fix: in `flag`, reject `no-<x>` when a bool `<x>` exists, and a bool `<x>` when
  `no-<x>` exists ("--no-color is reserved by the bool --color"); document it in the
  `bool` row. — Cost: XS
- Decision: none.

### PAR-07 `arg my-file` + `arg my_file` both map to `ARG_MY_FILE`: first value lost, no error
- Severity: minor   - Status: VERIFIED
- Aspect: DSL / env names   - Location: lib/spec.sh:224, lib/spec.sh:238, lib/parse.sh:168-169
- Evidence:
  ```
  $ tt argcol one two          # arg my-file "first" ; arg my_file "second"
  ARG_MY_FILE=two argv=one two
  ```
  Only args can collide (flag names cannot contain `_`, spec.sh:161).
- Fix: in `arg`, compare the normalised env name (`${name//-/_}`) of every declared arg and
  fail with "'my_file' and 'my-file' are both ARG_MY_FILE". — Cost: XS
- Decision: 0005 (env var names are public) — unchanged.

### PAR-08 `requires` is satisfied by shell keywords, builtins and flags.sh functions
- Severity: minor   - Status: VERIFIED
- Aspect: `requires` check   - Location: lib/router.sh:61
- Evidence: `/usr/bin/time` is absent in the sandbox (`type -a time` → keyword only).
  ```
  $ tt rq            # flags.sh: requires time   cmd.sh: time -v true
  …/rq/cmd.sh: line 1: -v: command not found     rc=127   (check passed)
  $ tt rq2           # flags.sh: fzf() { :; }; requires fzf
  …/rq2/cmd.sh: line 1: fzf: command not found   (the flags.sh function satisfied command -v)
  ```
- Impact: `requires time` (GNU time for `-v`/`-f`) is the realistic case; `kill`, `test`,
  `printf` similar. The promise "the command does not run if a tool is missing" fails.
- Fix: `type -P "$t" >/dev/null` (PATH lookup only, builtin, portable) here and wherever
  the deps code checks presence (deps reviewer to confirm in lib/deps.sh). — Cost: XS
- Decision: 0014 ("presence only, `command -v`") — the intent (an executable in PATH) is
  better served by `type -P`; amend the decision text.

### PAR-09 `--required` + `--default` is accepted, and the default is dead code
- Severity: minor   - Status: VERIFIED
- Aspect: DSL validation   - Location: lib/spec.sh:181, lib/parse.sh:123-124
- Evidence: `flag both string "Both" --required --default x`
  ```
  $ tt req --key k
  ✗ --both is required        rc=2   (the default is never used)
  ```
- Fix: `cb::_spec_err "--both: --required and --default are mutually exclusive"`. — Cost: XS
- Decision: none.

### PAR-10 A router's `flag` / `arg` / `requires` are silently ignored (and `requires` still counts)
- Severity: minor   - Status: VERIFIED
- Aspect: DSL / doctor   - Location: lib/router.sh:77-92, lib/help.sh:44,58, builtin/self/doctor/cmd.sh:106-127
- Evidence: plugins/rt/flags.sh declares `flag verbose -v`, `arg thing`, `requires
  definitely-missing-tool-xyz`, and has a subcommand `leaf/cmd.sh` but no cmd.sh.
  ```
  $ tt rt -v
  ✗ unknown option '-v'          rc=2   (declared, but ignored)
  $ tt rt --help                 -> Options: only "-h, --help"; nothing about verbose/thing
  $ tt self doctor | grep rt
    ! definitely-missing-tool-xyz missing, needed by tt rt (run 'tt self deps install')
  ```
- Impact: an author expecting a group-level flag (a natural expectation, cf. the accepted
  "inherited flags" roadmap item) gets no feedback; `self deps` would install a tool for a
  command that never checks it.
- Fix: doctor warning "declares flags/args/requires but has no cmd.sh: they are ignored";
  skip routers in `cb::deps_collect`. — Cost: XS
- Decision: 0001 (a directory without executable is a router) — unchanged.

### PAR-11 At load time, flags.sh sees no `CB_COMMAND_DIR` / `CB_PLUGIN_ROOT` — or the parent's in a nested call
- Severity: minor   - Status: VERIFIED
- Aspect: plugin contract (flags.sh environment)   - Location: lib/router.sh:74 vs lib/router.sh:95, lib/complete.sh:72,83-84
- Evidence: plugins/fs/flags.sh prints the variables to stderr at top level; plugins/nest
  (`flag x string`, cmd.sh `tt fs`) calls it.
  ```
  $ tt fs
  flags.sh sees: CB_COMMAND_DIR= CB_PLUGIN_ROOT= CB_COMMAND= BASH_SOURCE=plugins/fs/flags.sh
  $ tt nest --x leak
  flags.sh sees: CB_COMMAND_DIR=plugins/nest CB_PLUGIN_ROOT=plugins/nest CB_COMMAND=tt nest BASH_SOURCE=plugins/fs/flags.sh
  fs ran, FLAG_X=                  (FLAG_* are correctly cleared; CB_* are stale at load time)
  ```
  Completion exports `CB_PLUGIN_ROOT` before loading the spec but `CB_COMMAND_DIR` after
  (complete.sh:72 / :84), `cb::run` exports all three after (router.sh:95).
- Impact: a flags.sh that shares choice helpers with `source "$CB_COMMAND_DIR/_choices.sh"`
  (a natural extension of the documented `'"$CB_COMMAND_DIR/_hosts.sh"'` snippet) fails
  on direct runs and **sources another plugin's file** in nested calls.
- Fix: export `CB_COMMAND`, `CB_COMMAND_DIR`, `CB_PLUGIN_ROOT` before `cb::spec_load` in
  `cb::run` and `cb::complete` (and the doctor/deps loaders), then document that flags.sh
  may use them at top level; also document `${BASH_SOURCE[0]%/*}`. — Cost: XS
- Decision: none.

### PAR-12 Prompts go to stderr but read `/dev/tty`: with stderr redirected, questions are invisible and still answered
- Severity: minor   - Status: VERIFIED
- Aspect: ui:: helpers (rule 5)   - Location: lib/ui.sh:34-35, lib/ui.sh:48-52, lib/ui.sh:70-72
- Evidence: real pseudo-terminal (`script -qec`), keys sent on the pty, `_CB_TTY` unset:
  ```
  # ui::confirm "Delete everything?" 2>/dev/null; echo rc=$?     keys: y Enter
  y                       <- only the terminal echo of the key; the question never shows
  rc=0                    <- confirmed
  # c=$(ui::select "Env?" dev staging prod 2>/dev/null)          key: 2
  rc=0 choice=staging     <- menu never shown
  ```
- Impact: `mu x 2>err.log` or `2>/dev/null` (to hide warnings) on a terminal: the command
  seems to hang; a key typed blindly answers a destructive question the user never saw.
  git/ssh avoid this by writing prompts to the terminal they read from.
- Fix: open the prompt device read-write once (`exec {fd}<>"${_CB_TTY:-/dev/tty}"`) and,
  when stderr is not a terminal but `/dev/tty` is used, print the question (and the menu)
  to that fd; keep stderr when `_CB_TTY` is set (tests). Same draw logic for `ui::select`
  (`[[ -t $fd ]]` instead of `-t 2`). — Cost: S
- Decision: 0009 (`_CB_TTY`) unchanged.

### PAR-13 `ui::select`: options 10+ have no number, `-d` outside the options is returned only without a terminal
- Severity: minor   - Status: VERIFIED
- Aspect: ui:: helpers   - Location: lib/ui.sh:69, lib/ui.sh:73, lib/ui.sh:94, lib/ui.sh:110-115
- Evidence (pty as above):
  ```
  # 12 options o1..o12, keys "1" "0" (user wants o10)
  rc=0 choice=o1                 <- the first digit selects at once
  # ui::select "Pick" -d foo a b c, Enter, with a terminal
  rc=0 choice=a
  # same, without a terminal (_CB_TTY=/dev/null)
  rc=0 choice=foo                <- a value that is not an option
  ```
  The arrow-key menu does not display numbers, although the contract says "or the option
  number"; the fallback list (stderr not a tty) shows `10) o10`, which cannot be typed.
- Impact: the non-interactive path (cron, CI, tests) returns a value the plugin never
  offered, untested by the author; >9 options cannot use numbers.
- Fix: ignore/flag a `-d` that is not an option (`ui::error "ui::select: default 'foo' is not an option"`,
  return 1) so both paths agree; show numbers in the menu for n <= 9 and document "1-9";
  optionally accumulate digits when n > 9. — Cost: XS
- Decision: 0014 (`ui::select`) unchanged.

### PAR-14 `--=x` leaks a Bash error and reports the wrong option
- Severity: minor   - Status: VERIFIED
- Aspect: parser   - Location: lib/parse.sh:65-69
- Evidence:
  ```
  $ tt pe --=x
  $SB/app/lib/parse.sh: line 69: _CB_F_TYPE: bad array subscript
  ✗ unknown option '--'          rc=2
  ```
- Fix: `[[ -n $name ]] || cb::_parse_err "unknown option '$a'"` before the lookup. — Cost: XS
- Decision: none.

### PAR-15 Colours are decided once at load: `ui::title … > file` inside cmd.sh writes escape codes
- Severity: minor   - Status: VERIFIED
- Aspect: ui:: helpers / colours   - Location: lib/ui.sh:10-15, lib/ui.sh:27
- Evidence: in a pty, `bash -c 'source lib/ui.sh; ui::title Report > r.txt'`, then
  `cat -A r.txt` → `^[[1mReport^[[0m$`.
- Impact: a command that writes a report with `ui::title` (documented as "bold line on
  stdout") to a file or `$(…)` gets raw escapes. `NO_COLOR` with an empty value correctly
  keeps colours (verified: `NO_COLOR=` → `UI_BOLD=$'\E[1m'`, `NO_COLOR=1` → empty), as
  no-color.org specifies.
- Fix: `ui::title` tests `[[ -t 1 ]]` at call time; document that `UI_*` reflect stdout at
  start-up. — Cost: XS
- Decision: none.

### PAR-16 Help cosmetics: empty default, repeated spaces in choices, wide option names
- Severity: minor   - Status: VERIFIED
- Aspect: help   - Location: lib/help.sh:12, lib/help.sh:48, lib/help.sh:65-66
- Evidence (`tt hr --help`):
  ```
        --e <string>                Empty default (default: )
        --sp <a||b>                 Spaces
        --a-very-long-option-name-exceeding-thirty <string>  Long
  ```
  `about "100% sure \n back\\slash"`, a multi-line `description`, optional + variadic +
  choices args and bool `--default 1` all render correctly (`printf '%s'` everywhere).
- Fix: skip "(default: )" for an empty default; normalise choices with `read -ra` + join
  (conventions.md already warns about `${a[*]// /|}`). — Cost: XS
- Decision: none.

### PAR-17 `ui::select` redraw with lines wider than the terminal
- Severity: minor   - Status: NOT VERIFIED (needs a terminal emulator: the `script` pty does not wrap lines)
- Aspect: ui:: helpers   - Location: lib/ui.sh:79-85
- Evidence: the redraw moves the cursor up exactly `n` rows (`\e[%dA`); an option wider
  than the terminal occupies 2+ rows once wrapped, so each redraw would leave stale lines
  and climb into the question. Also no fallback for `TERM=dumb`.
- Fix: truncate options to `${COLUMNS:-80}` - 4 characters when drawing (Bash 4.2: get
  `COLUMNS` via `checkwinsize` or `stty size </dev/tty`), or fall back to the numbered
  list when an option is too wide or `TERM=dumb`. — Cost: S
- Decision: none.

## Deliverable 1 — the de-facto public API (what must never change)

Documented, and verified to behave as documented:
- DSL keywords `about`, `description`, `flag`, `arg`, `example`, `requires`; options
  `--default --required --choices --choices-from --strict --optional --variadic` and the
  `requires` package options; name regexes (flag `^[a-z0-9][a-z0-9-]*$`, arg
  `^[a-z0-9][a-z0-9_-]*$`); types `bool|string|int`; `-h`/`--help` reserved; a DSL error
  exits 3 with `<flags.sh>:<line>: <message>`.
- `FLAG_<NAME>` / `ARG_<NAME>` (upper case, `-`→`_`) **always exported**, empty when
  absent; bools `0`/`1`; variadic joined with spaces; `"$@"` = positionals in order,
  options and `--` removed; inherited `FLAG_*`/`ARG_*` cleared (verified on a nested call).
- `CB_NAME`, `CB_COMMAND`, `CB_COMMAND_DIR`, `CB_PLUGIN_ROOT`, `CB_ROOT`, `CB_CONFIG_DIR`.
- `ui::info/success/warn/error` (stderr, symbols `› ✓ ! ✗`), `ui::die` (default code 1),
  `ui::title` (stdout), `ui::confirm` (y/yes case-insensitive, no terminal = 1 even with
  default `y`), `ui::ask` (default on EOF), `ui::select` (stdout, 1 on cancel), `UI_*`.
- Exit codes 0 / 1 (`requires` missing) / 2 (usage) / 3 (invalid flags.sh), and
  `--choices-from` semantics of decision 0006 (eval in a subshell, user's cwd, stderr
  discarded, `value<TAB>description`).

Undocumented, but plugins may already rely on it (freeze or document before changing):
- **Parsing**: a flag given twice → the last one wins (`--key a --key b` → `b`); a
  string/int value is the next word verbatim even if it starts with `-` (`-k -l` →
  `-l`, `--key --help` → `--help`); `-k=val` → `=val`; `-kh` → value `h` but `-lh`
  (bool) → help; `--key=` / `--key ''` give an empty value that **satisfies
  `--required`**; `--help` exits 0 even with required flags missing, but only if no
  earlier word failed (`--lang xx --help` → error); `--no-x=…` is an unknown option;
  newlines are preserved in values; `int` keeps the typed form (`010`, `-0`).
- **flags.sh**: sourced on every run, `--help`, root help (each plugin's `about`), Tab,
  doctor and deps; `BASH_SOURCE[0]` is its path; functions it defines are visible to its
  `--choices-from` snippets; the status of its last command is ignored; `$HOME`,
  `CB_NAME`, `CB_ROOT`, `CB_CONFIG_DIR` are set at load time (`CB_COMMAND*` are not, PAR-11).
- **cmd.sh**: run as `bash lib/run.sh <cmd.sh> args` — sourced in a fresh Bash, so a
  top-level `return N` is the exit code, `BASH_SOURCE[0]` is cmd.sh, `$0` is run.sh, the
  cwd is the user's, stdin/stdout/stderr are inherited, `ui.sh` internals (`_UI_*`,
  `_cb_cmd`) are defined, no `set -e`/`-u`. `cmd` is `exec`'d directly.
- **ui::** details: `ui::ask` trims leading/trailing whitespace (`"  two  words  "` →
  `two  words`), no hidden-input mode; `ui::select` keys `j`/`k`/`q`/Esc/`1`-`9`, and its
  no-terminal default even when not an option (PAR-13); colours fixed at load (PAR-15);
  `NO_COLOR` only disables when non-empty.

## Deliverable 2 — undefined or missing in the contract, with proposals

| # | Undefined / missing | Proposal |
|---|---|---|
| 1 | Variables in flags.sh (scope, naming) | Fix PAR-01, then document "prefix helper variables and functions with `_<plugin>_`". |
| 2 | What flags.sh may use at load time | Export `CB_COMMAND*` before loading (PAR-11); document `${BASH_SOURCE[0]%/*}`. |
| 3 | Shell options, cwd, stdout of flags.sh | Enforce in `cb::spec_load` (PAR-02); document the three "don'ts". |
| 4 | How cmd.sh is started | Document "sourced by a fresh Bash; `return` allowed; use `$CB_COMMAND_DIR`/`$CB_PLUGIN_ROOT` for `_lib/`" and make `$0` = cmd.sh (PAR-03). |
| 5 | Repeated flags | Document "last wins" now; the roadmap's repeatable flags must be an explicit per-flag opt-in (`--repeatable`) to keep it. |
| 6 | Values starting with `-`, `-x=val` | Document both (getopt-like); optionally warn on `-x=` ("did you mean --name=val?"). |
| 7 | Empty value for `--required` | Document "given, possibly empty"; add `--non-empty` later if wanted (a behaviour change otherwise). |
| 8 | `int` format and range | Canonical decimal, 64-bit range, documented (PAR-04). |
| 9 | Default for an optional `arg` | Compatible extension: `arg … --optional --default v` (today the plugin writes `${ARG_X:-v}`). |
| 10 | `ui::select` corner cases (empty list, >9 options, `-d` not an option) | Define them (PAR-13): empty list → error message + 1, digits 1-9 shown. |
| 11 | Prompts when stderr is redirected; hidden input | PAR-12; a future `ui::ask -s` (password, `read -s`) would avoid plugins calling `read </dev/tty` themselves (forbidden by conventions). |
| 12 | Exit codes for plugins | Recommend `ui::die "…" 2` for usage errors, so `mu x …` behaves like the framework. |
| 13 | `--choices` value syntax | Document "no spaces, no glob characters" until PAR-05 is fixed. |
| 14 | `requires` semantics | "An executable in PATH" (`type -P`, PAR-08). |
| 15 | Flags declared on a router | Doctor warning now (PAR-10); "inherited flags" later, opt-in. |
| 16 | Contract versioning | A "Contract changes" list in plugin-authoring.md (date + change), so plugin authors and `self guide` readers can tell what changed. |

## What is good and must be kept

- DSL errors carry `file:line` found through `BASH_LINENO`, whatever the call depth,
  and exit 3; root help / completion degrade gracefully (subshells, `about_of`).
- Declaration-time checks: defaults vs type and choices, bool constraints, short-option
  conflicts, `-h` reserved, variadic last, required after optional, `--strict` only with
  `--choices-from`.
- Values as environment variables + `"$@"` in a fresh process (decision 0005); clearing
  of inherited `FLAG_*`/`ARG_*` verified on a nested call.
- Parsing rules implemented exactly as documented, including the careful `-5` negative
  number rule, `-` alone and options after positionals; helpful "Did you mean".
- Help never interprets `%` or backslashes; `--help` works without the `requires` tools.
- Prompts read `/dev/tty`, never stdin; no terminal = "no"; `_CB_TTY` makes every prompt
  path testable (decision 0009); `NO_COLOR` handling matches no-color.org.
- `contract_checks` in tests/run.sh extracts keywords, options, `CB_*` and `ui::` names
  from the code and fails if the docs miss one: keep it, and extend it (below).
- `set -euo pipefail` in a cmd.sh works with every `ui::` helper (verified without a
  terminal: info, title, confirm → no, ask → default, select → `-d`, `ui::die … 4` → rc 4)
  and with absent flags/args (always exported, empty); refuted hypothesis: `set -u` alone
  in flags.sh breaks nothing. `--no-loud=0` is rejected as "unknown option '--no-loud'".

## Risks for the future

- **Every new local in a function that sources flags.sh is a new collision** (PAR-01):
  add a "hostile flags.sh" fixture (`set -euo pipefail`, `cd /`, `echo`, `dir=`,
  `display=`, `name=`, `IFS=,`) run through run, `--help`, root help, Tab, doctor and deps.
- Roadmap items touch the contract: repeatable flags change "last wins"; inherited flags
  can collide with a subcommand's own flag of the same name (needs a declaration rule);
  command aliases must **not** add a DSL keyword named `alias` (a Bash builtin: defining
  `alias()` would shadow it in flags.sh and in the framework process).
- Changing `int` to canonical decimal (PAR-04) changes the value of `--id 007`-style
  invocations: announce it in the contract change list.
- `ui::select` relies on ANSI cursor control without a `TERM=dumb` fallback (PAR-17).
- The contract has no version marker; `self guide` copies the docs, so AIs will generate
  code for whatever the docs say at that time — undocumented behaviours (Deliverable 1)
  will be used by generated plugins anyway.

## Open questions for the owner

1. Harden `cb::spec_load` (save/restore shell options and cwd, flags.sh stdout to stderr,
   framework locals declared after loading) rather than only documenting "no side
   effects"? **Recommendation: yes** (PAR-01, PAR-02, PAR-11 together, cost S).
2. `int`: export canonical decimal (`08` → `8`) and reject out-of-range values, or reject
   leading zeros? **Recommendation: canonical decimal + range check**, listed as a
   contract change.
3. Start `cmd.sh` with `bash -c '…; source "$0"' <cmd.sh> args` so `$0` is the command?
   **Recommendation: yes** (XS, compatible: only `$0` and `_cb_cmd` change).
4. Should `--required` reject an empty value? **Recommendation: no** (document "given");
   add an explicit option later if a real need appears.
5. Prompts with stderr redirected: print them on the terminal they read from?
   **Recommendation: yes** (PAR-12), keeping stderr when `_CB_TTY` is set.
6. Flags/args on a router: error, warning, or the seed of "inherited flags"?
   **Recommendation: doctor warning now**, inherited flags later as an explicit opt-in.
