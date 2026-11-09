# architecture — architecture, maintainability & conventions, product vision

## Scope and method

**Read in full**: `AGENTS.md`, `docs/handoff.md`, `docs/architecture.md`, `docs/conventions.md`,
`docs/roadmap.md`, every `docs/decisions/*.md` (0001–0014 + index), `main.sh`, `init.sh`,
every `lib/*.sh`, every file of `builtin/self/`, `core/system/`, `templates/completion.{bash,zsh}`.
`tests/run.sh` and `templates/ai-guide.md` only through targeted greps (other reviewers own them).

**Static analysis (scripted, read-only on the repo)**: call graph between `lib/` files, writer/reader
inventory of every `_CB_*` global, cross-file use of `cb::_*` helpers, unused functions (none found),
function sizes with a rough decision-point count, convention greps (`set -e`, `[ ]`, `echo "$…`,
unquoted expansions, hard-coded package-manager lists, globals missing from the docs).

**Sandbox experiments** (helper `mksandbox.sh`, root name `tt`, sandbox deleted at the end):
symlinked subcommand as an alias; symlink loop; `self new` under a renamed official plugin;
config file mode after rewrites; `arg a-b` + `arg a_b`; glob characters in `--choices`; option
before a subcommand; `_wip` directory; a future DSL option and a future DSL keyword on today's code;
examples under a renamed plugin; `self update` to a release that adds a cross-file helper
(local bare repo, no network); timings (10 runs each).

**Not covered**: zsh (not installed), macOS / Bash 4.2 (not available), performance beyond a
few timings, security, the AI guide content (other reviewers).

## Grade

| Aspect | Grade | Why |
|---|---|---|
| Architecture (structure, process model, extension mechanism) | **B** | Clean, acyclic layering (util/ui → config/plugins/spec → help/parse/complete → router), small files (largest 252 lines), a sound fresh-process model (decision 0005) and a well-isolated overlay for extensions. Weak points: the routing loop exists in 4 copies that already disagree (ARC-02, ARC-01, ARC-12), `self update` mixes two code versions in one process (ARC-03), and the generic `util.sh` depends on plugin state (`_CB_OVL`) and layout. |
| Evolvability (Accepted roadmap items, contract migration) | **C+** | Every Accepted item is feasible compatibly (designs in Annex B), but three things make them costlier than they should be: the routing copies (each item touching routing must be done 3–4 times), the single-spec state (inherited flags need a merge mode), and the absence of any version number: a shared plugin using a new DSL option breaks with exit 3 on an older machine, with no hint (ARC-11). |
| Maintainability & conventions | **B+** | Conventions are mostly respected and several are enforced by tests (no `declare -g` in functions, no emoji symbols). No `set -e`, no `[ ]`, no unsafe `echo`, no dead functions. Deviations: hand-made tree walk in `self new` (convention docs/conventions.md:37-38, 52-53), undocumented globals and a dynamic-scope protocol (ARC-09), duplicated status symbols / config rewriters / bootstrap / PM lists (ARC-05, ARC-10), two unquoted splits without the required comment (ARC-07). |
| Product vision | **B** | Strong where the owner's goals are (safety, idempotence, AI-assisted authoring, `self guide`, doctor checking examples). Missing for daily use on several machines: a version, reproducing a plugin set on another machine, and command discovery/editing (`which`/`edit`/tree). Some surface (`self deps` = 6 commands) is large for a personal tool and should be frozen. |

## Findings

Counts: **1 major, 10 minor, 2 suggestions**. All VERIFIED unless stated.

### ARC-01 `self new` ignores renames: under a renamed official plugin it creates a shadowing plugin (the bug decision 0013 fixed comes back)
- Severity: major   - Status: VERIFIED
- Aspect: architecture / conventions   - Location: builtin/self/new/cmd.sh:16-36, builtin/self/new/cmd.sh:107; docs/conventions.md:37-38, docs/conventions.md:52-53
- Evidence (sandbox, `rename core:system sys` in the config):
  ```
  $ tt sys info -s >/dev/null && echo "before: 'tt sys info' works"
  before: 'tt sys info' works
  $ tt self new sys disk -a 'Disk usage'
  ✓ Command 'tt sys disk' created
    + plugins/sys/
    + plugins/sys/flags.sh
    + plugins/sys/disk/
  $ tt sys info -s
  ✗ unknown subcommand 'info'
  $ tt self plugins
    sys                core:system           shadowed by user:sys (renamed)
    sys                user:sys              active
  ```
  `self new` works on **directory names** (`cb::is_command_dir "$base/$1"`, `"$CB_ROOT/core/$1"`,
  `$udir/$name`, `$official/$name`, new/cmd.sh:16-33) and never loads the config or the plugins,
  whereas the user (and the AI guide) speak in **exposed names**. Conversely `self new system disk`
  with that rename creates `plugins/+system/disk` (reachable as `tt sys disk`) but prints
  "Command 'tt system disk' created" (new/cmd.sh:107) — not run, read from the code.
- Impact: anyone who followed decision 0003's advice (`rename` to keep both plugins) and then
  asks `self new <what they see>`: the official commands of that plugin disappear, `self doctor`
  reports a conflict the user did not create. Same class of bug as the one decision 0013 was
  written for ("`mu self new system disk` … hid `mu system info`").
- Fix: make `self new` resolve words like the router: load config + plugins; if `words[0]` is the
  exposed name of `core:<d>` → extension `plugins/+<d>/…`; of `user:<d>` → `plugins/<d>/…`; else a
  new plugin (refuse a name that is the *directory* name of a renamed plugin with a hint). Walk the
  rest with `cb::is_child` / `cb::child_dir` (or the `cb::route` of ARC-02) and print the real command
  path. Tests: rename + `self new` both ways. — Cost: S
- Decision: 0013 needs no change; this is an implementation gap of its convention.

### ARC-02 The routing loop exists in four copies, which already disagree
- Severity: minor   - Status: VERIFIED (code + consequences ARC-01, ARC-12)
- Aspect: maintainability / evolvability   - Location: lib/router.sh:28-38, lib/complete.sh:71-82, builtin/self/doctor/cmd.sh:21-36, builtin/self/new/cmd.sh:14-36; docs/architecture.md:124-125
- Evidence: each copy re-implements "plugin lookup + greedy `cb::is_child` / `cb::child_dir`":
  `cb::main` (router.sh), `cb::complete` (computes `CB_PLUGIN_ROOT` itself, complete.sh:72-82),
  doctor's `check_example` (also accepts the plugin's **directory** name, doctor/cmd.sh:22), and
  `self new` (directory names only, ARC-01). Divergences proven: ARC-01 (self new vs router) and
  ARC-12 (doctor accepts examples the router rejects). docs/architecture.md:124-125 says "The engine
  reuses the real routing … so completion can never disagree with execution": it reuses the
  helpers, not the routing.
- Impact: every Accepted item that touches routing (aliases, hidden commands, inherited flags) must be
  written 3–4 times, and each copy can drift silently.
- Fix: one `cb::route <words…>` in lib/router.sh filling `_CB_ROUTE_DIR`, `_CB_ROUTE_ROOT`
  (plugin root), `_CB_ROUTE_USED` (words consumed) and `_CB_ROUTE_CHAIN=()` (directories, needed by
  inherited flags), used by `cb::main`, `cb::complete`, `check_example` and `self new`. Do it before
  the Accepted items. — Cost: S
- Decision: none.

### ARC-03 `self update` runs the rest of its job with the old code mixed with the new files
- Severity: minor   - Status: VERIFIED (deps part) / NOT VERIFIED (completion part, reasoned)
- Aspect: architecture (process model)   - Location: builtin/self/update/cmd.sh:52, builtin/self/update/cmd.sh:65, builtin/self/update/cmd.sh:76-79
- Evidence: local bare repo; the "next release" adds `cb::deps_header` to lib/util.sh and calls it
  from `cb::deps_collect` (an ordinary refactoring):
  ```
  $ _CB_TTY=$S/yes uu self update
  › 1 new commit(s) on origin/main:
      36baf6d refactor: deps header
  ? Update? [Y/n] ✓ updated
  ✓ 1/1 repository(ies) updated.
  $S/install/lib/deps.sh: line 78: cb::deps_header: command not found
  rc=0
  ```
  After `git pull`, the process still holds the **old** lib functions in memory, then sources the
  **new** `lib/deps.sh` (update/cmd.sh:76) and calls the old `cb::completion_install` on the **new**
  templates (update/cmd.sh:65). A release that adds a placeholder to `templates/completion.*` would
  have it written unreplaced, and completion is only regenerated when the root repo changes again.
- Impact: every user, on any release that moves code between lib files or changes a template
  contract: an error right after "updated" (exit 0), or a broken completion file until next update.
- Fix: after a successful pull of `$CB_ROOT`, run the post-update steps in a fresh process from the
  new code, e.g. `"$BASH" "$CB_ROOT/lib/run.sh" "$CB_COMMAND_DIR/_post.sh"` (env is already exported),
  `_post.sh` doing `cb::completion_install` + the deps reminder. Test: the reproduction above. — Cost: XS
- Decision: 0005 (fresh process) — apply its own principle to self update.

### ARC-04 A symlinked subcommand already works as an alias, but is shown as a second command everywhere
- Severity: suggestion   - Status: VERIFIED
- Aspect: evolvability (roadmap "Command aliases")   - Location: lib/util.sh:34-49, lib/util.sh:65-71
- Evidence (`plugins/bk/ls -> list`):
  ```
  $ tt bk ls -l
  list cmd=tt bk ls dir=…/plugins/bk/ls
  $ tt bk --help            →  Commands:  list  List backups / ls  List backups
  $ tt __complete -- bk ''  →  list ls
  $ tt self deps            →  fzf  missing (optional)  -  tt bk list, tt bk ls
  $ tt self guide           →  - `tt bk list` (command, …)  /  - `tt bk ls` (command, …)
  ```
  `"$1"/*/` matches symlinks to directories, so the alias is a full child for help, completion,
  `cb::walk` (doctor count, deps users, guide). A symlink to an ancestor (`again -> .`) makes walks
  recurse until the kernel's ELOOP limit (doctor took 3 s, terminated).
- Impact: none today (undocumented); it is the cheapest compatible design for the Accepted alias item.
- Fix: make it first-class (design in Annex B.3): a child that is a symlink to a sibling is an alias:
  `list (ls)` in help, "alias of list" in completion, skipped by `cb::walk`; refuse symlinks to an
  ancestor in doctor. — Cost: S
- Decision: new record for aliases; 0001 unchanged (one directory per command still holds).

### ARC-05 Config rewriters drop the file mode, and are two copies of the same code
- Severity: minor   - Status: VERIFIED
- Aspect: maintainability / safety   - Location: lib/config.sh:78-92, lib/config.sh:95-109 (writes at :91 and :107); compare lib/install.sh:88
- Evidence:
  ```
  $ chmod 600 ~/.config/tt/config; tt self plugins disable core:system; stat -c %a …  → 644 after disable
  $ chmod 600 …; tt self deps managers add apt; stat -c %a …                         → 644 after managers add
  ```
  `cb::rc_replace` keeps the mode of rc files (install.sh:88); the two config rewriters (same
  read-filter-append-realpath-tmp-mv skeleton) do not.
- Impact: low today (no secrets in `config`), but users who restrict their config (dotfiles tools)
  see it reset, and any future directive (per-plugin settings, ARC Annex C) would inherit the leak.
- Fix: one `cb::_config_rewrite <drop-keyword> [<drop-arg>] -- <lines to append…>` + a shared
  `cb::copy_mode <ref> <file>` (moved from install.sh:88 to util.sh). — Cost: S
- Decision: none.

### ARC-06 `arg a-b` and `arg a_b` silently share `ARG_A_B`
- Severity: minor   - Status: VERIFIED
- Aspect: plugin contract   - Location: lib/spec.sh:224, lib/spec.sh:238, lib/parse.sh:167-170
- Evidence:
  ```
  $ cat plugins/col/flags.sh   →  arg a-b "first" / arg a_b "second"
  $ tt col one two             →  ARG_A_B=two argv=one two
  $ tt self doctor             →  ✓ 22 valid command(s)
  ```
  Arg names accept `-` and `_` (flags only `-`, spec.sh:161); both map to `_` at export.
- Impact: rare misuse; the first value is lost without any error.
- Fix: in `arg()`, reject a name whose `${name//-/_}` matches an existing arg's (DSL error, exit 3).
  Do not forbid `_` (rule 2). — Cost: XS

### ARC-07 Static `--choices` are glob-expanded in completion (and in the default check)
- Severity: minor   - Status: VERIFIED
- Aspect: conventions (quoting)   - Location: lib/spec.sh:45, lib/spec.sh:203; validator lib/spec.sh:57; also lib/router.sh:87
- Evidence (`--choices "a* b"`, files `abc.txt alpha.log` in the current directory):
  ```
  $ tt __complete -- gl --sel ''   →  abc.txt alpha.log b
  $ tt gl --sel abc.txt            →  ✗ --sel: invalid value 'abc.txt' (choices: a*, b)
  ```
  `for c in $static` globs; the validator uses `read -ra` (no glob), so completion offers values the
  parser rejects. docs/conventions.md:27-28 requires a comment when splitting is intended: missing at
  spec.sh:45 and router.sh:87 (`$(cb::children …)`, safe because names are validated).
- Impact: edge case (a choice with `*`, `?`, `[`).
- Fix: `read -ra` in `cb::choices_of` and at spec.sh:203; add the comment at router.sh:87. — Cost: XS

### ARC-08 Flags declared on a pure router are accepted but can never be used
- Severity: minor   - Status: VERIFIED
- Aspect: plugin contract / evolvability   - Location: lib/router.sh:77-92, lib/help.sh:58
- Evidence (`plugins/bk/flags.sh` declares `flag verbose -v bool`, `bk` has no cmd.sh):
  ```
  $ tt bk -v db       →  ✗ unknown option '-v'
  $ tt self doctor    →  (no warning about bk)
  ```
- Impact: an author (or an AI) who expects group-level options gets an "unknown option" for a
  declared flag; help hides it. Good news for ARC Annex B.2: no existing plugin can depend on these
  flags, so opt-in inherited flags can give them a meaning compatibly.
- Fix now: doctor warning "flags/args of a command without cmd.sh are ignored". — Cost: XS

### ARC-09 Undocumented globals, out-parameters and a dynamic-scope protocol
- Severity: minor   - Status: VERIFIED (grep)
- Aspect: maintainability / docs drift   - Location: lib/parse.sh:45, lib/spec.sh:55, lib/spec.sh:71, lib/spec.sh:75-81, lib/spec.sh:160, lib/spec.sh:223, lib/complete.sh:25, lib/ui.sh:17-19; docs/architecture.md:89-102
- Evidence: absent from docs/architecture.md and docs/conventions.md: `_CB_DIR`, `_CB_DISPLAY`
  (set by `cb::parse`), `_CB_CHOICES_LIST`, `_CB_OPT_SHIFT`, `_CB_TV_FLAG` (out-parameters), `_UI_*`
  (stderr colours, a prefix not in the naming table, docs/conventions.md:42-50).
  `cb::_spec_choice_opt` writes `_o_choices/_o_from/_o_strict`, which are **locals of its callers**
  `flag()`/`arg()` (Bash dynamic scope); called from anywhere else it would create globals. The doc
  tests check DSL options, `CB_*`, `ui::`, self commands, config directives and lib files, not `_CB_*`.
- Impact: the "Global state" table drifts; the next DSL option shared by flag/arg must know an
  unwritten protocol.
- Fix: add the rows; comment the `_o_*` protocol at spec.sh:68-69; add a doc test "every `_CB_*`
  assigned in lib/ is in architecture.md" (in the owner's "docs never drift" line). — Cost: XS

### ARC-10 Duplications: status symbols, bootstrap, install steps, PM lists, "Did you mean"
- Severity: minor   - Status: VERIFIED (code; doctor output below)
- Aspect: maintainability   - Location: see list
- Evidence:
  1. doctor's `ok/ko/wa` re-implement the `ui::` symbols on stdout (builtin/self/doctor/cmd.sh:7-9 vs
     lib/ui.sh:23-25), and capture `ui::error` output inside their own message (doctor/cmd.sh:111,118):
     `  ✗ plugins/nx/a: ✗ /…/plugins/nx/a/flags.sh:2: unknown option '--repeatable' for flag --tag`
     (double symbol, absolute path). doctor also overrides `ui::error` (doctor/cmd.sh:40).
  2. Bootstrap `source lib/core.sh; cb::config_load; cb::plugins_load` in 6 builtin files
     (builtin/self/plugins/cmd.sh:1-3, plugins/_resolve.sh:2-4, deps/_common.sh:2-5, doctor/cmd.sh:1-4,
     guide/cmd.sh:1-3, update/cmd.sh:1+76-78), redoing in the child what `cb::main` just did
     (lib/router.sh:7-8). `deps/_common.sh:6` also runs `cb::deps_collect` (sources every flags.sh)
     for `self deps managers [add|remove]`, which do not need it (55 ms vs 36 ms for `self plugins`).
  3. init.sh:139 `rc_block()` (asks, then appends) vs lib/install.sh:36 `cb::rc_block` (prints the
     block): same name, different jobs. The install steps (link, config, completion, rc append:
     init.sh:124-136, init.sh:150-156) are re-coded in builtin/self/rename/cmd.sh:72-102, 106-112,
     although decision 0012 puts "anything that knows the install layout" in lib/install.sh.
  4. The package-manager list is hard-coded in 5 code files: lib/config.sh:13, lib/spec.sh:137,146,
     lib/deps.sh:17 and :60-73, builtin/self/deps/managers/add/flags.sh:2, managers/flags.sh:3.
  5. "Did you mean" built 3 times (lib/router.sh:49-50, :87-88, lib/parse.sh:74-75).
  6. `cb::_rows` (a "helper of one file", docs/conventions.md:45) is used by builtin/self/plugins/cmd.sh:27.
- Impact: every change of the symbol rule, the install layout or the PM list must be made in several
  places; the doctor output is already inconsistent.
- Fix: `ui::_mark <ok|ko|warn>` used by both ui and doctor (and strip the inner symbol);
  `lib/self.sh` with `cb::self_init [deps] [install]`; `cb::install_link` / `cb::rc_enable` in
  lib/install.sh; `--choices "${_CB_PM_ALL[*]}"` in managers/add/flags.sh (sourced in the framework
  process); rename `cb::_rows` → `cb::rows`; lazy `cb::deps_collect`. — Cost: S (all)

### ARC-11 No version number: the plugin contract cannot evolve safely across machines
- Severity: minor   - Status: VERIFIED
- Aspect: product / evolvability   - Location: main.sh, lib/core.sh, lib/router.sh:21-25, lib/spec.sh:113-123, lib/spec.sh:106-111
- Evidence:
  ```
  $ tt --version                      →  ✗ unknown option '--version'   rc=2
  $ grep CB_VERSION…; git tag         →  (nothing)
  # a flags.sh written for a future DSL option, on today's code:
  $ tt nx a      →  ✗ …/plugins/nx/a/flags.sh:2: unknown option '--repeatable' for flag --tag   rc=3
  $ tt nx --help →  Commands:  a  (empty about)   b  Uses a future DSL keyword
  # a future DSL keyword:
  $ tt nx b      →  …/flags.sh: line 2: hidden: command not found / b-ran   rc=0
  ```
  A new *option* of an existing keyword is a hard failure with no "update" hint; a new *keyword*
  only warns. `cb::about_of` returns an empty summary for any flags.sh failing after its `about`.
- Impact: the owner's main use case (the same plugins on several machines, updated at different
  times): the first DSL extension (repeatable or inherited flags) breaks shared plugins on machines
  not yet updated, with a cryptic message. Issues and the guide cannot say which version they
  describe.
- Fix (before any DSL extension): `CB_VERSION` in lib/core.sh + `<name> --version` + version in
  `self doctor` and `self guide`; git tags; DSL errors of the kind "unknown option/keyword" end with
  "this flags.sh may need a newer cmd-builder (yours: X): run '<name> self update'" (catch unknown
  keywords with a `command_not_found_handle` defined during `cb::spec_load`). — Cost: S
- Decision: new record (versioning and contract evolution); complements rule 2.

### ARC-12 Examples do not follow a rename, and doctor accepts them
- Severity: minor   - Status: VERIFIED
- Aspect: architecture (rename is second-class)   - Location: lib/help.sh:84-90, builtin/self/doctor/cmd.sh:21-23
- Evidence (`rename core:system sys`):
  ```
  $ tt sys info --help   →  Examples:  tt system info / tt system info -s
  $ tt system info -s    →  ✗ unknown command 'system'  Did you mean: sys?   rc=2
  $ tt self doctor | grep -ci example   →  0
  ```
- Impact: copy-pasting an example from `--help` fails for every renamed plugin (and extension).
- Fix: in `cb::help`, replace the first word of an example by the exposed name when it is the
  plugin's directory name (the doctor leniency then matches what help prints). — Cost: XS

### ARC-13 Generic `util.sh` holds plugin-layout knowledge
- Severity: suggestion   - Status: VERIFIED (code)
- Aspect: architecture   - Location: lib/util.sh:34-61 (reads `_CB_OVL`, declared lib/plugins.sh:15), lib/util.sh:75-84 (`$CB_ROOT/plugins/+*` hard-coded)
- Evidence: the only data dependency against the layering (util.sh is a leaf by calls but reads the
  overlay state), and `cb::plugin_root_of` hard-codes where extensions live.
- Impact: lifting the known limitation "extensions only extend official plugins" or adding aliases
  will need to change "generic" helpers.
- Fix: move `cb::children / is_child / child_dir / walk / plugin_root_of` to `lib/tree.sh` (or
  plugins.sh), next to the code that builds `_CB_OVL`. — Cost: XS (+ docs table)

## What is good and must be kept

- The **fresh-process model** (decision 0005): `exec` into `lib/run.sh`, env-var contract readable
  from any language, inherited `FLAG_*`/`ARG_*` cleared (lib/parse.sh:162). It is what makes plugins
  in other languages and nested calls safe.
- **One directory per command** with greedy routing (0001) and the `+` extensions (0013): discovery
  never sources files (only `about_of` for listings), the tree is readable as-is.
- **Small, acyclic code base**: 13 lib files, about 2 600 lines in total with the builtins; only 5 functions
  above 60 lines (`cb::parse` 114, `cb::complete` 104, `cb::help` 66, `ui::select` 64, `flag` 61);
  no dead function found; builtins written with the framework itself.
- **Safety by construction**: `_CB_TTY` + "no terminal = no" (0009), atomic rc rewrites preserving
  mode and symlinks (lib/install.sh:56-90), resumable rename with the old link last.
- **Docs that are tested**: DSL/`CB_*`/`ui::`/self/config/lib checks, the executed guide example and
  flags example, convention tests (`declare -g`, emoji symbols). Keep extending this (ARC-09).
- **Decision records** that explain rejected alternatives: they made this review fast.
- Performance is fine for a personal tool: 25–55 ms per invocation or Tab.

## Risks for the future

1. **Contract migration without a version** (ARC-11): the first DSL extension is the trigger.
2. **Routing copies** (ARC-02): each Accepted item multiplies the divergence risk proven by ARC-01/12.
3. **Self-update mixing versions** (ARC-03): latent until the first cross-file refactoring.
4. **`flags.sh` must stay side-effect free and fast, but nothing enforces it**: it is sourced at every
   Tab, every help (once per child), by doctor (twice per command), deps, guide and update. A slow
   `flags.sh` (or one doing `curl`) degrades everything; doctor could time each spec load.
5. **Global state growth**: about 50 `_CB_*` globals, each new flag property adds an associative array
   reset in `cb::spec_reset`; acceptable in Bash, but document them (ARC-09).
6. **Builtin surface**: 15 `self` commands, 6 of them for `deps`. Each one is a contract with users
   and with the guide; prefer freezing `deps` (roadmap ideas pip/cargo/npm should stay ideas).
7. **Rename is a second-class citizen**: ARC-01 and ARC-12 are two places where exposed names and
   directory names are confused; any new feature taking command words must use exposed names.

## Open questions for the owner

1. Introduce a version number (`CB_VERSION`, `--version`, git tags, update hint on DSL errors) **before**
   any DSL extension? — Recommendation: yes, next batch (ARC-11).
2. Inherited flags: accepted only after the full command path (`mu backup db restore -v`), or anywhere
   (`mu backup -v db restore`)? — Recommendation: after the path only (keeps greedy routing and the
   existing "put the options after it" hint; "anywhere" needs every level's spec during routing).
3. Aliases as symlinks (`ls -> list`, no DSL, visible in the tree) rather than an `alias` keyword? —
   Recommendation: symlinks (Annex B.3); the keyword would force routing to source children.
4. Hidden commands as a `hidden` keyword in flags.sh rather than a directory marker? —
   Recommendation: keyword (no discovery cost, no rename of the directory when it is ready).
5. Repeatable flags: `FLAG_TAG` newline-joined + `FLAG_TAG_COUNT` + `FLAG_TAG_1..n`, and the same
   `_COUNT`/indexed variables added for variadic args? — Recommendation: yes (Annex B.1).
6. `self plugins install <url>` plus a manifest (`plugin <url> [name]` lines) and `self plugins sync`
   to reproduce your plugins on another machine? — Recommendation: install now, sync right after.
7. Should `self new` speak exposed names (follow renames, ARC-01)? — Recommendation: yes.
8. Freeze `self deps` (no new package sources) unless a concrete need appears? — Recommendation: yes.

---

## Annex A — Architecture map

### A.1 Load and process model

```
~/.local/bin/<name> ─symlink─▶ main.sh ─source─▶ lib/core.sh ─▶ util ui config plugins spec help parse complete router
                                                         cb::main: config_load → plugins_load → route → cb::run
cb::run: spec_load(dir) → parse → _check_requires → export_values
         └─ exec "$BASH" lib/run.sh <dir>/cmd.sh "${_CB_POS[@]}"   (process 2: only ui.sh preloaded)
            └─ builtin self cmd.sh: source lib/core.sh (+ install.sh / deps.sh) AGAIN,
               cb::config_load + cb::plugins_load AGAIN (6 files), then use _CB_* internals
init.sh: core.sh + install.sh + deps.sh (no routing)
```

### A.2 Call graph between lib files (caller → callee; computed)

```
router.sh   → complete config help parse plugins spec ui util   (orchestrator)
parse.sh    → help (on --help) spec ui util
complete.sh → plugins spec util
help.sh     → spec ui util
deps.sh     → config spec ui util          (not loaded by core.sh)
install.sh  → ui util                      (not loaded by core.sh)
spec.sh     → ui util
config.sh   → util
plugins.sh  → util
util.sh, ui.sh, run.sh, core.sh → (none)   but util.sh READS _CB_OVL owned by plugins.sh (ARC-13)
```
Builtins → lib: doctor uses config deps parse plugins spec util (the widest); guide: config help
plugins spec util; rename: complete config install util; update: complete config deps plugins;
plugins/*: config plugins (+ `cb::_rows` of help.sh); new: spec util only (hence ARC-01).

### A.3 Global state inventory (writer → readers)

| Globals | Written by | Read by |
|---|---|---|
| `_CB_DISABLED _CB_RENAME _CB_CONFIG_ERRORS _CB_PMS` (`_CB_PM_ALL` constant) | config.sh (`cb::config_load`, `cb::config_set_package_managers`) | plugins.sh, deps.sh, init.sh, doctor, deps/* |
| `_CB_PLUGINS _CB_PLUGIN_ID _CB_PLUGIN_NAMES _CB_IDS _CB_ID_DIR/NAME/STATE _CB_CONFLICTS` | plugins.sh | router, help, complete, deps, doctor, guide, plugins/*, enable/disable `flags.sh` (`--choices-from`) |
| `_CB_OVL` | plugins.sh (`cb::_overlay`) | util.sh (tree helpers) |
| `_CB_ABOUT _CB_DESC _CB_SPEC_FILE _CB_EXAMPLES _CB_FLAGS _CB_F_* _CB_ARGS _CB_A_* _CB_REQS _CB_R_*` | spec.sh (DSL, reset by `cb::spec_reset`) | help, parse, complete, router (`_CB_REQS`), deps, doctor (`_CB_EXAMPLES`) |
| `_CB_VAL _CB_AVAL _CB_POS _CB_DIR* _CB_DISPLAY*` | parse.sh | parse.sh, router (`_CB_POS`) |
| out-params `_CB_CHOICES_LIST*` / `_CB_OPT_SHIFT*` / `_CB_TV_FLAG*` / `REPLY` | `cb::choice_ok` / `cb::_spec_choice_opt` / `cb::_takes_value` / guide `sub()` | `cb::_choice_err` / `flag`,`arg` / `cb::complete` / guide |
| dynamic scope `_o_choices _o_from _o_strict`* | `cb::_spec_choice_opt` (locals of its caller) | `cb::_spec_choice_check` |
| `_CB_DEP_TOOLS/_REQ/_USERS/_PKG` | deps.sh (`cb::deps_collect`) | doctor, deps/*, update |
| `_CB_BIN_DIR` / `_CB_NO_DYNAMIC` / `_CB_TTY` / `_UI_*`* | install.sh / doctor / environment / ui.sh | init+rename / spec.sh / ui.sh / ui.sh |

`*` = missing from docs/architecture.md (ARC-09). Single-spec-at-a-time: `cb::spec_reset` wipes about 20
arrays at each load; other specs are read in subshells (`cb::about_of` once per listed child,
`cb::deps_collect` and doctor once or twice per command). It is the main obstacle to inherited flags.

## Annex B — Evolvability of the Accepted items

Environment variables cannot hold arrays; formats below keep every existing variable unchanged.

**B.1 Repeatable flags / list type** — DSL: a modifier, not a type: `flag tag -t string "Tag"
--repeatable` (keeps `int` and `--choices` validation per value; `--required` = at least one;
`--default` single value or refused). Env: `FLAG_TAG` = values joined by newlines (one value = today's
format), plus `FLAG_TAG_COUNT=n` and `FLAG_TAG_1..n` (exact for values with spaces/newlines, any
language); DSL error if another flag would produce `FLAG_TAG_COUNT`/`FLAG_TAG_<n>`. Same `_COUNT` +
indexed variables can be **added** for variadic args (fixes the known limitation without breaking the
space-joined `ARG_*`). Plugs into: spec.sh `flag()` (`_CB_F_REP`), parse.sh `cb::_set_flag` (append +
count) and the defaults loop, `cb::export_values`, help.sh (`<string>...`, "(repeatable)"); completion
and doctor need nothing. Decisions: amend 0005. Hard: one string per flag in `_CB_VAL`; the format is
public forever; older installs fail with exit 3 (ARC-11). Cost: M.

**B.2 Opt-in inherited flags** — DSL: `flag verbose -v bool "Verbose" --inherited` in a group's
`flags.sh` (today unusable there, ARC-08, so compatible). Accepted after the full command path,
exported as `FLAG_VERBOSE`; a descendant redeclaring the name or short option = DSL error
(restrictive); help gets an "Inherited options" section. Plugs into: `cb::route` returns the chain of
logical directories (official dirs for extension commands, so `core/system/flags.sh` applies to
`plugins/+system/disk`); `cb::spec_load` gets an ancestor pass (`_CB_SPEC_INHERIT=1`: only
`--inherited` flags kept, other keywords ignored), then the command's own spec; same in
`cb::complete` and `check_example` (hence ARC-02 first). Cost per run: one extra `source` per level,
no fork. Decisions: new record (+0001/0005 consequences). Hard: single-spec state, routing copies.
Cost: M–L.

**B.3 Command aliases** — Symlinks already route (ARC-04). Design: a child that is a symlink to a
sibling directory is an alias: help shows `list (ls)`, completion `ls  alias of list`, `cb::walk` skips
it (doctor, deps, guide), doctor refuses symlinks to an ancestor or outside the plugin. Top-level
plugin aliases (`plugins/b -> backup`) would today be a separate `user:b` plugin: leave out of scope
or treat the same way in `cb::plugins_load`. No DSL change, no routing cost, visible in the tree, git
stores symlinks. Rejected alternative: `alias ls` keyword (routing would source every child, the reason
0013 rejected `extends`). Cost: S.

**B.4 Hidden commands** — DSL keyword `hidden` (like `about`). Free at discovery: help, root help and
completion already source each child through `cb::about_of` (lib/help.sh:79, :104, lib/complete.sh:65,
:138), which can return a hidden mark; routing unchanged (still runnable); excluded from "Did you
mean"; still listed by `self guide` "(hidden)" and checked by doctor. On older installs the keyword
only warns (verified, ARC-11). Cost: S — do it together with aliases (same consumers).

**B.5 `self plugins install <git-url> [--name n]`** — name from the URL (validated; `+<official>`
allowed for an extension repo); refuse an existing target; big warning + `ui::confirm` default N;
`git clone` into `plugins/.<name>.install-tmp` (ignored by routing) then `mv` (atomic; leftover removed
on the next run); then report doctor problems, conflicts it creates and its `requires`
(`self deps install` hint). AGENTS.md rule 3 must list it. Decisions: 0002 + new record. Cost: S
(M with a manifest + `self plugins sync`, Annex C).

**B.6 Timeout for `--choices-from`** — Single plug point `cb::choices_of` (lib/spec.sh:39-48). No
`timeout(1)` on macOS (rule 1): run the snippet in the background in its own process group
(`set -m` in the subshell) writing to a temp file or coproc, `read -t` against a deadline, then kill
the group. Fixed default (e.g. 2 s) + optional config directive rather than a DSL option (no contract
change); at run time with `--strict`, a timeout fails closed with a clear message. Decisions: amend
0006 ("no timeout yet"). Cost: S–M.

## Annex C — Product vision

Missing for daily use, ordered by the owner's goals (several machines, AI authoring, safety):

1. **Version + releases** (ARC-11): `--version`, tags, a short CHANGELOG; doctor and guide print it.
   Every comparable tool has it (bashly, argc, cobra/click/oclif generate `--version`).
2. **Reproduce a setup on another machine**: `self plugins install` (Accepted) + a declarative list
   (`plugin <git-url> [name]` in the config, which can live in dotfiles since symlinked configs are
   supported) + `self plugins sync` (clone missing, confirm each). Closest analogues: basher, zinit.
3. **Discovery and editing**: `self which <words>` (prints the directory and file the router reaches),
   `self edit <words>` (`$EDITOR` on `cmd.sh`, fallback `vi`), `self tree` (every command with its
   summary; the code already exists in `self guide`'s `commands()` and `cb::walk`). Cheap (S) and
   used daily; they must use `cb::route` (ARC-02).
4. **Flag defaults per machine**: e.g. config `default <command words> --flag value` or env
   `<NAME>_<CMD>_<FLAG>`; useful for "my server name here, another there" across machines. Medium;
   decide after repeatable/inherited flags.
5. **Helpers plugins keep re-writing**: `ui::table` (expose `cb::_rows`, same ASCII-left-column
   caveat), `ui::ask` with hidden input for tokens (`read -s`), a documented `--dry-run` / `-v`
   convention in the guide (later as opt-in inherited flags). Spinner/progress: not worth it
   (terminal quirks, Windows Terminal).
6. **Sharing code between plugins**: today only `_lib/` inside one plugin (docs/plugin-authoring.md:18,
   :43). A user-wide `plugins/_shared/` is possible but couples plugins shared with others; keep as an
   idea.
7. **Testing helpers for plugin authors**: doctor's example check already covers the contract; a
   `self test` running examples is risky (side effects) — not recommended.
8. **Man pages**: superfluous (help + guide).

Superfluous or over-engineered: nothing to remove, but freeze `self deps` (6 commands, 6 managers)
and the `rename --keep-old` path (151-line script for a rare operation): no further features there.

Recommended roadmap order (vs the order suggested in docs/handoff.md:63-65): (0) review fixes
ARC-01/03/12; (1) `cb::route` (ARC-02, S) and versioning (ARC-11, S) — prerequisites that make every
next item cheaper and safe across machines; (2) repeatable flags (M); (3) aliases + hidden (S+S);
(4) `self plugins install` then sync (S/M) — the multi-machine goal; (5) inherited flags (M–L, the
most invasive, least demanded); (6) `--choices-from` timeout; (7) zsh completion test in CI
(installing zsh on the CI runner does not violate rule 1, which is about runtime).
