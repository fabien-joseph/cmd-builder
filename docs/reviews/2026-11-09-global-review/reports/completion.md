# completion — completion engine, bash/zsh adapters, performance of the hot path

## Scope and method
(report rewritten after a reboot wiped /tmp: evidence of CMP-01..03 and the quiet-machine timings were captured before it; the big tree was regenerated identically for the prototypes and the addendum)
Files read: lib/complete.sh, templates/completion.{bash,zsh}, lib/spec.sh, lib/util.sh, lib/plugins.sh, lib/config.sh,
lib/router.sh, lib/help.sh, lib/parse.sh, lib/core.sh, main.sh, builtin/self/*, docs/architecture.md, docs/roadmap.md,
decision 0006. Sandboxes from `mksandbox.sh`, fixture plugins (plugins/demo/*, plugins/+system/disk).
Harnesses: (1) COMPREPLY harness (tests/run.sh `bashcomp` idea); (2) a REAL interactive bash 5.2.37 in a pty
(`script -qec 'bash --rcfile rc -i'`, keys piped, then Enter so the command prints its argv as `[arg]`): shows what
readline really inserted. (3) exact process counts in a private PID namespace (`unshare -Urpf --mount-proc`, delta of
/proc/sys/kernel/ns_last_pid); (4) wall time via `$EPOCHREALTIME`, mean/min over N runs. Machine: WSL2, 8 CPUs, other
reviewers running concurrently (timings are noisy, ±20 %; process counts are exact).
Incident to disclose: one pty test typed `sudo tt demo mul<TAB>` then Enter; sudo prompted, read the next piped lines
as passwords and failed ("1 incorrect password attempt"); nothing ran. Later prefix tests never pressed Enter.
NOT covered: zsh (not installed: static review only), Bash 4.2 (not installed), macOS.

## Findings (appended as verified; final ordering at the end)

### CMP-01 Dynamic candidates are inserted on the line without shell quoting (spaces, `$`, quotes, `;`, `*`)
- Severity: major   - Status: VERIFIED (bash 5.2.37, real line in a pty)
- Aspect: bash adapter   - Location: templates/completion.bash:16-19, templates/completion.bash:21
- Evidence: fixture `arg file "A text file" --choices-from "ls *.txt"` (README "Dynamic choices" lists "files" as a use
  case) in a directory with `my notes.txt`; `_weird` printing `sp ace`, `dollar$HOME`, `quo'te`, `semi;colon`, `star*`.
  COMPREPLY: `tt demo files ` -> `[my notes.txt][plain.txt]`; `tt demo weird ` -> `[a:b][x=y][star*][dollar$HOME][quo'te][sp ace][~tilde][semi;colon]`.
  Real interactive bash, keys `tt demo files my<TAB><Enter>` etc.:
  ```
  $ tt demo files my notes.txt
  ✗ unexpected argument 'notes.txt'
  $ tt demo weird sp ace
  ✗ unexpected argument 'ace'
  $ tt demo weird dollar$HOME
  [dollar/tmp/.../sbx-completion.1NX30X/home]          <- the inserted value was expanded
  $ tt demo weird quo'te
  >                                                    <- unbalanced quote: the shell swallowed the next lines
  bash: unexpected EOF while looking for matching `''
  ```
- Impact: any `--choices-from` value with a space or shell metacharacter (file names, titles...): Tab builds a command
  line that does something else than what was offered. Static choices and names cannot contain such characters, so the
  blast radius is dynamic choices.
- Fix: quote in the adapter, `printf -v q '%q' "${line#"$prefix"}"; COMPREPLY+=("$q")` (pure Bash 4.2, no fork). Better
  (S-M): build words from `COMP_WORDS`, re-joining the `:`/`=` pieces (bash-completion's `__reassemble_comp_words_by_ref`
  approach) so quoted/backslashed words work too — removes the Known limitation docs/roadmap.md:85. Test with
  `my notes.txt`. Cost: S
- Decision: none.

### CMP-02 `--choices-from` snippets inherit the terminal (Tab) and the command's stdin (`--strict` at run time)
- Severity: minor   - Status: VERIFIED (pty for Tab, pipe for run time)
- Aspect: engine / spec   - Location: lib/spec.sh:43, lib/spec.sh:61, templates/completion.bash:14
- Evidence: `arg x "X" --choices-from "read -r l; echo got:\$l"`; pty keys `tt demo stdin <TAB>XYZ<Ctrl-J>`:
  ```
  $ tt demo stdin got:XYZ          <- keys typed after Tab were read by the snippet, not by readline
  ```
  With only `XYZ<CR>` sent and nothing more, the session stayed blocked until `timeout` (rc=124).
  Run time: `arg x "X" --choices-from "read -r l; echo a" --strict`, cmd.sh `echo "stdin of cmd.sh: $(cat)"`:
  ```
  $ printf 'line1\nline2\n' | tt demo strict a
  stdin of cmd.sh: line2            <- line1 eaten by the validation snippet
  ```
- Impact: a snippet that reads stdin (ssh without -n, a filter without file, `read`) freezes Tab and eats keystrokes;
  with `--strict` it silently consumes input piped to the command.
- Fix: `(eval "$from") </dev/null 2>/dev/null` in cb::choices_of. Cost: XS

### CMP-03 Root names `my-cmd` and `my_cmd` share one completion function
- Severity: minor   - Status: VERIFIED
- Aspect: script generation   - Location: lib/complete.sh:161, lib/install.sh:126 (both names valid)
- Evidence:
  ```
  my-cmd self completion bash -> _cb_complete_my_cmd ; my_cmd self completion bash -> _cb_complete_my_cmd
  $ bash -c 'source comp.my-cmd; source comp.my_cmd; complete -p my-cmd; declare -f _cb_complete_my_cmd | grep -o "my[-_]cmd __complete"'
  complete -o default -F _cb_complete_my_cmd my-cmd
  my_cmd __complete            <- Tab on my-cmd asks my_cmd (other config / renames / disables)
  ```
- Impact: two installs differing only by `-`/`_` (architecture.md:180 says installs coexist). Rare.
- Fix: injective encoding (`-` -> `_2d`, `_` -> `__`), or one shared function calling `"$1" __complete` (bash passes the
  command name as $1; zsh `$words[1]`). Cost: XS

### CMP-04 Root-level Tab and root `--help` cost 2 processes per plugin: ~300 ms with 100 plugins
- Severity: minor (performance; fine below ~25 plugins)   - Status: VERIFIED (numbers below)
- Aspect: performance   - Location: lib/spec.sh:106-111 (`cb::about_of` = `( ... )` inside every caller's `$( )`),
  lib/complete.sh:64-67, lib/complete.sh:137-139 (3 forks per child: `$(cb::about_of "$(cb::child_dir ...)")`),
  lib/help.sh:79, lib/help.sh:103-106, builtin/self/plugins/{enable,disable}/flags.sh:5
- Evidence: see "Performance numbers". Exact process counts: root Tab 13 (minimal) -> 213 (100 plugins) = 2/plugin;
  `tt __complete -- p42 ''` (5 children) 28 = 13 + 3/child; `self plugins disable <Tab>` 219.
  Wall time: root Tab 20 ms -> 304 ms, `tt --help` 22 ms -> 320 ms, `self plugins disable <Tab>` 28 -> 282 ms.
- Impact: Tab on the first word lags visibly (> 100 ms) beyond ~25-30 plugins; each fork costs ~1.4 ms on WSL2.
- Fix: (a) drop the inner `( )` of cb::about_of (all callers already run it in `$( )`) -> 1 fork/plugin; (b) better, a
  batch helper `cb::abouts_of dir...` printing one about per line from ONE subshell (spec_load in a loop) for
  help_root / root Tab / children lists / cb::help. Cost: S

### CMP-05 Fixed cost of every call: 13 processes, ~20 ms, mostly avoidable forks
- Severity: suggestion   - Status: VERIFIED (counts)
- Aspect: performance   - Location: main.sh:16-21 (5 processes: `$(cd -P "$(dirname ...)" && pwd)` twice + readlink),
  lib/plugins.sh:57 (printf | sort in a process substitution, ~3), lib/router.sh:30/34/38 and lib/complete.sh:71/76/82/129/143
  (`$(cb::plugin_dir)`, `$(cb::child_dir)`, `$(cb::plugin_root_of)`, `$(cb::executable)` = 1 fork each)
- Evidence: `bash -c true` = 1 process / 2 ms; `tt __complete -- system info --` = 13 processes / 22 ms; `tt p1 s1 foo` = 13.
- Fix: `${p%/*}` instead of dirname, a single `cd -P` subshell; pure-Bash sort (or glob order) of plugin names; helpers
  returning in a variable (REPLY) instead of `$( )`. Expected ~13 -> ~4 processes, ~20 -> ~10 ms. Cost: S
- Prototype (sandbox copies sharing the same 100-plugin tree, interleaved runs; machine under load avg ~7.9 at that
  time, so absolute values are ~2.3x the quiet ones):

  | variant | root Tab processes | root Tab mean / min | vs current |
  |---|---|---|---|
  | current | 213 | 706-784 / 622 ms | — |
  | A: `cb::about_of() { cb::spec_load "$1" >/dev/null 2>&1; printf '%s' "$_CB_ABOUT"; }` (no inner `( )`) | 111 | 442-481 / 411 ms | −40 % |
  | B: A + one `cb::abouts_of dir...` subshell for the whole root list | 13 | 158-163 / 138 ms | −78 % |

  Output identical (102 candidates, same descriptions; `tt --help` identical with A). Quiet-machine estimate:
  304 ms -> ~180 ms (A) -> ~65 ms (B). Caveat for B: flags.sh are sourced one after the other in the same subshell,
  so a function defined by one is visible to the next (harmless for `about`, but re-assert the DSL functions or keep A
  for cb::help children if that matters).

## Performance numbers (quiet machine unless noted; mean of 20 runs; exact process counts)

| call | minimal tree (core/system) | 100 plugins x 5 x 5 (3100 commands) |
|---|---|---|
| `bash -c true` (baseline) | 2.2 ms / 1 proc | 1.9 ms |
| `tt --help` | 21.9 ms / 13 procs | 319.5 ms / 213 procs |
| `tt <plugin> --help` | 25.8 ms | 62.6 ms / 29 procs |
| `tt __complete -- ''` (root Tab) | 20.4 ms / 13 | 303.5 ms / 213 |
| `tt __complete -- <plugin> ''` | 23.7 ms / 16 | 63.8 ms / 28 |
| `tt __complete -- <plugin> <sub> --` | 22.1 ms / 13 | 36.6 ms / 13 |
| `tt __complete -- p42 s3 -t ''` (`--choices-from` printf) | — | 38.6 ms / 14 |
| `tt __complete -- p42 s3 c2 x -f ''` | — | 36.7 ms |
| trivial run (`tt system info` / `tt p1 s1 foo`) | 30.9 ms / 20 (cmd.sh runs uname, sed...) | 37.1 ms / 13 |
| trivial run depth 3 (`tt p1 s1 c1 foo`) | — | 39.1 ms / 14 |
| `self plugins disable <Tab>` | 28.4 ms | 282.3 ms / 219 |
| `tt self doctor` | 1224 ms (5 runs) | see below |
| `tt self guide` | 223 ms | see below |
| `tt self deps` | 77 ms | see below |

Budget proposal: Tab < 100 ms (felt instant), plain run overhead < 50 ms. Where the tool stands: minimal tree and
any Tab below the first word are well within budget (20-40 ms); the first-word Tab and root `--help` grow by ~2.8 ms per
plugin and leave the budget at ~25-30 plugins; children lists cost ~4 ms per child (3 forks). A `--choices-from`
snippet adds its own run time to every Tab (no timeout, decision 0006): `sleep 2` = 2 s freeze.

### CMP-06 zsh adapter: `compinit` run from the completion file, raw `words`, no test
- Severity: minor   - Status: NOT VERIFIED (zsh not installed; static review)
- Aspect: zsh adapter   - Location: templates/completion.zsh:5, templates/completion.zsh:23-25
- Analysis:
  1. `if (( ! $+functions[compdef] )); then autoload -Uz compinit && compinit; fi` — for a user without a completion
     system this runs a full `compinit` at every shell start (tens of ms, and the interactive "insecure directories ...
     [y/n]?" prompt when fpath has group/world-writable dirs). If the user's own `compinit` runs later (plugin manager,
     file sourced after the block), the second compinit reloads `_comps` from the dump written before our `compdef`,
     so the `tt` mapping is lost. zinit "turbo" users rely on compdef replay: unverified interplay.
  2. `${(@)words[2,CURRENT]}`: zsh's `words` keep the quoting as typed (`'my no`) and `words[CURRENT]` is the whole word,
     including the part after the cursor ($PREFIX is what is before it). Quoted prefixes never match; mid-word Tab
     filters with the wrong prefix.
  3. Good: `:` escaped in values (`\:`) for `_describe`, full `--flag=value` words are right for zsh, `_files` fallback;
     `_describe`/`compadd` (no -Q) should quote spaces, so CMP-01 probably does not apply to zsh.
- Fix: in the rc block (not the completion file), only `compdef` when available and otherwise register lazily
  (`compdef` via `precmd` hook once, or document "requires compinit"); use `$PREFIX` (unquoted with `${(Q)PREFIX}`) for the
  current word. Add the zsh test already on the roadmap (docs/roadmap.md:64), e.g. via `zsh -f` + `zpty` in CI. Cost: S

### CMP-07 A subcommand name that is also a positional choice is offered twice
- Severity: suggestion   - Status: VERIFIED (COMPREPLY), invisible in bash (readline drops duplicates)
- Location: lib/complete.sh:136-153
- Evidence: `demo env` with `arg target --choices "prod staging list"` and a child `list`: `tt demo env l` -> `[list][list]`.
  Routing always takes the child (docs/architecture.md:40-43), so the positional `list` can never be reached by Tab;
  zsh `_describe` may list it twice with two descriptions.
- Fix: skip positional choices equal to a child name when `start == n`. Cost: XS

### Checked and OK (no finding)
`core:sy` -> `system` and `--opt=a:` -> `b` (prefix stripping for `:`/`=`); `--fmt=`/`-vf `/`-f ` value completion;
after `--` (no option candidates); negative numbers; variadic (`multi alpha beta ` -> all choices); extension
(`tt system ` -> `disk info`); renamed (`sys`), disabled (no output -> file fallback), shadowed (user tree) plugins;
mid-line Tab (COMP_POINT=22 -> `[json]`); command prefixes on the real line: `FOO=1 tt demo mul<TAB>`,
`(tt demo mul<TAB>`, `true && tt demo mul<TAB>` all completed to `multi` (bash strips them from COMP_LINE); `sudo tt
...` completes via bash-completion's `_command_offset`; `env tt` only with bash-completion (bash default: none — not
cmd-builder's issue). Snippet `pwd; cd /; exit 3` -> prints the user's cwd, `exit` only leaves the subshell; stderr
discarded. Bash 4.2 note (NOT VERIFIED): COMP_POINT counts bytes in 4.2 (characters since 4.3), so
`${COMP_LINE:0:COMP_POINT}` over-reads after multibyte characters on 4.2 only.

## Grade
- Completion engine (lib/complete.sh): **A-**. Reuses the real routing/spec, so it cannot disagree with execution;
  every edge case tried (`--`, `-vf`, `--x=`, negative numbers, variadic, extensions, rename/disable/shadow, mid-line)
  behaves right. Only duplicates (CMP-07) and the snippet stdin (CMP-02).
- bash adapter: **C**. Clever `:`/`=` handling and glob-safe `mapfile`, prefixes work, but candidates are inserted
  unquoted (CMP-01, major) and the function name is not injective (CMP-03).
- zsh adapter: **C (unverified)**. Plausible design, but `compinit` from the completion file and raw `words` are
  risky, and it has never been run by a test (CMP-06).
- Performance: **B**. 20-40 ms per call on normal trees, linear 2-3 ms per listed plugin/child because `about` is read
  in 2 forks; a batch reader cuts root Tab by ~78 % (CMP-04). Whole-tree `self` commands are slow on huge trees.

## What is good and must be kept
- One engine, shared by both shells, driven by the real router and `cb::spec_load`.
- `mapfile` instead of `$( )` word-splitting (immune to nullglob/failglob), `:`/`=` prefix stripping driven by
  `COMP_WORDBREAKS`, `-o default` fallback to files.
- Process-isolated `--choices-from` (subshell, stderr dropped) and `exec` of the command: no global leaks.

## Risks for the future
- Every new per-item `$(...)` helper multiplies by the tree size: keep helpers returning in variables on hot paths
  and add a perf guard test (e.g. process count of root Tab with 50 fixture plugins must stay < N).
- Inherited flags / aliases / hidden commands (roadmap) will touch `cb::complete` and `cb::children`: keep the engine
  routed through the same helpers as `cb::main`.
- No zsh test: any change to the protocol can silently break zsh users.

## Open questions for the owner
1. Fix CMP-01 by `%q`-quoting candidates (XS) or by switching to `COMP_WORDS` re-assembly (S, also fixes quoted
   words)? Recommendation: `COMP_WORDS` re-assembly, with a pty-free COMPREPLY test for `my notes.txt`.
2. Add the `--choices-from` timeout from the roadmap? Recommendation: yes but cheap — `</dev/null` now (CMP-02), and a
   pure-Bash timeout only if users report slow snippets (portable `timeout` is not on macOS by default).
3. Target size: how many plugins should stay "instant"? Recommendation: budget Tab < 100 ms for 100 plugins, which
   requires the batch about reader (CMP-04 B) plus the fixed-cost trims (CMP-05).
4. zsh: keep `compinit` in the generated file? Recommendation: no — move registration to the rc block and document
   that zsh completion needs `compinit`; add zsh to CI.

## Addendum: whole-tree `self` commands and the WSL Windows PATH (100 x 5 x 5 = 3100 commands, 1 run each, loaded machine)

| call | time |
|---|---|
| `tt self guide` | 26.0 s (minimal tree: 223 ms) |
| `tt self deps` | 33.9 s (minimal: 77 ms); 12.9 s in a later run with the Windows PATH — load noise dominates, compare only the order of magnitude |
| `tt self doctor` | 260 s (minimal: 1.2 s) |
| `command -v <missing tool>` | 1.7 ms with the Linux PATH, 50.6 ms (min 39.7) with the 19 `/mnt/c/...` entries of the owner's PATH |

### CMP-08 Whole-tree `self` commands are fork-bound: doctor ~84 ms, guide ~8 ms, deps ~11 ms per command
- Severity: suggestion   - Status: VERIFIED (numbers above)
- Location: builtin/self/doctor/cmd.sh:106-127 (per command: `$( (cb::spec_load) )`, a process substitution, one
  `check_example` per example with `xargs` + subshell, `$(cb::executable)`, `$(cb::children)`), lib/util.sh:65-71
  (`cb::walk`: `$(cb::child_dir)` + `< <(cb::children)` per node), lib/deps.sh:92-102 (one subshell per command),
  builtin/self/guide/cmd.sh:51-57 (`$(cb::executable)` + `$(cb::about_of)` per command).
- Impact: irrelevant for typical trees (minimal tree: 1.2 s doctor), minutes for very large ones. Not on the hot path.
- Fix: same helpers-in-variables refactor as CMP-05; doctor: load each flags.sh once per command. Cost: M
- WSL note: each `command -v` of a MISSING tool costs ~40-50 ms with the Windows PATH (9P lookups in 19 /mnt/c
  dirs, no negative cache). Only `requires` checks do it (lib/router.sh:61 for required tools at run time — the
  command then fails anyway —, `self deps`/`doctor` once per declared tool), so the impact stays small: ~1 s for 20
  missing tools in doctor. Present tools resolve from /usr/bin first (no cost). No action needed; worth one line in
  docs/conventions.md ("never `command -v` in a loop on the hot path").

## Final counts
major 1 (CMP-01); minor 4 (CMP-02, CMP-03, CMP-04, CMP-06 not verified); suggestion 3 (CMP-05, CMP-07, CMP-08).
