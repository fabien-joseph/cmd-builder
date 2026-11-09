# routing — routing, plugin discovery, extensions, config, self new / plugins / doctor / guide

## Scope and method
Read: lib/router.sh, lib/plugins.sh, lib/util.sh, lib/config.sh, lib/parse.sh:12-18 and
:133-158 (error paths only), builtin/self/{new,plugins,doctor,guide}/, core/system/, main.sh,
docs/architecture.md, README.md, docs/plugin-authoring.md (layout), docs/roadmap.md,
docs/handoff.md, decisions 0001, 0002, 0003, 0010, 0013.

Experiments (all in a sandbox `mksandbox.sh routing tt --init`, root name `tt`,
`package-manager apt` in the config; `$P` = `$SB/app/plugins`, `$CFG` =
`$SB/home/.config/tt/config`): `self new` with renamed / disabled / shadowed plugins; symlink
loops (single and fan-out) under `timeout`; symlinked plugin and extension; odd directory
names (space, unicode, uppercase, leading digit, trailing `-`, `+` inside, `++x`); rename
edge cases; config with CRLF, tabs, inline comments, duplicates, as a directory, unreadable,
read-only (under `script -qec` for a pseudo-terminal), mode 600; option/subcommand ordering;
suggestions; root edge cases; doctor gaps (orphan/disabled extension, CRLF files, `cmd`
without shebang, router with args, pipe/redirect examples, broken install); guide `-o -`,
`-o` missing dir, placeholders in an `about`, request with special characters; `self plugins`
alignment and resolution.

Prototypes (sandbox copy only): RTE-03 (ancestor check in `cb::walk`), RTE-06 (CR strip),
RTE-14 ("Did you mean" in lib/parse.sh). With the three patches, the sandbox suite gave
`441 passed, 0 failed` (the sandbox copy has no `.git`, which likely explains 441 vs 442;
baseline not re-run there), and every reproduction below was fixed.

NOT covered: parser internals, completion, install/rename/deps/update (other reviewers);
macOS / BSD tools and zsh (not installed: `xargs`, `mv` prompt, `stat` behaviour on macOS NOT
VERIFIED); performance of routing (one subshell per word) not measured.
The sandbox was lost in a machine reboot after the experiments; nothing was re-run after.

## Grade
- **Routing (A-)**: simple, predictable, extension-aware, safe against path traversal
  (`cb::is_child` validates the word). Weak spot: options placed before a subcommand
  silently route to the parent (RTE-04), contradicted by the README.
- **Discovery / extensions (B)**: deterministic, conflicts reported, symlinked plugins and
  extensions work. Weak spots: unbounded walk on symlink loops (RTE-03), locale-dependent and
  silently ignored names (RTE-08, RTE-09).
- **Config (C+)**: the parser tolerates tabs, inline comments and missing final newlines,
  and errors are collected rather than fatal. But CRLF breaks every line (RTE-06), and the
  writers lie or prompt in degraded cases and drop the file mode (RTE-07).
- **self new (C)**: works on directory names, so renames make it shadow plugins or print
  wrong commands (RTE-01, RTE-02).
- **self doctor (B)**: good coverage, a correct exit-code split (errors -> 1, warnings -> 0)
  and a clear report on a broken install. Gaps: inactive extensions, invalid names, CRLF
  files; false positives on pipes (RTE-09/10/11/15).
- **self guide / self plugins (B+)**: robust (placeholders inside an `about` are not
  substituted, the request is quoted). There are only cosmetic issues (RTE-16, RTE-17).

## Findings

### RTE-01 `self new` resolves words by directory name, ignoring `rename`: it shadows the renamed plugin or prints a command that does not exist
- Severity: major   - Status: VERIFIED
- Aspect: self new / renames      - Location: builtin/self/new/cmd.sh:16-36, :107-110
- Evidence:
```
$ echo 'rename core:system sys' >> $CFG
$ tt self new sys disk            # the user knows the plugin as "sys"
✓ Command 'tt sys disk' created
  + plugins/sys/
  + plugins/sys/flags.sh ...
$ tt sys info -s
✗ unknown subcommand 'info'                  # the official plugin is now shadowed
$ tt self plugins
  sys                core:system           shadowed by user:sys (renamed)
  sys                user:sys              active

# same with a renamed user plugin (rename user:backup bk):
$ tt self new bk prune            -> creates plugins/bk/, user:bk shadows user:backup
$ tt bk list                      -> ✗ unknown subcommand 'list'   (rc=2)
$ tt self new backup restore      -> ✓ Command 'tt backup restore' created
$ tt backup restore --help        -> ✗ unknown command 'backup'   (it is 'tt bk restore')
# and for a renamed official plugin, by directory name:
$ tt self new system disk         -> ✓ Command 'tt system disk' created (added to the official plugin 'system'...)
$ tt system disk                  -> ✗ unknown command 'system'  Did you mean: sys?   (works as 'tt sys disk')
```
- Impact: anyone who renamed a plugin (the documented way to solve a conflict, decision 0003)
  and then adds a command to it by the name they use every day. The scaffold silently hides
  every existing command of the renamed plugin (only `self doctor` / `self plugins` / the
  root help say "1 conflict"); the AI guide teaches `self new <plugin> <sub>` with the names
  the user sees, so an AI reproduces it. With the directory name, the success message and the
  "Try:" line name a command that does not exist.
- Fix: resolve `$1` like the router first: if `${_CB_PLUGIN_ID[$1]}` exists, map it to its
  id, then to its directory (`core:x` -> extension `+x`, `user:x` -> `plugins/x`); if `$1` is
  only a directory name whose plugin is exposed under another name, either accept it and say
  so, or refuse with "plugin 'backup' is exposed as 'bk': tt self new bk ...". Refuse to create
  a new plugin whose name is the exposed name of another one (it would shadow it) unless
  `--force`. Print the success/"Try" lines with the exposed words. Tests: renamed core,
  renamed user, by exposed name and by dir name. — Cost: S
- Decision: 0003 (renames) and 0013 (`self new` creates the extension) are fine; `self new`
  just does not apply them.

### RTE-02 `self new <official> <sub>` on a disabled (or shadowed) official plugin creates an inactive extension and reports success
- Severity: minor   - Status: VERIFIED
- Aspect: self new / extensions   - Location: builtin/self/new/cmd.sh:16, :107-110
- Evidence:
```
$ echo 'disable core:system' >> $CFG
$ tt self new system disk
✓ Command 'tt system disk' created (added to the official plugin 'system', in plugins/+system/)
› Try: tt system disk --help
$ tt system disk
✗ unknown command 'system'
  Plugin core:system is disabled: 'tt self plugins enable core:system'
```
- Impact: the user is told the command exists; it does not until they re-enable the official
  plugin (decision 0013 makes the extension inactive, by design). Confusing, not harmful.
- Fix: after the scaffold, if `_CB_ID_STATE[core:$1]` is not `active`, replace the "Try" line
  by a warning: "core:system is disabled: the extension is inactive until
  'tt self plugins enable core:system'" (or refuse unless `--force`). — Cost: XS
- Decision: 0013 (inactive extensions) stays; only the message is wrong.

### RTE-03 A symlink loop inside a plugin makes `self doctor`, `self guide`, `self deps` and `self update` hang (exponential tree walk)
- Severity: minor   - Status: VERIFIED
- Aspect: discovery / tree walk   - Location: lib/util.sh:65-71 (`cb::walk`), lib/util.sh:34-49
- Evidence:
```
# one loop: bounded by the kernel (40 symlinks per path), 40 bogus commands
$ tt self new a; ln -s . $P/a/loop
$ tt self guide | grep -c '`tt a loop'          -> 40 lines, the last one is "tt a loop loop ... (x40)"
$ tt self doctor                                -> "✓ 59 valid command(s)"  (18 real)
# two loops: 2^40 nodes
$ ln -s . $P/a/x; ln -s . $P/a/y
$ timeout 20 tt self doctor     -> rc=124 20003ms (killed)
$ timeout 20 tt self guide      -> rc=124
$ timeout 20 tt self deps       -> rc=124
# same inside an extension (plugins/+system/disk/{x,y} -> .):
$ timeout 20 tt self doctor     -> rc=124 ;  timeout 20 tt self update --check -> rc=124
$ tt a x y x --help             -> works (routing itself is fine)
```
- Impact: rare (needs a link to an ancestor, e.g. a user trying a symlink as a command alias,
  `ln -s . plugins/tool/t`), but then the diagnostic tool and the update tool both hang
  silently: the user cannot find out why.
- Fix: in `cb::walk`, skip a child that is the same directory as one of its ancestors, with
  the builtin `[[ $child -ef $ancestor ]]` (device+inode, no subshell), passing the ancestor
  chain down; `self doctor` warns "plugins/a/x links to an ancestor: ignored". Alternative:
  a depth limit (e.g. 32) in `cb::walk`. Test with a two-link fixture under `timeout`. — Cost: S
- Decision: none.

### RTE-04 Options before a subcommand silently run the parent command; README says "options may be placed anywhere"
- Severity: major   - Status: VERIFIED
- Aspect: routing rule (decision 0001) + docs   - Location: lib/router.sh:33-37, README.md:182, lib/parse.sh:149-155
- Evidence (fixture: `backup` has `cmd.sh`, `flag verbose -v`, `arg target --optional`, and a
  child `restore` with `flag verbose -v`):
```
$ tt backup restore -v    -> restore: verbose=1
$ tt backup -v restore    -> backup: target=restore verbose=1      # the PARENT runs, silently
$ tt backup -- restore    -> backup: target=restore verbose=0      # documented nowhere
$ tt backup restor        -> backup: target=restor verbose=0       # typo of a subcommand = argument
$ grep -n anywhere README.md docs/plugin-authoring.md
README.md:182: ... `--` (end of options); options may be placed anywhere.
docs/plugin-authoring.md:230: ... Options may appear anywhere among positionals.
```
  When the parent accepts no positional, the parser already explains it well
  (lib/parse.sh:152: "'restore' is a subcommand: put the options after it."). The bad case
  is a parent with its own `cmd.sh` **and** an `arg`.
- Impact: a user (or an AI reading the README) who writes `mu deploy -v status` runs
  `mu deploy` with the argument `status`, which may be a destructive action on a target
  named "status". Scripts that worked can change meaning when a subcommand is added later
  with the name of a value they pass.
- Fix: (1) docs (README:182, plugin-authoring "Parsing rules", ai-guide): "options go
  **after** the subcommand words; routing stops at the first option; use `--` to pass a
  subcommand name as an argument". (2) In `cb::parse`, when routing stopped on an option and a
  positional (not after `--`) is a child name, print a warning on stderr (`! 'restore' is also
  a subcommand of 'tt backup': 'tt backup restore -v' runs it; 'tt backup -- restore' passes
  it as an argument`) — or an error (exit 2) if the owner prefers strictness (behaviour
  change for invocations that are almost certainly mistakes). (3) `self doctor`: warn when a
  static `--choices` value of an `arg` is also a child name (unreachable without `--`). — Cost: S
- Decision: 0001 ("a child name wins") should stay (it is what makes `mu system info` work
  next to an `arg`), but its consequences (`--` escape, options after subcommands) must be
  documented and the silent case flagged.

### RTE-05 After a `rename`, every `--help` example of the plugin shows a command that does not exist (and `self doctor` accepts it)
- Severity: minor   - Status: VERIFIED
- Aspect: renames / help / doctor   - Location: lib/help.sh:85 (examples section), builtin/self/doctor/cmd.sh:21-23
- Evidence:
```
$ echo 'rename core:system sys' >> $CFG
$ tt sys info --help | sed -n '/Example/,$p'
Examples
  tt system info              <- 'tt system' is now "unknown command"
  tt system info -s
$ tt self doctor | tail -1
✓ Everything is fine.          (check_example accepts the directory name on purpose)
```
- Impact: rename is the documented answer to conflicts (0003) and is set per machine, so the
  author of a shared plugin cannot write the exposed name. After a rename, `--help` shows
  commands that fail. The examples of an extension of a renamed official plugin have the same
  problem.
- Fix: when showing an example, replace its first word by the exposed name when it equals the
  plugin's directory name (the exposed name is the second word of `$display`). Keep the
  doctor's tolerance. — Cost: XS
- Decision: 0003 unchanged.

### RTE-06 A CRLF config is ignored entirely, with misleading and garbled doctor messages
- Severity: minor   - Status: VERIFIED
- Aspect: config parsing   - Location: lib/config.sh:21-24
- Evidence:
```
$ printf '# my config\r\n\r\ndisable core:system\r\npackage-manager apt\r\n' > $CFG
$ tt system info -s >/dev/null && echo active      -> active   (the disable is ignored)
$ tt self deps managers                            -> › none configured yet
$ tt self doctor | cat -A
  ✗ config line 2: unknown directive '^M'          (on a terminal the CR garbles the line)
  ✗ config line 3: expected 'disable <core|user>:<plugin>'
  ✗ config line 4: expected 'package-manager <apt|dnf|pacman|zypper|apk|brew>'
```
- Impact: WSL users (the owner's setup) whose config lives in a Windows-side dotfiles repo
  (`core.autocrlf=true`; a symlinked config is explicitly supported) or is written by a Windows
  tool. Every directive is ignored, the messages report a syntax error on correct lines, and
  blank lines become errors.
- Fix: `line=${line%$'\r'}` after each `read`, in `cb::config_load` and in both writers. Prototyped
  in the sandbox: the CRLF config then works and the doctor reports 0 config errors; the suite
  stays green. — Cost: XS
- Decision: none.

### RTE-07 Config path that is a directory, unreadable or read-only: raw Bash errors, a false success, a `mv` prompt, mode not kept
- Severity: minor   - Status: VERIFIED
- Aspect: config writers   - Location: lib/config.sh:20, :52, :59-60, :82-91, :107; compare lib/install.sh (`cb::rc_replace`: `chmod --reference` + `stat -f %Lp` fallback)
- Evidence:
```
$ mkdir $CFG; tt self plugins disable core:system; echo rc=$?
.../lib/config.sh: line 60: .../config: Is a directory
.../lib/config.sh: line 82: read: read error: 0: Is a directory
✓ core:system disabled (re-enable: tt self plugins enable core:system)
rc=0                     -> nothing disabled; config/config.tmp created INSIDE the directory
$ chmod 000 $CFG; tt system info -s
.../lib/config.sh: line 17: .../config: Permission denied     (on every command)
$ chmod 444 $CFG; script -qec "tt self plugins disable core:system; echo tt-rc=\$?" /dev/null </dev/null
mv: replace '.../config', overriding mode 0444 (r--r--r--)? ✓ core:system disabled (...)
tt-rc=0                  -> EOF = "no": config unchanged, config.tmp left behind
$ chmod 600 $CFG; tt self plugins disable core:system; stat -c %a $CFG    -> 644
```
- Impact: these situations are rare, but the command lies (`✓ disabled`, exit 0), and `mv` prompts
  on stdin, outside `ui::confirm` / `_CB_TTY` (rule 5). `cb::rc_replace` keeps the file mode; the
  config writers do not.
- Fix: one shared `cb::config_write` helper. It refuses (`ui::die`) a path that exists and is
  not a regular writable file, copies the mode like `cb::rc_replace`, uses `mv -f`, and
  checks the status before reporting success. `cb::config_load` reports a non-regular or
  unreadable config in `_CB_CONFIG_ERRORS` instead of letting Bash print. — Cost: S
- Decision: architecture.md:149-150 promises an atomic rewrite; it should also promise "or a
  clear error".

### RTE-08 Plugin and command names depend on the locale (`café` exists under en_US.UTF-8, not under C)
- Severity: minor   - Status: VERIFIED
- Aspect: discovery   - Location: lib/util.sh:16 (`cb::valid_name`), lib/config.sh:15 (`cb::valid_id`)
- Evidence:
```
$ locale | grep LANG          -> LANG=en_US.UTF-8
$ (plugins/café with flags.sh + cmd.sh) tt café      -> runs
$ LC_ALL=C tt café            -> ✗ unknown command 'café'   rc=2
$ LC_ALL=C.UTF-8 tt café      -> ✗ unknown command 'café'   rc=2
```
  In a Bash regex, `[a-zA-Z]` is a collation range: in most UTF-8 locales it also matches
  accented letters.
- Impact: a plugin that works in the terminal disappears in cron, in CI or in `LC_ALL=C`
  scripts. The documented rule (architecture.md:34) is not the one the code enforces.
- Fix: put `local LC_ALL=C` at the top of both functions (Bash re-reads the locale when it is
  assigned), or spell out the classes. — Cost: XS
- Decision: none.

### RTE-09 Directories with an invalid name are ignored silently, by the doctor too
- Severity: minor   - Status: VERIFIED
- Aspect: discovery / doctor   - Location: lib/plugins.sh:27, :69; lib/util.sh:40, :47
- Evidence: `plugins/my plugin/`, `plugins/a+b/`, `plugins/+my ext/disk/` and
  `plugins/++system/disk/`, each with flags.sh + cmd.sh:
```
$ tt self doctor | grep plugin    -> ✓ 7 plugin(s) found, 7 active     (nothing about the 4 others)
$ tt 'my plugin'                  -> ✗ unknown command 'my plugin'
```
- Impact: a user, or an AI that ran `mkdir`, picks a name with a space or a `+` inside and gets a
  command that "does not exist", with no clue why.
- Fix: the doctor warns about command directories (they contain flags.sh, cmd.sh or cmd) whose
  name is invalid, except the deliberately ignored `_*` and `.*`. Same while walking
  subcommands. — Cost: S
- Decision: 0001 ignores `_` and `.` on purpose; other invalid names should be reported.

### RTE-10 `self doctor` never checks the commands of a disabled, inactive or orphan extension (it does check disabled plugins)
- Severity: minor   - Status: VERIFIED
- Aspect: doctor   - Location: builtin/self/doctor/cmd.sh:102-105
- Evidence:
```
$ printf 'flag x\n' > $P/+nope/bad/flags.sh                    # orphan extension, invalid DSL
$ printf 'flag y bogus "d"\n' > $P/+system/bad2/flags.sh        # plus 'disable user:+system'
$ tt self doctor; echo rc=$?
  ! user:+nope extends core:nope, which does not exist: it is inactive (...)
  ✓ 23 valid command(s)
rc=0
```
- Impact: the errors only show up once the extension becomes active, for example after
  renaming `+nope` to `nope` as the warning advises.
- Fix: for an extension whose state is not `extends:*`, walk its directory on its own and run
  the flags.sh checks (skip the examples). — Cost: XS
- Decision: none.

### RTE-11 `self doctor` warns on valid examples that use a pipe or a redirection
- Severity: minor   - Status: VERIFIED
- Aspect: doctor examples   - Location: builtin/self/doctor/cmd.sh:14-48
- Evidence:
```
example "router sub | grep x" "pipe"      -> ! ...: example 'router sub | grep x': unexpected argument '|'
example "router sub > out.txt" "redirect" -> ! ...: example 'router sub > out.txt': unexpected argument '>'
```
- Fix: cut the word list at the first shell operator word (`|`, `||`, `&&`, `;`, `&`, `>`,
  `>>`, `<`, `2>`, `2>&1`). — Cost: XS
- Decision: none.

### RTE-12 Conflict hints suggest adding a `rename` that already exists; duplicate renames are silent; the "disabled" hint ignores directory names
- Severity: minor   - Status: VERIFIED
- Aspect: renames / messages   - Location: lib/plugins.sh:40, :46; lib/config.sh:37-38; lib/router.sh:44-48
- Evidence (doctor output, one config per line):
```
rename core:system self    -> ! core:system: 'self' is reserved for tt → add 'rename core:system <name>' to the config
rename core:system backup  -> ! 'backup': user:backup shadows core:system → add 'rename core:system <name>' ...
rename user:a x + rename user:a y   -> (nothing: the last line wins silently)
rename core:system sys + disable core:system:
  $ tt system  -> ✗ unknown command 'system'   (no hint)
  $ tt sys     -> ✗ unknown command 'sys'  Plugin core:system is disabled: 'tt self plugins enable core:system'
```
- Fix: when `_CB_RENAME[$id]` is set, say "the config renames core:system to 'self': change
  that line". Collect duplicate `rename` lines for the same id as config errors. In
  `cb::_unknown_plugin`, also match `${id#*:} == $name`. — Cost: XS
- Decision: 0003 unchanged.

### RTE-13 `cb::suggest` misses common typos and is noisy for short words
- Severity: suggestion   - Status: VERIFIED
- Aspect: UX   - Location: lib/util.sh:95-106
- Evidence: `tt sistem` and `tt dystem` give no suggestion (the first two letters differ).
  `tt e` gives "Did you mean: system, self?" (every name containing "e"). `tt self docter`
  correctly suggests doctor.
- Fix: a pure-Bash optimal-string-alignment distance (≤ 2, or ≤ 1 for words of up to 4
  letters) plus prefix matches, sorted by distance. Strings are short, so this is cheap. — Cost: S

### RTE-14 No "Did you mean" after a command that has its own executable (`tt self deps manager`): design of the fix
- Severity: suggestion (documented in roadmap.md:92-93)   - Status: VERIFIED (prototype)
- Aspect: routing UX   - Location: lib/parse.sh:149-155
- Evidence: `tt self deps manager` -> `✗ unexpected argument 'manager'` and nothing else
  (same with `tt self deps managers ad`).
- Fix (prototyped in the sandbox, suite green): in the "unexpected argument" branch, when `i == 0`
  (no `arg` consumed a word) and the command has children, add the suggestion:
```bash
    if ((i == 0)); then
      local _cb_s
      _cb_s=$(cb::suggest "$val" $(cb::children "$_CB_DIR"))
      [[ -n $_cb_s ]] && cb::_parse_err "unexpected argument '$val'" "Did you mean: $_cb_s?"
    fi
```
  Result: `✗ unexpected argument 'manager'` / `Did you mean: managers?`. `tt system info extra`
  is unchanged. This only touches an error path, so the 0001 rule ("a child name wins") is not
  affected. When the command declares an `arg`, the typo is a valid positional and nothing can
  be said at run time (RTE-04). — Cost: XS (+ test, remove the roadmap limitation)

### RTE-15 Doctor gaps: CRLF in flags.sh / cmd.sh, missing `about`, a router that declares args
- Severity: suggestion   - Status: VERIFIED
- Aspect: doctor   - Location: builtin/self/doctor/cmd.sh:106-127
- Evidence: a CRLF `flags.sh` + `cmd.sh` raise no doctor message. At run time `--help` shows
  `Win file^M` and the command prints `v=1^M` (a CRLF `cmd.sh` with `cd dir` fails at run
  time). A command without `about` and a pure router that declares `arg target` / `flag force`
  (unusable: `tt router x` -> unknown subcommand) are not reported either. (`cmd` without a shebang
  works: not an issue.)
- Fix: warnings for `$'\r'` in flags.sh / cmd.sh (relevant on WSL), a missing `about`,
  `arg`/`flag` on a command without an executable, and static `--choices` values that equal a child name.
  — Cost: S

### RTE-16 `self guide -o -` writes a file named `-`; `-o` into a missing directory prints a raw Bash error first
- Severity: minor   - Status: VERIFIED
- Aspect: self guide   - Location: builtin/self/guide/cmd.sh:100-111
- Evidence: `tt self guide -o -` -> `✓ Guide written to -`, rc=0, and a 27 KB file `./-` is created
  (the `self new` skeleton itself suggests `--default "-"` for an output flag).
  `-o $SB/nodir/g.md` -> `.../guide/cmd.sh: line 109: ...: No such file or directory`, then
  `✗ cannot write ...`, rc=1.
- Fix: treat `-` as stdout; redirect the raw error: `{ printf ... >"$FLAG_OUTPUT"; } 2>/dev/null`.
  — Cost: XS

### RTE-17 `self plugins` columns break for names over 18 characters
- Severity: minor (cosmetic)   - Status: VERIFIED
- Location: builtin/self/plugins/cmd.sh:24, :26
- Evidence: `a-very-long-plugin-name-here user:a-very-long-plugin-name-here  active` (the
  columns shift).
- Fix: compute the widths from the data. — Cost: XS

### RTE-18 Root edge cases: `tt ''` = help + exit 0, `tt -- x` rejected, no `--version`, `tt help`
- Severity: minor   - Status: VERIFIED
- Location: lib/router.sh:17-26
- Evidence: `tt ''` prints the root help with exit 0, so a script running `tt "$cmd"` with an
  empty variable "succeeds". `tt -- system` -> `✗ unknown option '--'`. `tt --version` -> unknown
  option, and the doctor shows no version either. `tt help` -> unknown command, no hint.
- Fix: when `$# > 0 && -z $1`, report "unknown command ''" (exit 2); accept `--` at the root;
  add `--version` (`git -C "$CB_ROOT" describe --always --dirty`, also shown by the doctor). — Cost: XS

Note on RTE-03: the ancestor-check prototype (`[[ $d -ef $a ]]` against the chain passed down
to `cb::walk`) brought the two-loop fixture (`a/x -> .`, `a/y -> .`, `a/sub/up -> ..`) down to
doctor 1.4 s, guide 0.3 s, deps 0.1 s. The guide then lists only `tt a` and `tt a sub`,
routing (`tt a x y sub up sub`) still works, and the suite stays green.

## What is good and must be kept
- A single extension-aware traversal API (`cb::children` / `cb::is_child` / `cb::child_dir`):
  routing, help, doctor and guide cannot disagree.
- `cb::is_child` validates the word before touching the disk: `tt system ../../x` cannot
  traverse directories.
- Conflicts are never silent (0003): `self plugins`, `self doctor` and the root help all
  report them; the ambiguous name in `self plugins disable system` is refused with the ids.
- The config parser never aborts: errors are collected and reported by the doctor. Tabs,
  inline `#`, a missing final newline and unknown ids are handled (an unknown id gets a warning).
- `self new` refuses before writing anything, escapes `about` (`cb::dq`), and refuses `self`,
  official commands and official plugins as targets.
- The parser hint "'restore' is a subcommand: put the options after it" (lib/parse.sh:152).
- The guide never substitutes placeholders inside user content (`__CB_NAME__` in an `about`
  stays literal) and quotes the request with `> `.
- The doctor exit codes (errors 1, warnings 0) and its broken-install report (missing link =
  error, missing completion = warning).
- Symlinked plugins and extensions work, and `CB_PLUGIN_ROOT` keeps the logical path.

## Risks for the future
- Every new "words -> directory" feature (aliases, hidden commands, `self plugins install`)
  must resolve **exposed** names the way the router does. RTE-01 shows how easy it is to
  forget. A single `cb::resolve_words <words...>` helper returning id + directory + exposed
  path would serve the router, `self new`, the doctor examples and help.
- Command aliases (accepted in the roadmap) will probably be tried with symlinks first.
  Without RTE-03, an alias to an ancestor hangs the tools.
- Inherited flags (roadmap) will make RTE-04 worse: more flags will be valid on the parent,
  so `mu x -v sub` will more often silently run the parent.
- `flags.sh` is sourced by doctor, guide, completion and deps: any slowness or side effect
  in a plugin's flags.sh multiplies with the walk (and with RTE-03).

## Open questions for the owner
1. RTE-04: when routing stopped on an option and a later positional is a subcommand name,
   should it be a warning (compatible, recommended) or an error (strict)? Recommendation:
   a warning plus documenting `--`; fix the README wording in any case.
2. RTE-01: should `self new <name>` accept a plugin's directory name when the plugin is
   exposed under another name, or refuse and point to the exposed name? Recommendation:
   accept both, map them to the right directory, and always print the exposed path.
3. RTE-02: should `self new` refuse to extend a disabled or shadowed official plugin, or warn?
   Recommendation: warn (the files stay useful once the plugin is re-enabled).
4. RTE-18: add `--version`? Recommendation: yes, from `git describe`, also shown by
   `self doctor`, which is useful in bug reports.
5. RTE-08: officially ASCII-only names (recommended, matches the docs), or allow Unicode
   everywhere?

## View on decision 0001 ("a child name always wins over a positional")
Keep it: it is what lets a command with an `arg` also have subcommands, and it is
predictable. It bites in three cases:
- (a) options typed before the subcommand (RTE-04): silent when the parent has an `arg`;
- (b) a value that equals a child name, which can only be passed after `--` (undocumented);
- (c) a subcommand added later captures a value that scripts used to pass.
The error message is good when the parent takes no positional (parse.sh:152), and nothing
at all is shown in the silent cases. Needed: document `--` and "options after subcommands",
add the RTE-04 warning, and have the doctor flag `--choices` values that equal child names.
