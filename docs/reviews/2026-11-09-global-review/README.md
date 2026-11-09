# cmd-builder — global review (2026-11-09)

Reviewed commit: `201aa62` (branch `docs/wrap-up-features`, = `main` + wrap-up PR #14, merged).
Team: 9 reviewers (parser/contract, routing/plugins/config, completion/performance, security,
robustness/idempotence, portability, tests/CI, docs, architecture/product) + 1 evaluator of the
AI guide (7 simulated chat answers: 5 Haiku, 2 Sonnet, Read/Write tools only, then every
answer executed in a fresh sandbox). Everything ran in sandboxes (copy of the project +
isolated HOME); the repository and the owner's install were never modified.

Detailed reports with full evidence (reproductions + outputs) are next to this file, in
`reports/` (`parser.md`, `routing.md`, `completion.md`, `security.md`, `robustness.md`,
`portability.md`, `tests.md`, `docs.md`, `architecture.md`, `guide-eval.md`). This file is the
consolidated, deduplicated view. IDs refer to those reports.

**Lead verification.** I re-ran myself, in my own sandboxes, the critical finding and most
majors: ROB-01, PAR-01, PAR-02, PAR-03, PAR-04, PAR-08, DOC-01, DOC-02, DOC-03 (= RTE-01 =
ARC-01), RTE-04, ROB-05, CMP-01, POR-01, POR-05 (Turkish locale compiled with `localedef`),
TST-03 (harness false positives). All reproduced as described. Line numbers of two reports
(parser, docs) were wrong for `lib/` files and have been recomputed by their authors.
Duplicates merged below; no false positive was found among the re-run items.

**Incidents during the review (disclosed).** (1) A reboot of the machine wiped `/tmp` mid-review:
sandboxes and logs were lost; reports were recovered from the agents' transcripts or rewritten
from their captured outputs (the evidence in `routing.md` RTE-05..18, `robustness.md`,
`security.md`, `portability.md`, `tests.md`, `completion.md` was copied from pre-reboot output,
not re-produced). (2) During a pseudo-terminal test of completion, a test line `sudo tt …` was
validated with Enter: the real `sudo` prompted and read piped lines as a password: **one failed
sudo attempt is logged on the machine**, nothing was executed. (3) The user-level agent
`chat-ai-simulator` was not loaded in this session at first; the simulations used its exact
definition in generic agents restricted by instruction to Read/Write; their transcripts were
audited: each did exactly 1 Read (the guide) and 1 Write (its answer).

---

## 1. Executive summary

cmd-builder is a small (~3,300 lines), clean, well-documented framework with an unusual and
valuable discipline: decision records for every structural choice, docs checked against the
code by tests, an AI guide generated from the reference, a CI on Linux/macOS/Bash 4.2. The
parser, help and DSL behave exactly as documented; no untrusted input reaches any `eval`.

The review nevertheless found **1 critical issue and ~20 distinct major issues**, in five
clusters:

1. **Data safety of system-changing commands** — `self rename` back to the old name after
   `--keep-old` **deletes the user's config** and says "Done" (ROB-01, critical); uninstall of
   a name that owns a shared config deletes it for the other name; a rename leaves plugin data
   behind; a failed link creation still removes the old command; `self update` exits 0 on
   failure. Rule 4 (idempotent, resumable) is well applied to the *happy* interruptions, but
   the failure paths and the `--keep-old` combinations were not tested.
2. **The AI guide's paste format can destroy or execute user code** — a file containing its
   own `EOF` line truncates the file and runs the rest in the user's shell; a refused
   `self new` is followed by blocks that overwrite the existing command; the "Try it" step of
   real AI answers deleted real data (a note) and wrote test files in the home directory; WSL
   is flagged but not explained (false red alert on every run of both `system disk` answers).
3. **`flags.sh` is not isolated** — it is sourced inside framework functions: a helper variable
   named `dir`/`display`/`top` corrupts routing and `CB_*` values, `set -euo pipefail` (a
   habit of many AIs) makes every run with an argument exit 1 silently, `cd`/`echo` leak into
   the command. In `cmd.sh`, `$0` is `lib/run.sh`.
4. **Routing knowledge is duplicated** (4 copies that already disagree): `self new` ignores
   renames and re-creates the shadowing bug decision 0013 fixed; options before a subcommand
   silently run the parent; examples do not follow renames.
5. **Tests are weaker than their count suggests** — 442 checks but a mutation score of
   **32 %** (13/41 killed): `check` matches substrings, so 46 numeric expectations accept
   wrong exit codes/counts (127 passes for "2"); whole families (exit codes, `self update`,
   zsh, idempotence of init) are untested; the suite writes into the developer's real
   `.zshrc` when `ZDOTDIR` is exported; the Bash 4.2 job silently skips a check.

Also notable: locale-dependent name validation (under `tr_TR.UTF-8`, `tt system info` itself
fails), no `.gitattributes` (a Windows-side clone is unusable from WSL), Tab inserts dynamic
candidates unquoted, no version number for a contract declared public, and performance that
is good up to ~25-30 plugins (Tab ≈ 20-60 ms) but degrades for whole-tree commands.

None of this is hard to fix: almost every fix is XS or S. The plan (section 6) groups them
into 10 pull requests; the first two (data safety, then a trustworthy test harness) should
come before any new feature.

## 2. Grades per aspect

| # | Aspect | Grade | In one sentence |
|---|---|---|---|
| 1 | Architecture | B- | Clear process model and layout; but routing in 4 copies, flags.sh sourced in framework scope, many implicit globals/out-parameters; extensions are elegant. |
| 2 | Plugin contract | B- | Small, coherent, documented; holes: flags.sh isolation, `$0`, `int` semantics, collisions (`no-x`, `a-b`/`a_b`), no version. |
| 3 | Correctness | C+ | Parser/help A-level; `self new` + rename, rename/uninstall data loss, options before subcommands, completion quoting. |
| 4 | Security | B | No injection into `eval`; risks are in the AI paste format and in the undocumented trust model of third-party plugins. |
| 5 | Robustness / idempotence | C | Resumable happy paths, but failure paths report success, critical config loss with `--keep-old`. |
| 6 | Portability | B- | Bash 4.2/macOS/paths with special chars OK; locale, CRLF/.gitattributes, macOS login shells, BusyBox chmod. |
| 7 | Performance | B | 20-30 ms per call, Tab < 100 ms up to ~25-30 plugins; 2 processes per plugin at root; doctor fork-bound on big trees. |
| 8 | CLI UX | B | Good messages with fixes; gaps: no `--version`, invisible prompts with `2>/dev/null`, silent parent run, false successes. |
| 9 | Tests | C | Many checks, real sandbox, doc checks; but substring matching, 32 % mutation score, untested families, shared state. |
| 10 | CI | B- | Right platforms incl. real 4.2; silent skip, floating runners, no zsh, no shellcheck. |
| 11 | Documentation | B | Accurate on most quoted facts; outdated decisions, duplication README/reference, missing "stability/debugging" docs. |
| 12 | AI guide | C | Complete and generated; dangerous paste format, no data-safety rule for "Try it", WSL not explained, renamed plugins mislead. Answers worked 7/7. |
| 13 | Maintainability / conventions | B | Conventions mostly followed; duplications, long functions (`cb::complete`, `cb::parse`, doctor), undocumented globals. |
| 14 | Product | B | Coherent scope; missing versioning, `--version`, `self which/edit`, trust model; roadmap order should change. |

## 3. Findings by severity

Format: **ID(s)** — problem — evidence pointer — impact — fix (cost). Cost scale: XS < 30 min,
S ≤ 2 h, M ½ day, L 1-2 days (code + tests + docs).

### Critical

**C1. ROB-01** — `tt self rename xx --keep-old` then `xx self rename tt` deletes the real config
and writes a default one; "Done", exit 0. Location: `builtin/self/rename/cmd.sh:87-96` (the
"identical copy" branch removes `$oc`, which is the real file, while `$nc` is the link to it).
Lead repro: disable line lost, `~/.config/xx/config` = 406-byte default. Impact: loss of every
`disable`/`rename`/`package-manager` line, silently. Fix: resolve both paths with
`cb::realpath` before any `rm`; when the old config is the target of the new link, move the
file and replace the link; test the round trip both ways (S).

### Major

**M1. ROB-02** — `init.sh --uninstall <owner name>` after `--keep-old` removes the shared config
for the other name (prompt default yes, sharing not mentioned). Fix: detect incoming links
(`same_config` logic) and refuse/explain; default no (S).

**M2. ROB-03 (+ GDE-04)** — `self rename` moves only `config`; plugin data under
`$CB_CONFIG_DIR` (where the guide tells AIs to store settings) stays in the old directory, while
the plan and `--help` say the directory moves. Fix: move every user file of the directory (all
but generated completion files), list them in the plan (S).

**M3. ROB-04** — when `ln` of the new link fails, the old link is still removed: no command
left, "Done", exit 0, not resumable. Fix: stop on any failed step (`|| ui::die`), old link last
only if the new one is ours (XS).

**M4. ROB-05 (+ ROB-06/ARC-03, SEC-04)** — `self update` always exits 0 ("update failed",
unreachable remote, no upstream → "Everything is up to date"), `--check` exits 0 with updates
available; after pulling, the old in-memory code sources new files (shown to break). Fix:
non-zero exit on any failure, `--check` exit 10 when updates exist (documented), re-exec the
new `main.sh` after pulling the main repo; show `git log --stat` (sanitised) before confirming
(S).

**M5. RTE-01 = DOC-03 = ARC-01** — `self new` resolves words by directory name: with
`rename core:system sys`, `tt self new sys net` creates `plugins/sys/`, which shadows the
official plugin (`tt sys info` → unknown subcommand) — the exact bug decision 0013 fixed, and
the guide leads the AI there. Fix: resolve the first word through exposed names
(`_CB_PLUGIN_ID`), print exposed paths; test (S). Best done with M8.

**M6. DOC-01 = SEC-01** — guide paste format `cat > '<path>' <<'EOF'`: a generated file with its
own `EOF` line (any `cat <<EOF` usage text) is truncated and **the rest runs in the user's
interactive shell** (lead repro under `bash -i`). Fix: unique delimiter (`CB_FILE_END`) in the
template, worked example and decision 0010, plus a rule and a test (XS).

**M7. DOC-02 = SEC-02** — when `self new` refuses (command exists; unknown with `--no-commands`),
the next pasted blocks overwrite the user's `cmd.sh` and parent `flags.sh` (lead repro). Fix:
the guide chains `self new … && { cat > … ; }` in one block, tells the user to stop on `✗`,
and allows asking about existing names in `--no-commands` mode; evaluation case added (S).

**M8. PAR-01** — flags.sh is sourced inside `cb::run`/`cb::complete`/doctor functions: a top-level
helper variable (`dir=…`, `display=…`, `top=…`) overwrites framework locals → declared flag
"unknown", wrong `CB_COMMAND`/`CB_PLUGIN_ROOT` (lead repro). Fix: load the spec before declaring
locals / `_cb_`-prefixed locals in every loader; document variable prefixing; hostile-fixture
test (S).

**M9. PAR-02** — `set -euo pipefail` in flags.sh: every run with a positional exits 1 silently
(`((i++))` in `lib/parse.sh:147`); `cd`/`echo` in flags.sh change cmd.sh's directory and
pollute stdout/`--help`. Fix: `cb::spec_load` saves/restores shell options and `PWD`, sends
flags.sh stdout to stderr; `((++i))` style in lib (S).

**M10. PAR-03 = DOC-05** — in cmd.sh `$0` is `lib/run.sh` (`$(dirname "$0")/_lib` breaks) and
`_cb_cmd` leaks. Fix: `exec "$BASH" -c 'source "$CB_ROOT/lib/ui.sh"; source "$0"' "$exe" args`
(prototype verified), document "sourced; use `CB_COMMAND_DIR`/`CB_PLUGIN_ROOT`" (XS).

**M11. PAR-04** — `int` accepts `08` (crashes `$((…))`), `010` (= 8), 30-digit values (wrap).
Fix: export canonical decimal, reject out of 64-bit range; contract change noted (S).

**M12. RTE-04** — an option before a subcommand silently runs the parent when it has a `cmd.sh`
and an `arg` (`tt backup -v restore` → parent with `target=restore`); README says "options may
be placed anywhere". Fix: keep decision 0001's rule but warn/error when a positional equals a
child name after options, document "options after the subcommand" and `--` (S).

**M13. SEC-03** — a third-party plugin's flags.sh runs at `tt`, `tt --help`, the first Tab,
`self doctor/guide/deps/update --check`, before it is ever run; the README suggests
`git clone … plugins/` without a word. Fix: document the trust model (README, plugin-authoring,
future `self plugins install` warning with default no) (XS doc; S with the future command).

**M14. CMP-01** — dynamic candidates are inserted unquoted: `my notes.txt` becomes 2 words,
`$HOME` expands, a quote opens a string (verified in a real interactive bash). Fix: `printf %q`
per candidate in the bash adapter (XS); rebuilding words from COMP_WORDS also lifts the
"quoted words" limitation (S).

**M15. POR-05 (= RTE-08)** — validation regexes use `[a-z]` ranges and `${x^^}`: under
`tr_TR.UTF-8`, `i` is not in `[a-z]` → `tt system info`, `self plugins`, `self new` fail
(lead repro); under `en_US.UTF-8`, `café` validates then `export FLAG_CAFÉ` fails. Fix: explicit
ASCII letter lists, `LC_ALL=C` around case conversion, convention + CI check (S).

**M16. POR-01** — no `.gitattributes`: a clone made with Git for Windows defaults
(`autocrlf=true`) gives `env: 'bash\r'` at install. Fix: `* text=auto eol=lf` (XS).

**M17. POR-06** (NOT VERIFIED on macOS) — the rc block goes to `~/.bashrc`, which macOS login
shells do not read: no PATH, no completion for Homebrew-bash users. Fix: on Darwin with a bash
login shell, also offer `~/.bash_profile` (sourcing `~/.bashrc`) (S).

**M18. TST-02** — with `ZDOTDIR` exported, `tests/run.sh` writes a block into the developer's
real `.zshrc` (rule 3 of the brief / rule 4 spirit). Fix: `unset ZDOTDIR` and pin every
environment input in the sandbox (XS). (The owner's machine is not affected: `ZDOTDIR` unset,
no `.zshrc`; verified.)

**M19. TST-03/04/05** — harness false positives (numeric substring matching, 46 checks),
mutation score 32 % (survivors: wrong exit codes, doctor exiting 0 on errors, rc mode loss,
`--check` inverted, `ui::ask` default lost, `cb::dq` not escaping `$`, early old-link removal…),
untested families. Fix: `check_eq` / `check_status` / `check_count` helpers, convert the 46
checks, add the tests listed in `tests.md` for each survivor (M).

**M20. GDE-01** — the guide's "Try it" step has no data-safety rule: a real answer ran
`mu notes rm 1 -y` (deletes the user's oldest real note), others wrote `~/empty.json`,
`~/empty-test`. Fix: rule "try runs never change real data: `--dry-run`, test data in
`mktemp -d`, never `--yes`, nothing in `$HOME`", and make the worked example follow it (XS).

**M21. GDE-02 + DOC-14 + DOC-06** — the System row (WSL2) is not explained: both `system disk`
answers raise a false red alert on every run (read-only WSL image at 100 %), browser openers are
guessed; the guide lacks distribution and package manager, and contradicts itself on asking
about the system. Fix: Setup rows for distribution (`/etc/os-release`), package managers,
absolute config dir; a WSL paragraph when detected (S).

### Minor (grouped by theme)

- **Contract / DSL**: PAR-05 = ARC-07 glob-expanded `--choices` (flags.sh invalid depending on
  cwd); PAR-06 `no-x` vs bool `x`; PAR-07 = ARC-06 `a-b`/`a_b` same `ARG_`; PAR-08 `requires`
  satisfied by keywords/builtins/functions (`requires time`) → `type -P`; PAR-09
  `--required --default`; PAR-10 = ARC-08 = RTE-15 flags/args/requires on a router ignored;
  PAR-11 flags.sh sees stale/absent `CB_COMMAND*`; PAR-14 `--=x` Bash error; PAR-16 help
  cosmetics; PAR-13 `ui::select` >9 options and `-d` outside options; PAR-15 colours fixed at
  load; PAR-17 redraw of wrapped lines (not verified).
- **Prompts**: PAR-12 = ROB-14 prompts on stderr but read `/dev/tty`: with `2>/dev/null` the
  question is invisible yet answerable. ROB-17 "remove your configuration?" defaults to yes;
  ROB-18 / SEC-07 `self deps install` saves a manager before the refusal, runs sudo on Enter.
- **Routing / doctor**: RTE-02 `self new` under a disabled official plugin reports success;
  RTE-03 symlink loop → exponential walk, doctor/guide/deps/update hang; RTE-05 = ARC-12
  examples ignore renames; RTE-09/DOC-09 invalid directory names silently ignored; RTE-10
  doctor skips inactive extensions; RTE-11 examples with pipes flagged; RTE-12 misleading
  conflict hints; RTE-16 `self guide -o -`; RTE-17 column overflow; RTE-18 `tt ''`, `tt -- x`,
  no `--version`, no `tt help`.
- **Config & files**: RTE-06 CRLF config ignored entirely; RTE-07 config path that is a
  directory/read-only (false success, raw `mv` prompt — rule 5); ARC-05 = SEC-05 config
  rewrites reset the mode (600 → 644) and are duplicated code; ROB-07 = POR-07 rc mode lost on
  BusyBox; SEC-13 predictable temp names; ROB-15 stow-folded config dir.
- **Install / uninstall**: ROB-08 CRLF/indented marker → false "block removed"; ROB-09 init
  prints success when writes failed; ROB-10 half-written rc block accepted as "configured";
  ROB-11 `ZDOTDIR`/`XDG_CONFIG_HOME` changes between install and uninstall; ROB-12 "Replace
  it?" deletes the user's own script without backup; POR-04 rc block writes `$HOME` unescaped
  (a backtick in HOME runs at every shell start); SEC-11 = POR-08 exported `CDPATH` breaks
  entry scripts; POR-03 POSIX-mode Bash passes the guard then dies.
- **Deps**: ROB-13 `self deps update` assumes one manager owns every tool, stops at first failure.
- **Security hygiene**: SEC-06 `_CB_NO_DYNAMIC` / `_CB_TTY` honoured from the environment;
  SEC-08 = CMP-03 = POR-09 root name unescaped/colliding in completion templates;
  SEC-09 token as a flag in the reference example, no hidden input; SEC-10 `git` choices
  snippets run hooks of an untrusted repo at Tab.
- **Completion / perf**: CMP-02 snippets inherit stdin (eat typed keys / piped input); CMP-04
  2 processes per plugin at root (~300 ms at 100 plugins); CMP-06 zsh adapter calls `compinit`
  (static); POR-02 CRLF in flags.sh/cmd.sh undetected by doctor.
- **Tests / CI**: TST-01 Bash 4.2 job skips the handoff check silently (441 vs 442); TST-06
  space in temp path; TST-08 floating runners, tag-pinned actions, weak macOS pty grep, no
  zsh/shellcheck/intermediate Bash.
- **Docs**: DOC-04 config dir given as `~/.config/<name>` (wrong under XDG, unusable in quotes),
  no `mkdir -p`; DOC-07 decisions 0001/0008/0010 outdated, not marked amended; DOC-08 AGENTS.md
  has no "sync with main" step; DOC-10 six inaccuracies in architecture.md tables; DOC-11
  README duplicates the reference and drifted; DOC-12 guide heading levels; ROB-16 exit-code
  table incomplete.
- **Architecture**: ARC-02 routing in 4 copies (main, completion, doctor, self new); ARC-09
  undocumented globals/out-parameters/dynamic scope; ARC-10 duplications (symbols, bootstrap,
  PM lists, "Did you mean"); ARC-11 no version number (shared plugin using a new DSL option
  fails with exit 3 and no "update" hint).
- **Guide quality**: GDE-03 grey-areas list invites needless questions (Sonnet asked 6, 2
  already settled); GDE-05 odd values from other tools (`-` in df, `null` in jq, detached
  HEAD, newlines in file names) missed by 4/7 answers.

### Suggestions

ARC-04 symlinked subcommand = free alias but listed twice (basis for the alias feature);
ARC-13 layout knowledge in `util.sh`; RTE-13 better `cb::suggest`; RTE-14 "Did you mean" after
a command with its own `cmd.sh` (design in `routing.md`); CMP-05/08 fork reduction (13
processes per call); CMP-07 duplicate candidates; DOC-13 stability/debugging/changelog docs;
DOC-15 AGENTS.md table indentation; DOC-16 roadmap order; GDE-06/07; SEC-12 `--no-commands`
still sends path/kernel; POR-10 static WSL/zsh/BusyBox notes; TST-07 split the suite.

## 4. What is good and must be kept

- One directory per command, `flags.sh` + `cmd.sh`, values as env vars in a fresh process
  (decisions 0001, 0005): simple, language-agnostic, proven by the parser review (every
  documented parse rule behaves exactly as written; help never interprets `%`/backslashes).
- No untrusted input reaches `eval`: `--choices-from` and package commands only carry plugin
  code or `printf %q`-quoted validated names; `cb::dq` resisted 17 injection payloads.
- Prompts read `/dev/tty`, no terminal = no, `_CB_TTY` testability (0009); `NO_COLOR` per
  no-color.org; messages on stderr, data on stdout.
- Extensions `plugins/+x/` (0013): elegant, visible in the tree, correctly followed by every
  walker except `self new`.
- Decision records with rejected alternatives; doc checks that fail on undocumented
  contract items; the AI guide generated from the reference, with its worked example
  executed by the tests (0010). The 7 AI answers all produced working commands, used
  extensions, `requires` + `self deps install`, `ui::select` and confirmations correctly.
- Real Bash 4.2 in CI (0011) — it found two real bugs; sandboxed test suite; atomic rc rewrites
  with markers; paths with spaces/special characters work (except the rc escaping).

## 5. Risks for the future

- **Every roadmap item touches routing or the DSL** (aliases, hidden commands, inherited and
  repeatable flags): doing them before ARC-02 (single router) means 4 implementations each.
- **No version number** while the contract is public: shared plugins will break silently
  across machines as soon as the DSL grows (ARC-11).
- **Tests give false confidence** (32 % mutation score): fixes made before the harness is
  hardened may regress unnoticed.
- **The guide scales the risk**: every AI answer pasted by a user executes; one bad pattern in
  the template (EOF, overwrite, destructive "try") replicates across all users.
- **Trust model implicit**: `self plugins install` without a documented trust model would make
  third-party code run at Tab.
- **Locale/CRLF/WSL** issues appear only on machines the CI does not model.
- Docs written three times (reference, README, guide rules): drift is already visible.

## 6. Correction plan — ordered batches (one PR each)

| Lot | Content (IDs) | Cost | Why this order |
|---|---|---|---|
| **1. Data safety** | C1 ROB-01, M1 ROB-02, M3 ROB-04, M2 ROB-03, ROB-17 (default no), M18 TST-02 (`unset ZDOTDIR`), with tests of the `--keep-old` round trips and failed steps | M | Only critical; user data at stake today |
| **2. Trustworthy tests** | M19: `check_eq`/`check_status`/`check_count`, convert the 46 numeric checks, kill the listed survivors, skip counter, `safe.directory` in the 4.2 job (TST-01), TST-06; doc in testing.md | M | Every later fix needs tests that can fail |
| **3. AI guide safety** | M6 delimiter, M7 `&&` chain + stop on ✗, M20 safe "Try it", M21 Setup rows (distribution, package managers, absolute config dir) + WSL notes, DOC-04 `mkdir -p`, M10 doc part (`$0`), GDE-03/05, DOC-12; amend decision 0010; re-run the evaluation set (7 requests + "existing command", "renamed plugin") | S-M | Pasted answers execute on users' machines |
| **4. flags.sh isolation & cmd.sh launch** | M8 PAR-01, M9 PAR-02, PAR-11, M10 PAR-03 (`bash -c`), CMP-02 (`</dev/null`), hostile-fixture test | S | Contract robustness; small, local changes |
| **5. One router** | ARC-02 `cb::route` used by main, completion, doctor and `self new`; then M5 (rename-aware `self new`), RTE-05/ARC-12, M12 RTE-04 warning, RTE-14 "Did you mean", RTE-03 loop guard, RTE-02 | M | Prerequisite of aliases / hidden / inherited flags |
| **6. DSL & ui hardening** | M11 int, PAR-05/06/07/08/09/10/14/16, PAR-12 prompts on the tty, PAR-13, PAR-15; contract change list | S-M | Contract changes grouped and announced once |
| **7. System commands robustness** | M4 `self update` (exit codes, re-exec, `--check` code), ROB-08/09/10/11/12/13/15/16, ARC-05/SEC-05 config mode + one rewriter, ROB-07/POR-07, POR-04, SEC-11/POR-08 (`unset CDPATH`), POR-03 (`set +o posix`), RTE-06/07 | M | Rule 4/5 compliance on failure paths |
| **8. Portability** | M15 locale, M16 `.gitattributes`, POR-02 CRLF detection (doctor + config strip CR), M17 macOS login shells, tr_TR CI step | S | Cheap, prevents classes of bugs |
| **9. Completion & performance** | M14 quoting, SEC-08/CMP-03/POR-09 root-name escaping, CMP-04 batch `about` (−78 % processes), CMP-06 zsh `compinit`, CMP-05 forks; zsh job in CI if possible | S-M | Daily UX |
| **10. Docs & versioning** | M13 trust model, DOC-07 decision amendments, DOC-08 AGENTS sync step, DOC-10, DOC-11 README → tour + links, DOC-13 stability/debugging, ARC-11 version (`CB_VERSION`, `--version`, CHANGELOG of contract changes, `requires-version`?), roadmap reordered | S-M | Before any DSL extension of the roadmap |

Then the roadmap features, in this order: `--choices-from` timeout → repeatable flags →
opt-in inherited flags → aliases + hidden commands (on the single router) → zsh test →
`self plugins install` (last, with the trust model).

### Architecture decisions to take together (new decision records)

1. **flags.sh isolation**: harden in-process loading (save/restore options/cwd, prefixed
   locals) — recommended — vs loading every spec in a subshell (cleaner, ~1 fork more per call).
2. **Single router** `cb::route` (shared by run, completion, doctor, `self new`), and the rule
   for options placed before a subcommand (warning vs error).
3. **How `cmd.sh` is started** (`bash -c … source "$0"`, `$0` = cmd.sh) — amends 0005's practice.
4. **`int` semantics** (canonical decimal, 64-bit) and the **contract change list**.
5. **Versioning** of cmd-builder and of the plugin contract (version file, `--version`,
   CHANGELOG; optional `requires-version` in flags.sh).
6. **Prompt output device** (print on the tty that is read, stderr when `_CB_TTY` is set) —
   amends 0009; and whether internal `_CB_*` variables may come from the environment.
7. **Trust model of plugins** (documented now; prerequisite of `self plugins install`).
8. **Guide paste protocol** (delimiter, `&&` chain, safe "Try it") — amends 0010.
9. **Single source of the reference** (README = tour + links) and **test harness structure**.

## 7. Owner's answers (2026-11-09)

1. Order of the batches: **accepted** as in section 6.
2. flags.sh isolation: harden in-process loading if it does not risk many problems,
   otherwise the clean option. Chosen: **in-process hardening** (save/restore shell options,
   shopt, cwd, stdout; prefixed locals; hostile-fixture tests). The subshell option would need
   to send the spec arrays back to the parent (`declare -p` + `eval` inside a function), the
   very mechanism that breaks on Bash 4.2 (decision 0011): riskier, not cleaner.
3. An option before a subcommand: **error** (with the right form in the message).
4. Versioning (`--version`, `CB_VERSION`, CHANGELOG of contract changes) before any DSL
   extension: **yes**.
5. `int`: canonical decimal, 64-bit range: **yes** (contract change).
6. `cmd.sh` started so that `$0` is the command: **yes**.
7. Guide Setup gains distribution, package managers and the absolute config dir: **yes**, but
   the guide must not *encourage* extra dependencies; when one is really needed, it must be
   declared properly with `requires` in the DSL.
8. README becomes a tour + links, `docs/plugin-authoring.md` the single reference: **yes**.
