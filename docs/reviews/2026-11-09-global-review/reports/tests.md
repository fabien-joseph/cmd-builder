# tests — the test suite (tests/run.sh) and the CI (.github/workflows/tests.yml)

## Scope and method
Read: tests/run.sh (all 739 lines), .github/workflows/tests.yml, docs/testing.md, decisions 0004, 0008, 0009, 0010, 0011, every file of lib/, main.sh, init.sh, builtin/self/**, templates/completion.{bash,zsh}, the relevant parts of README.md, docs/plugin-authoring.md, docs/architecture.md, docs/roadmap.md.
Experiments (all in sandboxes from `mksandbox.sh`, deleted afterwards): CI logs of the last runs through `gh api …/actions/jobs/<id>/logs` (read-only); a timing-instrumented copy of the suite; the suite with `ZDOTDIR` exported; the suite with a temp dir containing a space; a mutation campaign (one literal mutation per sandbox copy, `bash $SB/app/tests/run.sh`, 8 in parallel). Sandbox copies have no `.git`, so their baseline is **441** checks (the handoff-commit check is skipped, see TST-01).
Not covered: zsh, macOS, BusyBox and Bash 4.2 are not installed here (CI logs only); BSD `script` exit status (NOT VERIFIED).
Note: a machine reboot wiped a first mutation run; the results come from a full re-run (42 runs incl. baseline, all completed).

## Grade
- **Coverage of the happy paths: B.** Every documented feature family has end-to-end checks, and the guide, extensions, rename and deps blocks are excellent (executed docs examples, interruption resume, fake package managers). But many error paths, exit codes and options have no check at all (table below), and zsh has none.
- **Assertion strength: D.** `check` is a substring match; 46 of the 277 `check` calls expect a bare number (`0`, `1`, `2`, `6`), which also match 10, 12, 127…; several expectations are one generic word. Mutations prove real regressions pass (see TST-03, TST-04).
- **Isolation / safety: C.** Good idea (copy + isolated HOME + `_CB_TTY`), but `ZDOTDIR` leaks to the developer's real `.zshrc` (TST-02), and fixtures share one mutable config.
- **Maintainability: C.** One 739-line flat script, no sections addressable on their own, shared mutable state (`$cfg`), order-dependent blocks, no skip count; but simple, dependency-free and fast (21 s).
- **CI: B-.** Three useful jobs, pty runs, timeouts, 20/21 green runs; but a silently skipped check, floating runners, tag-pinned actions, no zsh / shellcheck / intermediate Bash versions.

## Findings

### TST-02 Running the suite with `ZDOTDIR` exported writes into the developer's real `.zshrc`
- Severity: major   - Status: VERIFIED
- Aspect: test isolation   - Location: tests/run.sh:156, lib/install.sh:22, init.sh:283
- Evidence: the suite isolates `HOME`/`XDG_CONFIG_HOME` but never unsets `ZDOTDIR`; `init.sh` and `cb::rc_files` use `${ZDOTDIR:-$HOME}/.zshrc`. Zsh users often `export ZDOTDIR` from `~/.zshenv`, so `./tests/run.sh` launched from zsh inherits it. Sandbox with a fake "real" ZDOTDIR outside the suite's temp dir, one probe line (`cp "$ZDOTDIR/.zshrc" probe`) inserted after tests/run.sh:564 in the sandbox copy:
```
before: inode=67478 -rw-------
$ ZDOTDIR=$SB/realzdot bash app/tests/run.sh
438 passed, 3 failed
✗ install: source hint for the user's shell
✗ rename: broken rc block refused
✗ rename: done
after: inode=70890 -rw-------          <- real file rewritten (temp file + mv)
--- real .zshrc after tests/run.sh:564:
# my real zshrc
alias keep=me

# >>> cmd-builder: zz >>>
case ":$PATH:" in *":/…/tmp.VmGeHB3MzJ/home/.local/bin:"*) ;; *) export PATH="/…/home/.local/bin:$PATH" ;; esac
[ -f "/…/home/.config/zz/completion.zsh" ] && . "/…/completion.zsh"
# <<< cmd-builder: zz <<<
```
  The content came back only because later uninstall tests (566, 629-630) removed the block.
- Impact: a zsh contributor with `ZDOTDIR` gets their real rc file edited by every run (new inode: hard links broken, concurrent edits lost); a Ctrl-C between 563 and 566 or inside the rename block (577-631) leaves a stale `cmd-builder: zz`/`yy` block in it; and the suite fails for a reason unrelated to their change.
- Fix: next to tests/run.sh:156: `unset ZDOTDIR CDPATH BASH_ENV ENV` and an explicit `SHELL=/bin/bash` (init.sh hints at 571/573 read the developer's `SHELL`). Then test ZDOTDIR support itself: `ZDOTDIR=$TMP/zdot` → the block lands there. Cost: XS.
- Decision: 0009 fixed the same class of leak (real terminal); this is its rc-file twin.

### TST-01 The Bash 4.2 job silently skips the handoff-commit check (git "dubious ownership"); skips are never counted
- Severity: minor   - Status: VERIFIED
- Aspect: CI / silent skips   - Location: tests/run.sh:122, .github/workflows/tests.yml:64-70
- Evidence: pass counts per job (`gh api repos/{owner}/{repo}/actions/jobs/<id>/logs | grep -oE '[0-9]+ passed, [0-9]+ failed'`):
```
run 42524920126 (main) Linux 442 | macOS 442 | Bash 4.2 441
run 42524819752 (PR)   Linux 442 | macOS 442 | Bash 4.2 441
run 42524431227 (PR)   Linux 442 | macOS 442 | Bash 4.2 441
run 42522449275 (main) Linux 433 | macOS 433 | Bash 4.2 432
```
  The only conditional check is the `git rev-parse --git-dir` guard (tests/run.sh:122). In the container, root works on a checkout owned by the runner uid; `actions/checkout`'s `safe.directory` is set in the host's git config only. Reproduced locally:
```
$ GIT_TEST_ASSUME_DIFFERENT_OWNER=1 git rev-parse --git-dir; echo "status=$?"
fatal: detected dubious ownership in repository at '/home/fabien/repo/fabien/cmd-builder'
status=128
```
  The `fetch-depth: 0` of that job exists only for this check and is wasted.
- Impact: low today (two jobs still run it), but it shows that a guard turning false removes checks invisibly; nobody compares counts across jobs.
- Fix: `git config --global --add safe.directory /w &&` in the container command; count skips (`N passed, N failed, N skipped`) and make CI fail on `skipped > 0` (or `CB_TEST_STRICT=1` turns guards into failures). Cost: XS.
- Decision: 0011, completed, not changed.

### TST-03 Numeric expectations are substring matches: exit 12 passes for 2, 10 offenders pass for 0, status 127 passes for 1
- Severity: major   - Status: VERIFIED (counts); mutation proofs in TST-04
- Aspect: assertion strength   - Location: tests/run.sh:12-21 (`check`), docs/testing.md:35-36 (recommends the pattern)
- Evidence: `check` uses `[[ $out == *"$3"* ]]`. Counting call sites after joining continuation lines (`sed -e :a -e '/\\$/N; s/\\\n//; ta' tests/run.sh | grep -E '^[[:space:]]*check '`):
```
check() call sites: 277
numeric-only expected values: 46   (26 x "0", 12 x "1", 7 x "2", 1 x "6")
  6 via status, 28 via grep -c, 8 via wc -l, 4 via "echo $?"
+ 2 multi-line expectations starting with a number (tests/run.sh:617 $'2\n…', 625 $'0\nlink')
```
  So "0" passes for 10, 20, 100; "1" for 10-19, 21, 127 (command not found!); "2" for 12, 20-29, 127; `status=1` (3 `ui::select` checks, 646-649) passes for `status=127`. All 8 static code-hygiene checks (no `declare -g` in functions 523, no `\~` 526, no `requires` in core 725, no emoji 730, French comments 734…) end in `| wc -l` → "0": they fail at 1-9 offenders but pass again at 10.
  Other weak expectations (one generic word): `"·"` (220, 221), `"created"` (226, 509), `"disabled"` (219, 612), `"demo"` (183), `"greet"` (185), `"leaf"` (191, also contained in the error `unknown subcommand 'leaf'`), `"self"` (184), `"en"`-like short values, `"b"`/`"c"` (650, 652: any output containing the letter passes).
- Impact: regressions of exit codes (a documented contract, docs/architecture.md "Exit codes") and counts can pass CI; proven by the surviving mutants of TST-04.
- Fix (S): add exact helpers and use them for every numeric case:
```bash
check_eq()     { local out; out=$(eval "$2" 2>&1); [[ $out == "$3" ]] && ((pass++)) || fail_msg "$1" "$2" "= $3" "$out"; }
check_status() { local st; eval "$2" >/dev/null 2>&1; st=$?; [[ $st == "$3" ]] && ((pass++)) || fail_msg "$1" "$2" "status $3" "$st"; }
check_count()  { local n; n=$(eval "$2" 2>/dev/null | grep -c -- "$3"); [[ $n == "$4" ]] && ((pass++)) || fail_msg …; }  # trims BSD wc padding
check_absent() { … grep -qF -- "$3" … && fail || pass; }
```
  and replace `"·"`/one-word expectations by a full line. Optionally make `check` refuse a purely numeric `$3` (fail loudly: "use check_eq"). Update docs/testing.md:35-36.

### TST-04 Mutation score 32 %: 28 of 41 meaningful mutants survive, including exit-code, parser, doctor, rc-permission and zsh breakages
- Severity: major   - Status: VERIFIED
- Aspect: test effectiveness   - Location: see table
- Method: one sandbox copy per mutant (`mksandbox.sh`), one literal replacement applied by a `rep file old new` helper that refuses a mutation whose pattern is absent (no no-op mutant), `diff -ru` against the repo recorded, then `bash $SB/app/tests/run.sh` of that copy; 8 in parallel. Baseline (`none`): `441 passed, 0 failed` (no `.git` in copies, TST-01). Scripts: `$SCR/tst-mut/runner.sh`, `$SCR/tst-mut/mutations.sh`.

| # | Mutation (file: change) | Result | Killed by / test that would kill it |
|---|---|---|---|
| 1 | lib/parse.sh:16 `exit 2` → `exit 12` (cb::_parse_err) | **SURVIVED** | 206 `status … "2"` matches "12" (TST-03) → `check_status … 2` |
| 2 | lib/parse.sh:105 short bool in a group drops the rest (`rest=`) | killed | 196 grouped shorts |
| 3 | lib/parse.sh:70 `--no-x` accepted for non-bool flags | **SURVIVED** | `tt demo greet --no-key …` → "unknown option '--no-key'" |
| 4 | lib/parse.sh:149 extra positionals no longer refused | **SURVIVED** | `tt neg -5 kb extra` → "unexpected argument 'extra'", status 2 |
| 5 | lib/parse.sh:78 bool with `=value` accepted | **SURVIVED** | `--loud=1` → "--loud does not take a value" |
| 6 | lib/parse.sh:162 inherited `FLAG_*`/`ARG_*` no longer cleared (documented contract) | **SURVIVED** | `FLAG_LOUD=1 FLAG_GHOST=x tt py` → no `FLAG_GHOST` in env of cmd |
| 7 | lib/spec.sh:229 `--strict` never validates | killed | 347, 350 |
| 8 | lib/spec.sh:364 `-h` short no longer reserved | **SURVIVED** | `flag x -h bool` → "-h is reserved for --help", exit 3 |
| 9 | lib/spec.sh:289 spec error line always `1` | **SURVIVED** | error on line 3 of a flags.sh → `flags.sh:3:` |
| 10 | lib/config.sh:331 symlinked config replaced by a file | killed | 517 |
| 11 | lib/config.sh:326 enable no longer removes the `disable` line | killed | 222, 625 |
| 12 | lib/config.sh:265 `#` comments no longer stripped | **SURVIVED** | `disable core:system # note` → plugin disabled, doctor without "unknown directive" |
| 13 | lib/install.sh:78 uninstall keeps the blank line before the block | killed | 547, 610 |
| 14 | lib/install.sh:88 rc rewrite drops `chmod --reference` (permissions of `~/.bashrc` lost) | **SURVIVED** | `chmod 600 ~/.bashrc`, uninstall, `ls -l` → `-rw-------` |
| 15 | rename/cmd.sh:133 old link removed right after the confirmation (interruption safety, decision 0012) | **SURVIVED** | make step 3/4 fail (read-only `.bashrc` dir) and check the old link still works |
| 16 | lib/ui.sh:326 `ui::confirm` = yes without a terminal (rule 5) | killed | 18 checks |
| 17 | lib/ui.sh:405 `q` returns 10 instead of 1 | **SURVIVED** | 646 `"status=1"` matches "status=10" |
| 18 | lib/ui.sh:400 number out of range accepted | **SURVIVED** | keys `9` with 3 options → not picked |
| 19 | lib/ui.sh:342 `ui::ask` loses its default | **SURVIVED** | no `ui::ask` test at all |
| 20 | lib/router.sh:147 `cb::_check_requires` skipped | killed | 667-669 |
| 21 | lib/router.sh:102 unknown command exits 0 | **SURVIVED** | `status 'tt dem'` = 2 |
| 22 | lib/router.sh:117 missing tool exits 10 | **SURVIVED** | 669 `"1"` matches "10" |
| 23 | lib/router.sh:86 routing stops after one level | killed (41 checks) | but 191 "deep nesting" itself **passed** (`"leaf"` matches `unknown subcommand 'leaf'`) |
| 24 | lib/router.sh:74 unknown root option returns 0 | **SURVIVED** | `tt --nope` → status 2 |
| 25 | lib/plugins.sh:22 core loaded after user (core shadows user) | killed | 216, 217 |
| 26 | lib/util.sh:238 `cb::dq` no longer escapes `$` | **SURVIVED** | `tt self new x -a 'cost $HOME'` → help shows `cost $HOME` |
| 27 | lib/util.sh:174 `sort -u` of merged children removed | **SURVIVED** | `+system/info` + `+system/aaa` → help lists `aaa, info` once each |
| 28 | lib/util.sh:206 `cb::plugin_root_of` returns the default | killed | 449 |
| 29 | 10 French comment lines appended to lib/util.sh | **SURVIVED** | 734 `wc -l` = 10 matches "0" (TST-03) |
| 30 | templates/completion.bash:12 prefix stripping removed | killed | 363, 391 |
| 31 | templates/completion.zsh:25 `compdef` without the command name (zsh completion dead) | **SURVIVED** | any zsh smoke test |
| 32 | lib/complete.sh:99 negative-number rule removed | killed | 398 |
| 33 | lib/complete.sh:41 `-kK <TAB>` treated as expecting a value | **SURVIVED** | `tt __complete -- demo greet -kK ''` → arg candidates, not flag values |
| 34 | lib/help.sh:244 `(required)` no longer shown | **SURVIVED** | `tt demo greet --help` contains `Key (required)` |
| 35 | lib/deps.sh:186 never `sudo` | **SURVIVED** | 690 expects `apt-get install …` (substring of `sudo apt-get …`) → expect `sudo apt-get install cbx-pkg cby` when `EUID != 0` |
| 36 | init.sh:378 rc block appended even when present | killed | 553, 555 (by luck: pre-seeded blocks) |
| 37 | init.sh:349 keyword/builtin names accepted (`./init.sh cd`) | **SURVIVED** | `init.sh cd` → refused, nothing created |
| 38 | doctor/cmd.sh:133 exit 0 with errors | **SURVIVED** | `status 'tt self doctor'` = 1 with the bad spec of 209 |
| 39 | doctor/cmd.sh:57 good link reported as wrong | **SURVIVED** | `tt self doctor` → "Everything is fine." / no `✗` on a clean install |
| 40 | update/cmd.sh:47 `--check` inverted (would update!) | **SURVIVED** | local bare-repo test of `self update --check` |
| 41 | new/cmd.sh:4 `--core` ignored | **SURVIVED** | `tt self new zz --core` → `core/zz/` |

  Score: **13 killed / 41 = 32 %** (28 survivors). Survivors concentrate on: exit codes (1, 21, 22, 24, 38 — 5 of them only because of TST-03), error paths (3, 4, 5, 8, 9, 12, 37), documented options never used (34, 41, 40, 19), safety/idempotence properties (14, 15, 35), zsh (31).
- Impact: CI green says little about exit codes, error messages, doctor, update and zsh, i.e. about the public contract of rule 2 and the safety rules 4/5.
- Fix: add the "would kill it" check of each row (≈ 30 checks, S-M); re-run this campaign (scripts above) as a periodic, non-blocking CI job or a `tests/mutate.sh` contributors can run (pure Bash, ≈ 3 min on 8 cores).

### TST-05 Whole families of documented behaviour have no check (exit codes, DSL errors, `ui::ask`, zsh, `self update`, init idempotence)
- Severity: major   - Status: VERIFIED (by reading tests/run.sh and by the surviving mutants of TST-04)
- Aspect: coverage   - Location: see the coverage map below
- Evidence / summary of the gaps (details in the map): exit code 3 (invalid flags.sh, docs/architecture.md "Exit codes") is never asserted; exit 2 of an unknown command / unknown root option and exit 1 of `self doctor` with errors are never asserted; 14 of the ~17 DSL errors of lib/spec.sh have no check, and the line number of a spec error is only ever checked as `:1:`; `ui::ask` has no functional check at all; the zsh adapter and `self completion zsh` output are never run (documented in docs/testing.md "Not covered yet"); `self update` only runs in a non-git copy (prints "not a git repository, skipped"), so `--check`, `pull --ff-only`, the completion refresh are unchecked; `init.sh` is never run twice with "yes" (rc idempotence, AGENTS.md rule 4); the parser errors `unexpected argument`, `expects a value`, `does not take a value`, unknown short `-z`, `-` alone, `(no value is currently possible)`, `… (Tab to see all)` are unchecked; help elements `(required)`, `(on by default…)`, argument `(choices: …)`, `Examples`, `description` are unchecked; `self new --core`, `--git`, invalid names and `cb::dq` escaping are unchecked.
- Impact: the contract of AGENTS.md rule 2 (public API used by plugins we do not control) includes exit codes and error messages that scripts may rely on; any of these can regress with a green CI.
- Fix: one check per row marked "no" in the map, prioritised in "What is missing entirely" (M, about 60 checks). Kill every surviving mutant of TST-04 first (S).

### TST-06 Test fragility: `tests/run.sh:221` breaks when the temp path contains a space
- Severity: minor   - Status: VERIFIED
- Aspect: test robustness   - Location: tests/run.sh:221
- Evidence: whole suite with `TMPDIR="$SB/tmp dir"` (so `CB_ROOT`, `HOME`, the install path all contain a space):
```
439 passed, 2 failed
✗ rename keeps the core plugin
✗ guide: renamed plugin
```
  Line 221 appends with an unquoted `>>\$XDG_CONFIG_HOME/tt/config` (an "ambiguous redirect" once the path has a space), so `rename core:system sys` is never written and the later guide check (241) fails as a consequence. Good news hidden in it: the framework itself passed the other 439 checks with spaces in every path.
- Fix: quote it (`>>\"\$XDG_CONFIG_HOME/tt/config\"`); add a CI variant or a local option running the suite under a temp dir with a space (cheap regression guard for users who clone under `~/My Projects`). Cost: XS.

### TST-07 The suite is one flat 739-line script with shared, accumulating state; no way to run one section
- Severity: suggestion   - Status: VERIFIED (timing measured)
- Aspect: maintainability   - Location: tests/run.sh:144-739, docs/testing.md:57-60
- Evidence: blocks depend on each other through the single `tt` config (lines 221, 433-435, 440-491, 513-520, 680-681, 706-708 add/filter/restore it by hand, documented as a rule in docs/testing.md:57-60); fixtures created early are reused later (`demo`, `py`, the guide file `$G` from 234 to 321); an early failing `rm -rf` or a forgotten restore shifts every later block. Failure output prints the command and the whole output, which is good, but no line number and no section name. Time per section (instrumented copy, alone, 21.1 s total, 441 checks):
```
6.35 s  38 checks  Extensions (439-495)
4.29 s  37 checks  Dependencies (656-726)
2.20 s  12 checks  negative numbers + doctor examples (393-437)
1.37 s  12 checks  complete flags.sh example (284-305)
0.90 s  20 checks  rename resume / keep-old (613-631)
0.83 s  33 checks  guide (232-268)
0.27 s 130 checks  doc consistency
```
  The cost is dominated by `tt self doctor` (about 25 calls) and `self plugins`, each loading every plugin.
- Fix (pure Bash, rule 1 kept): split into `tests/lib.sh` (check helpers, sandbox setup), and `tests/NN-<section>.sh` files, each starting from a fresh `$TMP` copy or at least a freshly written config (`reset_config` helper instead of manual save/filter/restore); `tests/run.sh [section...]` runs all or some (`./tests/run.sh parsing completion`), prints `section: N passed`, and the failure line `✗ [completion] tests/10-completion.sh:42 …` (use `${BASH_LINENO[0]}` in `check`). Sections can run in parallel (`&` + `wait`, each with its own sandbox): the suite would drop well below 10 s.
  On bats: decision 0004 forbids dependencies for *users*; a test framework used only by contributors and CI does not violate it, but it adds a vendored or installed tool (bats-core + bats-assert as git submodules), a second idiom for contributors and AI agents, and `bats` itself needs Bash ≥ 3.2 (fine). Recommendation: keep pure Bash (the needs are small: exact asserts, sections, line numbers, skips) and record the choice in a decision.
- Cost: M.

### TST-08 CI gaps: floating runners, tag-pinned actions, weak macOS pty assertion, no zsh/shellcheck/intermediate Bash, no BusyBox-only run
- Severity: minor   - Status: VERIFIED (workflow + logs) / NOT VERIFIED (BSD `script` exit status)
- Aspect: CI   - Location: .github/workflows/tests.yml:16, 19, 34, 53-54, 67-70
- Evidence and points:
  - `runs-on: ubuntu-latest` / `macos-latest` float: logs show Bash 5.3.9 (Linux) and 5.3.20 arm64 (macOS) today; an image switch changes the tested environment silently. Pin (`ubuntu-24.04`, `macos-15`) and bump on purpose.
  - `actions/checkout@v5` is pinned by tag, not by commit SHA (supply-chain hardening; `permissions: contents: read` limits the damage, good). Pin by SHA with a comment, plus Dependabot for actions.
  - macOS pty step: `script -q /dev/null ./tests/run.sh | tee pty.log; grep -q ' 0 failed' pty.log` ignores the exit status and would accept a truncated run that printed `0 passed, 0 failed`; it also cannot detect a drop in the number of checks. Better: `grep -qE '^[0-9]{3,} passed, 0 failed' pty.log` and compare with the non-pty count.
  - No job compares pass counts across jobs (TST-01 went unnoticed).
  - No zsh job although `templates/completion.zsh` ships to every zsh user (zsh is `apt install zsh` / preinstalled on macOS runners): a smoke test `zsh -fc 'autoload -Uz compinit; compinit; source <(tt self completion zsh); …'` or a `zpty` session would at least catch syntax errors (mutant `zsh_broken` survives, TST-04).
  - No shellcheck (`shellcheck -s bash lib/*.sh main.sh init.sh builtin/**/*.sh`), no `bash -n` of `builtin/` and `templates/completion.bash` (the syntax step only lists lib/, main.sh, init.sh, tests/run.sh).
  - Bash 4.2 and 5.3 only: 4.3/4.4/5.0/5.1/5.2 are untested (e.g. `patsub_replacement` appeared in 5.2, `${var@Q}` changes in 4.4); a matrix of `bash:4.4`, `bash:5.0`, `bash:5.1`, `bash:5.2` images is cheap (≈25 s each).
  - The 4.2 job installs GNU coreutils/sed/grep/findutils/gawk/diffutils: BusyBox tools themselves (Alpine users, small containers) are never exercised. Add one job on plain `alpine` + `apk add bash git` only.
  - Timeouts exist (10/15 min) and runs take 20-90 s; history: 21 runs, 20 green, the only red one is the first CI run (feat/ci, real 4.2 bug, decision 0011). No flakiness seen.
- Cost: S (pins, asserts, bash -n, matrix), M (zsh smoke test).

## Coverage map (task 1)
Line numbers are tests/run.sh. "weak" = asserted only by a substring that broken code can also print.

| Feature | Tested? | Checks | Missing |
|---|---|---|---|
| Root help (`tt`, `--help`) | yes | 183, 184 | `-h`; conflict warning on stderr (help.sh:285-288) |
| Unknown root option `tt --nope` (exit 2) | **no** | — | message + status |
| Unknown command + suggestion | partly | 189 | exit 2; "Plugin X is disabled: enable" hint (router.sh:94-98) |
| Router: no cmd → help / unknown sub | yes | 185, 190 | unknown option of a router (router.sh:133); exit 2 |
| Deep nesting | weak | 191 (`"leaf"` also matches the error) | assert the exact output line |
| Non-bash `cmd` executable | yes | 192 | `cmd` not executable; cmd.sh preferred over cmd |
| `_x`, `.x` directories ignored | **no** | — | fixture `_lib/`, `.git/` under a plugin |
| `self` reserved as plugin dir (plugins.sh:38) | **no** | 230 tests only `self new self` | `plugins/self/` state "reserved" |
| CB_* variables | partly | 227 (CB_COMMAND), 346, 449 (CB_COMMAND_DIR, CB_PLUGIN_ROOT) | CB_CONFIG_DIR, CB_ROOT, CB_NAME in cmd.sh |
| Parsing: `--x`, `--x=v`, `--x v`, `--no-x`, `-x`, `-x v`, `-xv`, `-abc`, `--`, options anywhere | yes | 195-200 | `-` alone; `-5` when `-5` is a declared short |
| Parsing: negative number positional | yes | 397 | negative int value `-n -5` |
| Parse errors | partly | 201-205, 347, 350 | unknown short `-z`; `expects a value`; `does not take a value`; `unexpected argument` (+ subcommand hint); `(no value is currently possible)`; `… (Tab to see all)`; suggestion `Did you mean: --…` |
| Exit codes 2 / 3 | weak / **no** | 206 (`"2"` substring) | exit 3 never asserted |
| FLAG_/ARG_ export, `-`→`_`, inherited values cleared | partly | 195, 303; keep-old indirectly | ARG with a dash; nested call leak (see mutant `export_nounset`) |
| DSL keywords about/description/example/flag/arg/requires | partly | many | `description` in help; `Examples` section in help |
| DSL errors (spec.sh, ~17 cases) | 3 + 3 requires | 210, 353, 355, 710-714 | invalid names, `-h` reserved, declared twice, short reused, bool + choices/required, bool default, int default, default not in choices, variadic not last, required after optional, unknown option; line ≠ 1 |
| `--choices`, `--choices-from`, `--strict`, `--default`, `--required`, `--optional`, `--variadic` | yes | 187-204, 343-355 | variadic values validated against choices |
| `requires` + `--optional`, `--<pm> pkg`, `-` | yes | 665-715 | unknown option of requires |
| Help: usage, choices, default, Tab hint, Arguments, Commands | yes | 186-188, 278, 301, 351, 451, 463 | `(required)`, `(on by default…)`, arg `(choices: …)`, Examples, description, 30-col cap |
| Completion engine: root, sub, flags, choices, dynamic, prefix, `--x=`, negative numbers, extensions, missing tools | yes | 324-328, 343-361, 388-390, 398, 452-453, 671 | `--` in completion; grouped short `-lk <TAB>`; root `-<TAB>` |
| Bash adapter | yes | 329, 363-365, 383-384, 391 | `-o default` fallback; root names with `-` (function name) |
| Zsh adapter, `self completion zsh` | **no** | (328 only lists `zsh` as a candidate) | everything (documented gap) |
| `self new` | yes | 226-230, 446-464, 505-511 | `--core`, `--git`, invalid name, `cb::dq` of `"`/`$`/backquote in `-a` |
| `self plugins`, enable/disable | yes | 217-222, 358-362, 454, 478-487, 732 | "already enabled/disabled" |
| `self doctor` | partly | 211, 401-437, 455-493, 676-677, 705, 707 | exit 1 on errors; Environment section (link, completion files, git); "Everything is fine."; unknown directive; config mentions a missing id; cmd not executable; cmd.sh+cmd; "does nothing" |
| `self guide` | yes (excellent) | 232-321 | — |
| `self update` | **no** (manual) | 704 runs it in a non-git copy | `--check`, ff-only, plugins with .git, completion refresh (local bare repos, cf. docs/roadmap.md recipe) |
| `self rename` | yes (very good) | 577-631 | ZDOTDIR, symlinked rc, zsh block replacement, "not installed" refusal, existing-command warning, rc permissions, interruption *during* the steps (old link must survive) |
| `self deps` + install/update/managers | yes (very good) | 656-726 | `managers remove` behaviour; `sudo` prefix asserted; pm order; pacman/zypper/apk install, brew update commands; `pm_ask` → none |
| init.sh install | partly | 553-575 | second run with "yes" (rc idempotence); invalid name; keyword/builtin; foreign link "Replace it?"; command already in PATH; PATH warning |
| init.sh uninstall | partly | 541-548, 565-567, 627-630 | symlinked rc; permissions kept; foreign link kept; ZDOTDIR; CRLF rc; interrupted re-run (decision 0007) |
| Bash version guard | yes | 529-530 + CI job | — |
| ui::info/success/warn/error/die/title | indirect | everywhere, 732 | `ui::die` custom code (only via rename 592) |
| ui::confirm | yes | 310-313, 563-567, 589-591, 678-679 | Enter = default; `yes`; `[Y/n]` default y with empty answer |
| ui::ask | **no** | — | everything |
| ui::select | yes | 633-654 | number out of range; `status=1` weak; pty drawing (NOT tested, needs `script`) |
| Colours / NO_COLOR | **no** | — | (needs a pty) |
| Config: disable / rename / package-manager | yes | 219-221, 433, 476-490, 516-519, 571-572, 680-707 | comments `#` and blank lines; `expected 'disable …'` / `'rename …'` / unknown directive errors |
| Config kept as a symlink | yes | 513-520 | — |
| Extensions (decision 0013) | yes (excellent) | 439-495 | `sort -u` merge with a shadowing command (mutant `children_nosort`) |
| Doc consistency | yes | 37-131, 738 | handoff commit skipped without git (TST-01) |
| Static hygiene (declare -g, `\~`, emoji, French) | weak | 523-535, 725-735 | `wc -l` → "0" passes at 10 offenders (TST-03) |

## What is missing entirely (task 6), by priority
1. Exact assertions (`check_eq` / `check_status` / `check_count`) — TST-03; then the surviving mutants of TST-04.
2. Isolation: `unset ZDOTDIR …` + a ZDOTDIR test (TST-02).
3. Idempotence (rule 4): `init.sh` twice with "yes"; uninstall interrupted then re-run; rc permissions and symlinked rc during uninstall and rename.
4. Exit codes 1/2/3 of every documented case (docs/architecture.md table) and the untested parse/DSL errors.
5. zsh: smoke test in CI (zsh installed on the runner), at least `zsh -n` of the generated script and candidates through `_describe` in a `zpty` session.
6. `self update` with local bare repositories (the manual recipe of docs/roadmap.md made automatic: no network needed).
7. Interactive pty test of `ui::select` drawing and of a confirm under `script` with keys piped in.
8. Paths with spaces (TST-06), CRLF `flags.sh`/rc files, `-` and digits in root names.

## What is good and must be kept
- End-to-end through the real entry point (`tt` symlink), on a copy, with isolated HOME: tests what users run.
- `_CB_TTY` (decision 0009) makes both "yes" and "no" paths testable without a terminal, and the pty CI runs prove nothing hangs.
- Executed documentation: the worked example of the guide and the complete `flags.sh` example are extracted and run (decision 0010); doc-consistency checks extract facts from the code. Rare and valuable.
- Fake `apt-get`/`sudo` stubs for `self deps`; simulated interruption for `self rename`.
- Pure Bash, no dependency, 21 s, runs on Bash 4.2, BSD and GNU tools.

## Risks for the future
- Every new check written with the current helpers inherits the substring weakness; the docs teach it (docs/testing.md:35-36).
- Shared config state makes each new block more likely to break a later one; the suite will get slower linearly (`self doctor` calls).
- zsh users are a likely majority on macOS and have zero automated protection.

## Open questions for the owner
1. Accept exact-match helpers and a rule "no bare-number expectation with `check`" (enforced by `check` itself)? Recommended: yes.
2. Split `tests/run.sh` into sections runnable alone (pure Bash) rather than adopting bats? Recommended: pure Bash, with a short decision record.
3. Add a zsh smoke job and a Bash 4.4/5.0/5.1/5.2 matrix to CI? Recommended: yes, both are cheap.
4. Should CI fail when any check is skipped? Recommended: yes (and fix the safe.directory of the 4.2 job).

## Summary of findings
major: TST-02 (ZDOTDIR leak to the real .zshrc), TST-03 (numeric substring assertions), TST-04 (mutation score 32 %), TST-05 (untested families) — minor: TST-01 (silent skip in the 4.2 job), TST-06 (space in path), TST-08 (CI hardening) — suggestion: TST-07 (structure).
