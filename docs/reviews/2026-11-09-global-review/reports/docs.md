# docs — documentation accuracy + static review of the AI guide

## Scope and method

- Read: AGENTS.md (+ CLAUDE.md, GEMINI.md, .github/copilot-instructions.md), README.md,
  docs/{architecture,conventions,plugin-authoring,testing,roadmap,handoff}.md,
  docs/decisions/README.md + 0001-0010, 0014 in full, 0011/0013 by grep, plugins/README.md,
  templates/ai-guide.md, main.sh, lib/*.sh (all but install.sh/deps.sh bodies: headers + greps),
  builtin/self/new, guide, deps (_common, install), file headers of init.sh / lib/install.sh / lib/deps.sh.
- Sandbox `mksandbox.sh docs tt --init`: generated the guide (default, `--no-commands`, with a
  request, with `rename core:system sys` + an extension, with another `XDG_CONFIG_HOME`), ran
  the guide's worked example over an existing command, a nested-heredoc paste in `bash -i`,
  `self new` with a renamed official plugin, `requires` failure, `$0` in `cmd.sh`, ignored
  directory names, DSL error format, non-executable `cmd`, `bash -x` / `SHELLOPTS=xtrace`,
  `tt self --help` and sub-helps vs README, `init.sh` without a name (exit 2: matches).
- Read-only git/gh: `git branch -a`, `git log`, `gh pr list --state all`, `gh run list`.
- Verified as exact (no finding): the `requires` message and exit 1 (`✗ 'tt dd x' needs
  'cbx', not installed` / `  Install: tt self deps install`, `--help` still works), the
  exit-code rows 0/1/2, config directives, plugin states, completion protocol text, `ui::`
  table, DSL tables and name regexes of plugin-authoring.md, README "Built-in commands" vs
  every `self` help, `self deps install` asking for a manager when none is configured
  (0014), `self update` reminder, 442 tests = baseline.
- NOT covered: zsh (not installed), GitHub Markdown rendering, macOS, deep review of
  docs/testing.md recipes and of decisions 0011-0013 bodies, `self rename` / uninstall prose
  (other reviewers own the behaviour).
- Note: this report was rewritten after /tmp was wiped; lib/ line numbers were recomputed
  with `grep -n` on the real files (no new experiments).

## Grade

- **Exactness (README/docs vs code): B.** Almost every quoted message, option, default, table
  and help text matches the code. The drift is in secondary places (architecture tables,
  README partial copies, the unstated directory-name rule): DOC-09, DOC-10, DOC-11.
- **Contradictions / decision records: B-.** Three records (0001, 0008, 0010) describe rules
  that later decisions changed, without "amended by" marks; README duplicates the reference
  verbatim (DOC-07, DOC-11).
- **Newcomer test: C+.** AGENTS.md is a very good entry point and the wrap-up procedure is
  followable, but there is no "sync with main" step, no public/internal boundary, nothing on
  `$0`, sharing code, debugging or versioning (DOC-05, DOC-08, DOC-13).
- **handoff / roadmap: B.** Accurate at wrap-up time (442 tests, PR list, next step = this
  review) but stale by construction once the wrap-up PR merges; the Accepted list has no
  order (DOC-08, DOC-16).
- **AI guide, static: C.** Well organised, complete, placeholders always filled, sensible
  size (~7k tokens), good ask-first and safety rules. But its paste format and step 1 have
  two traps that can destroy or execute user code (DOC-01, DOC-02), it misleads with renamed
  plugins (DOC-03), and it withholds facts it asks the AI to use (DOC-04, DOC-06).

## Findings

### DOC-01 Guide paste format breaks when a file contains its own `EOF` line: the rest runs in the user's shell
- Severity: major   - Status: VERIFIED
- Aspect: AI guide (static)   - Location: templates/ai-guide.md:102-112 (format), :206-211 (worked example)
- Evidence: the guide mandates `cat > '<abs path>' <<'EOF'` for every file, with no rule on the
  delimiter. A `cmd.sh` that prints a usage text or writes a config with its own heredoc
  (`cat <<EOF ... EOF`, very common in generated Bash) ends the outer heredoc early.
  Sandbox, paste fed to an interactive bash (`bash -i < paste.sh`):
  ```text
  $ cat > '<root>/plugins/demo/usage/cmd.sh' <<'EOF'
  cat <<EOF
  Usage: tt demo usage
  EOF
  echo "LEAKED: this line ran in the user's shell, not written to cmd.sh"
  EOF
  -- output --
  LEAKED: this line ran in the user's shell, not written to cmd.sh
  bash: EOF: command not found
  -- cmd.sh now contains --
  cat <<EOF
  Usage: tt demo usage
  ```
- Impact: every user of `self guide` whose AI writes a file with an inner heredoc: the file
  is truncated silently and the remaining lines of the plugin code are **executed in the
  interactive shell** (with the user's cwd and variables; `rm`, `exit`, `cd` included). Weak
  models copy the template literally; the 3 guide evaluations did not hit it by chance.
- Fix: in *Format of the files*, use a delimiter that cannot appear in code, e.g.
  `<<'CB_EOF'` (a name generated Bash code never uses) in the template, the worked example and
  decision 0010, plus one rule: "never put a line equal to the delimiter in the content".
  Add a test that the worked example's delimiter is not `EOF`. Alternative: `printf '%s\n'`
  blocks (unreadable, rejected). — Cost: XS
- Decision: 0010 ("blocks ready to paste (`cat > '<abs path>' <<'EOF'`)") should be amended.

### DOC-02 Guide never says "stop if `self new` fails": a refused `self new` is followed by blocks that overwrite the existing command
- Severity: major   - Status: VERIFIED
- Aspect: AI guide (static)   - Location: templates/ai-guide.md:70-97, :123-124; builtin/self/new/cmd.sh:41; builtin/self/guide/cmd.sh:35-37
- Evidence: the guide's only protection is "Never overwrite an existing command. If the
  requested path already exists (see *Existing commands*)..." (ai-guide.md:123). With
  `--no-commands` that section only says "Not shared by the user. Ask them whether the
  command (or its plugin) already exists." — which contradicts "If the request is already
  clear, do not ask anything" (ai-guide.md:64). `self new` refuses an existing command, but
  nothing tells the user to stop. Sandbox: an existing `tt test hello` (cmd.sh =
  `echo "MY ORIGINAL CODE"`), then the bash blocks of the guide's own worked example pasted
  (as the owner does, several at once):
  ```text
  ✗ 'tt test hello' already has an executable: plugins/test/hello/cmd.sh
  Hello, world!
  HELLO, ALICE!
  -- cmd.sh now --
  msg="Hello, ${ARG_NAME:-world}!"   (original code lost; the parent plugins/test/flags.sh
                                      is rewritten too, against ai-guide.md:81)
  ```
- Impact: loss of a user's hand-written command (no git in `plugins/` by default) whenever
  the AI does not know the name exists: `--no-commands`, a command created after the guide
  was generated, a plugin cloned later, a weak model not checking the list.
- Fix: (1) in *The step-by-step guide*, step 1: "tell the user: if this prints a line
  starting with ✗, stop and send it to me (the next steps would overwrite files)"; (2) make
  step 1 a guard the next blocks depend on: the guide tells the AI to put `self new` and
  the first file of the new command in **one** block chained with `&&`
  (`tt self new test hello -a "..." && cat > '...' <<'CB_EOF'`), so a refusal (exit 1) writes
  nothing; later blocks repeat a cheap guard such as
  `grep -q 'TODO: describe' '<flags.sh>' && cat > ...` only if the owner wants belt and braces. (3) In
  `--no-commands` mode, say explicitly that asking about existing names is the one
  exception to "do not ask anything". Add one evaluation request "a command that already
  exists" to docs/testing.md. — Cost: S
- Decision: 0010 (worked example executed by the tests) — keep; extend the test with a
  re-run that must not overwrite.

### DOC-03 With a renamed official plugin, the guide's own advice makes the AI shadow it (`self new` takes directory names, the guide shows exposed names)
- Severity: major   - Status: VERIFIED
- Aspect: AI guide / plugin-authoring   - Location: templates/ai-guide.md:125-131; docs/plugin-authoring.md:32-34; README.md:215-217; builtin/self/new/cmd.sh:16,107,110; builtin/self/guide/cmd.sh:50
- Evidence: config `rename core:system sys` (documented feature). The guide lists the plugin by
  its exposed name, and tells the AI "To add a command to an official plugin ..., use
  `tt self new system disk`":
  ```text
  ### Plugin `sys` (id `core:system`, active)
  - `tt sys` (group, `core/system/`): System information and tools
  - `tt sys info` (command, `core/system/info/`): ...
  $ tt self new sys net            # what an AI does with the names it was shown
  ✓ Command 'tt sys net' created
    + plugins/sys/ ...
  $ tt sys info
  ✗ unknown subcommand 'info'                      (the official commands are gone)
  ! 'sys': user:sys shadows core:system → ...
  ! user:+system extends core:system, which is shadowed: it is inactive too
  $ tt self new system disk        # the directory name works, but its hint is wrong:
  ✓ Command 'tt system disk' created (added to the official plugin 'system', in plugins/+system/)
  › Try: tt system disk --help   →  ✗ unknown command 'system'  Did you mean: sys?
  ```
- Impact: exactly the error the guide forbids ("would **shadow** it, and all its commands
  ... would disappear"), reached by following the guide, for any user who renamed an
  official plugin. Every later official command of that plugin is hidden too.
- Fix: code (owner of `self new`): resolve the first word through the exposed names
  (`_CB_PLUGIN_ID`) so `self new sys net` extends `core:system`, and print the exposed path
  in the success/Try lines. Docs: until then, state in plugin-authoring.md (Layout) and the
  guide that `self new` takes **directory names** (the part after `core:` in the id). Add a
  test: renamed plugin + `self new <exposed> x` must not create `plugins/<exposed>/`. — Cost: S
- Decision: 0013 (extensions follow renames: "renamed with it") — keep; `self new` must follow it too.

### DOC-04 Files outside the command directories: no usable absolute path for the config dir, `~/.config/<name>` is wrong under `XDG_CONFIG_HOME`, no `mkdir -p`
- Severity: minor   - Status: VERIFIED
- Aspect: AI guide / plugin-authoring   - Location: templates/ai-guide.md:76-77, :111, :148-151; docs/plugin-authoring.md:245; main.sh:26
- Evidence: the guide requires "Always use the absolute path" in `cat > '<path>'` (single
  quotes) but only gives the config dir as `~/.config/tt` (ai-guide.md:149) and the
  reference says `CB_CONFIG_DIR` = `~/.config/<name>`; the code is
  `CB_CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/$CB_NAME` (main.sh:26). The Setup table has
  no config-dir row. Sandbox:
  ```text
  $ cat > '~/.config/tt/notes.conf' <<'X' ...      # the guide's format + the path it gives
  bash: line 1: ~/.config/tt/notes.conf: No such file or directory
  $ XDG_CONFIG_HOME=$SB/xdg tt self guide | grep '\.config'
  149:  a file under `$CB_CONFIG_DIR` (that is `~/.config/tt`), ...      (real dir: $SB/xdg/tt)
  $ tt self new bk save; cat > '<root>/plugins/bk/_lib/common.sh' <<'X' ...
  bash: line 1: <root>/plugins/bk/_lib/common.sh: No such file or directory
  ```
  Also: "always use the paths that `self new` prints" (ai-guide.md:76-77) cannot be followed
  by an AI that never sees the output; it must predict `plugins/+<p>/...` itself.
- Impact: settings files (a case the guide itself requires, :148) and shared helpers fail
  to be written; a model that "fixes" it with `mkdir -p '~/...'` creates a literal `~`
  directory in the cwd. Loud failure, but a broken first experience.
- Fix: add Setup rows "Config directory | `<absolute CB_CONFIG_DIR>`" (new placeholder
  `__CB_CONFIG_DIR__`); rule: "a file outside the directories created by `self new`
  (`_lib/`, a settings file) gets `mkdir -p '<dir>'` first"; replace "use the paths that
  `self new` prints" by the rule that computes them (`plugins/+<plugin>/`, `+<group>` for
  each official group listed in *Existing commands*). Reference: `CB_CONFIG_DIR` =
  "`$XDG_CONFIG_HOME/<name>`, default `~/.config/<name>`". — Cost: XS

### DOC-05 `$0` inside `cmd.sh` is `lib/run.sh`, and sharing code through `_lib/` is not shown
- Severity: minor   - Status: VERIFIED
- Aspect: newcomer / plugin contract docs   - Location: docs/plugin-authoring.md:18, :233-248; lib/router.sh:100; lib/run.sh:1-8
- Evidence: a `cmd.sh` printing `$0` and `${BASH_SOURCE[0]}`:
  ```text
  0=<root>/lib/run.sh SRC=<root>/plugins/dd/x/cmd.sh
  ```
  plugin-authoring.md says `_lib/` holds "helpers, assets…" but never shows
  `source "$CB_PLUGIN_ROOT/_lib/x.sh"`; `$0` is not mentioned anywhere (grep `\$0` in
  README.md, docs/plugin-authoring.md, templates/ai-guide.md: no hit).
- Impact: the classic Bash idioms `$(dirname "$0")/../_lib/x.sh` or `usage: $(basename "$0")`
  (frequent in AI-written code and in scripts users migrate) silently point into `lib/`.
- Fix: in "What the command receives": "`$0` is the framework launcher: use `CB_COMMAND`
  for messages and `CB_COMMAND_DIR` / `CB_PLUGIN_ROOT` for paths", plus a 2-line
  "Sharing code" example (`source "$CB_PLUGIN_ROOT/_lib/common.sh"`). Mention it in the
  guide's Rules. — Cost: XS

### DOC-06 The guide asks the AI to decide what is "standard" and which package names to use, without giving the distribution or the configured package manager
- Severity: minor   - Status: VERIFIED
- Aspect: AI guide (static)   - Location: templates/ai-guide.md:28, :31-32, :52-55, :140-141, :157-162; builtin/self/guide/cmd.sh:69-71
- Evidence: Setup only has `System | Linux 6.18.54.1-microsoft-standard-WSL2 (WSL: Linux
  under Windows)` (`uname -sr`); the sandbox config contains `package-manager apt`, absent
  from the guide. Contradictory instructions: "do not assume anything else about it (other
  tools, distribution...). When something else matters, ask." (:31-32) vs "which external
  tools it relies on (the system is known: see *Setup*, do not ask about it)" (:52-53), and
  "do not check standard tools of the system (`ps`, `awk`, `df`...). Declare every other
  tool" (:157-158). Whether `git`, `curl`, `ss`, `lsof`, `rsync`, `ip` are "standard" depends
  on the distribution; `requires ss` would make apt look for a package `ss` (it is
  `iproute2`). `git` is guaranteed (install requirement, README.md:14) but the guide does
  not say so.
- Impact: inconsistent `requires` lines between models; wrong package names → `self deps
  install` then "still not found" (documented limitation, roadmap.md:87-88).
- Fix: add Setup rows "Package managers | apt" (from `_CB_PMS`) and "Distribution" (from
  `/etc/os-release` `PRETTY_NAME`, read with `while read`, no dependency); state "always
  available: Bash, POSIX tools, git"; one sentence: "with apt, give `--apt <package>` when
  the package name differs (e.g. `requires ss --apt iproute2`)". Remove "the system is
  known ... do not ask". — Cost: S

### DOC-07 Decision records outdated in fact but still plain "Accepted"
- Severity: minor   - Status: VERIFIED
- Aspect: decisions vs code   - Location: docs/decisions/0010-ai-guide-built-from-the-docs.md; 0008-require-bash-4-2.md; 0001-one-directory-per-command.md; docs/decisions/README.md
- Evidence:
  - 0010: "the guide now makes a user plugin with another name the default and `--core`
    only an explained alternative" — current guide: "use `self new system disk`: it creates
    an **extension** ... Never use `self new --core` for that" (ai-guide.md:128-131, since
    0013 / PR #12). 0010's signature `mu self guide [-o file] [--no-commands]` lacks the
    `[request]` argument (guide/flags.sh:8). Index: "Accepted", no amendment.
  - 0008: "The framework already relies on ... `declare -g` / `declare -gA` (global arrays
    declared from sourced files and functions)" and "`declare -g` ... allowed" — 0011
    found that `declare -gA` inside functions does not work on 4.2 and moved the arrays to
    top level; conventions.md:12-13 still lists `declare -g` under "Allowed" (then :20
    forbids it in functions). 0008 is not marked "amended by 0011".
  - 0001: "Directories starting with `_` or `.` are ignored" — `+` directories now carry
    meaning (0013); only 0003 is annotated "(extensions added by 0013)".
- Impact: the README of decisions tells agents to "Read the relevant record before
  proposing to change a structural choice": these three give a wrong picture of the
  current rules (an agent could restore `--core` advice or `declare -g` in a function).
- Fix: add "Amended by 0013" (0001, 0010) and "Amended by 0011" (0008) in the records and
  the index; fix 0010's signature; conventions.md:12: "`declare -g` at top level only".
  — Cost: XS

### DOC-08 Session start: AGENTS.md never says to sync with `main`; the handoff snapshot is stale by construction
- Severity: minor   - Status: VERIFIED
- Aspect: AGENTS.md procedure / handoff   - Location: AGENTS.md:126-134 ("Starting a session"), :100-108; docs/handoff.md:7, :44-47
- Evidence:
  ```text
  $ git branch -a        → * docs/wrap-up-features (merged), fix/ui-symbols, main
  $ git log --oneline -1 main            → 284d249 Merge pull request #13 ...
  $ gh pr list --state all               → 14 docs: session wrap-up ... MERGED
  $ gh run list                          → success  Merge pull request #14 ... main push
  ```
  The checkout sits on the merged wrap-up branch; local `main` is behind GitHub's `main`.
  The handoff (written inside PR #14) says "`main` = `284d249`" and "Branch
  `docs/wrap-up-features`: this wrap-up" — both false once the PR is merged. "Starting a
  session" only says `git status --short` and `git log --oneline -10`, which show the
  merged branch, not `main`; nothing says `git fetch` / switch to an up-to-date `main`
  before branching.
- Impact: the next agent may branch from a stale `main` or keep committing on a merged
  branch (conflicts, a PR re-containing merged commits).
- Fix: "Starting a session" step 0: `git fetch --prune && git switch main && git pull
  --ff-only` (read-only for the user's files; ask before deleting merged branches). In the
  handoff template, write the state "as of the wrap-up PR" (`main` = `<sha>` + this PR),
  not as a fact. — Cost: XS

### DOC-09 The command-directory name rule is not in the plugin contract; a `my.tools/` plugin is silently ignored
- Severity: minor   - Status: VERIFIED
- Aspect: plugin-authoring exactness   - Location: docs/plugin-authoring.md:25-26; README.md:93-94; lib/util.sh:16; docs/architecture.md:34
- Evidence: plugin-authoring only says "Directories whose name starts with `_` or `.` are
  ignored"; the rule `^[a-zA-Z0-9][a-zA-Z0-9_-]*$` is only in architecture.md. Sandbox:
  `plugins/my.tools/flags.sh` → `tt my.tools` gives `✗ unknown command 'my.tools'`, and
  `tt self doctor | grep -c my.tools` → `0`. Names are also stated three different ways:
  guide "lower case letters, digits and `-`" (ai-guide.md:132, stricter: safe), `self new`
  "letters, digits, - and _; not first" (new/cmd.sh:7), code (util.sh:16; arg names allow
  `_`, spec.sh:224; flags do not, spec.sh:161).
- Impact: a user (or a migrated script dir) with a dot, space or accent in the name sees
  nothing and gets no diagnostic.
- Fix: one line in plugin-authoring Layout: "Command directory names:
  `^[a-zA-Z0-9][a-zA-Z0-9_-]*$`; other names are ignored (reported by `self doctor`)" and
  a doctor warning for ignored non-`_`/`.` directories (code reviewers). — Cost: XS (doc) / S (doctor)

### DOC-10 Small inaccuracies in docs/architecture.md
- Severity: minor   - Status: VERIFIED
- Aspect: architecture exactness   - Location: docs/architecture.md:24, :65, :68, :100, :111, :149-150, :89-102
- Evidence (doc vs code):
  - :24 `exec bash lib/run.sh <dir>/cmd.sh "$@"` — code passes the positionals only:
    `exec "$BASH" "$CB_ROOT/lib/run.sh" "$exe" "${_CB_POS[@]}"` (router.sh:100).
  - :111 DSL errors "reported as `file:line : message`" — actual:
    `✗ <root>/plugins/okp/flags.sh:2: invalid flag name 'Bad' (usage: ...)` (spec.sh:122).
  - :68 `lib/config.sh` "(`disable`, `rename`)" — also `package-manager` and
    `cb::config_set_package_managers` (config.sh:43-49, :95-109); :149-150 says only
    `self plugins enable|disable` rewrite the file atomically and follow a symlink —
    `self deps managers add|remove` do too (config.sh:106-107).
  - :100 `_CB_PM_ALL` "filled by `cb::config_load`" — it is a constant (config.sh:13).
  - :65 `lib/core.sh` "Sources all libs" — not `install.sh` / `deps.sh` (core.sh:9).
  - Globals table: `_CB_CHOICES_LIST`, `_CB_DIR`, `_CB_DISPLAY`, `_CB_OPT_SHIFT`,
    `_CB_TV_FLAG` are used in lib/ but absent (grep of every `_CB_*` of lib/ against the doc).
- Impact: low; each one misleads a contributor reading the reference table first.
- Fix: correct the 6 lines; add a doc check "every `_CB_[A-Z_]*` of lib/ appears in
  architecture.md" (same style as the lib/ files check). — Cost: XS

### DOC-11 README drifts from plugin-authoring.md (duplicated text, partial copies)
- Severity: minor   - Status: VERIFIED
- Aspect: README vs reference   - Location: README.md:22-23, :96, :215-230; docs/plugin-authoring.md:5, :27-28, :32-47; lib/install.sh:35-40
- Evidence: README.md:96 "`cmd` is any executable (Python, binary…)" omits the executable
  bit stated in plugin-authoring.md:28; sandbox: a `plugins/py/cmd` without `+x` → `tt py`
  prints the help (`tt py — py / Usage`) instead of running it (doctor does report it,
  doctor/cmd.sh:120). README.md:22-23 says init "offers to enable completion" but the rc
  block also edits PATH (install.sh:35 "PATH + completion"; sandbox ~/.bashrc contains
  `case ":$PATH:" in ... export PATH=...`). README.md:215-230 is a verbatim copy of
  plugin-authoring.md:32-47 (16 lines); the doc tests only check that names are
  *mentioned*, not that copies agree. plugin-authoring.md:5 itself asks to "keep both in sync".
- Impact: drift is already visible; each new feature must be written twice.
- Fix: README keeps a short tour + links (layout, one `flags.sh`, one `cmd.sh`, the self
  table) and drops the duplicated tables/paragraphs; or add a test that the README extension
  block equals the reference block. — Cost: S

### DOC-12 Guide structure: the reference's `##` sections are siblings of the guide's own sections; small inaccuracies
- Severity: minor   - Status: VERIFIED
- Aspect: AI guide (static)   - Location: builtin/self/guide/cmd.sh:19-31, :36, :47; templates/ai-guide.md:5-6, :21, :156, :247-250
- Evidence: generated headings (`grep -n '^#' guide`): `## Reference: writing a command` is
  immediately followed by `## Layout`, `## \`flags.sh\` DSL`, `## What the command receives`,
  `## \`ui::\` helpers` — same level as `## How to answer`; the "Reference" section is empty.
  *Setup* is referenced 4 times (:52, :140, testing.md) but is a sentence ("Setup of this
  user:"), not a heading. With `--no-commands` the guide still says "It contains ... their
  existing commands" (:5-6) and prints "Commands already installed for this user, with their
  directory..." then "Not shared by the user". Extensions are headed by an invented name:
  "### Extension `+sys` (id `user:+system`, `plugins/+system/`, ...)" (`+sys` is neither a
  command nor a directory). "Tab completion included: nothing to reload" (:156) is false
  when completion was declined at install ("Enable 'tt' completion in ~/.bashrc? [Y/n]").
  Size: 27.3 KB / 4,139 words (~7k tokens), fine. No unfilled `__CB_*__` in any mode.
- Impact: weak models rely on headings to find rules; small contradictions cost answers.
- Fix: demote reference headings by one level when embedding (prefix `#` in `reference()`),
  make "Setup" a `###` heading, drop the intro paragraph in `--no-commands` mode, head
  extensions by their directory (`plugins/+system/`), qualify the completion claim. — Cost: XS

### DOC-13 Missing contributor/author docs: public vs internal, exit codes, debugging, versioning
- Severity: suggestion   - Status: VERIFIED (absence + behaviour checked)
- Aspect: newcomer test   - Location: docs/plugin-authoring.md (whole), README.md, docs/conventions.md:44-50
- Evidence:
  - Public vs internal: plugin-authoring.md never says whether a plugin may
    `source "$CB_ROOT/lib/core.sh"` or call `cb::*` (the `self` commands do, architecture.md:155);
    `cb::` appears 0 times in it. `_CB_` is "never in plugins" only in architecture.md:81.
    The `__complete` protocol and exit code 3 are not said to be internal or stable.
  - Exit codes for plugin authors/scripts (2 = usage error from the parser, 1 = missing
    required tool, 3 = invalid flags.sh) are only in architecture.md.
  - Debugging: `bash -x ~/.local/bin/tt dbg` traces 0 lines of `cmd.sh` (new process via
    `exec "$BASH" lib/run.sh`), `SHELLOPTS=xtrace tt dbg` traces it (sandbox: 0 vs 1 match);
    neither is documented (`grep -i 'debug\|set -x'`: no hit).
  - Versioning: `tt --version` → `✗ unknown option '--version'`; no CHANGELOG; the plugin
    contract is declared a public API (plugin-authoring.md:3-5) but contract additions
    (`requires`, `ui::select`, `+` extensions) are only traceable through git log.
  - plugin-authoring.md:203 "official plugins (`core/`) and `self` never need anything beyond
    Bash and POSIX tools" — `self update` needs git (update/cmd.sh:3; also README.md:14).
- Impact: authors reach for internals that may change, or lose time debugging.
- Fix: a short "Stability" paragraph in plugin-authoring (public: DSL, `FLAG_*`/`ARG_*`/`CB_*`,
  `ui::`/`UI_*`, layout, exit codes; internal: `cb::`, `_CB_*`, `lib/`, `__complete`); a
  "Debugging" line (`set -x` in `cmd.sh`, or `SHELLOPTS=xtrace mu ...`, `mu self doctor`);
  a CHANGELOG.md limited to contract changes (or a dated "Contract changes" list in
  plugin-authoring). — Cost: S

### DOC-14 WSL is flagged in the guide but nothing says what it implies
- Severity: suggestion   - Status: VERIFIED
- Aspect: AI guide (static)   - Location: templates/ai-guide.md:28; builtin/self/guide/cmd.sh:69-70
- Evidence: the only WSL mention in the generated guide is the Setup row
  `Linux 6.18.54.1-microsoft-standard-WSL2 (WSL: Linux under Windows)`
  (`grep -i 'wsl\|clip\|xdg-open\|notify'`: 1 hit). The owner's machine is WSL2.
- Impact: AIs write `xdg-open`, `notify-send`, `xclip` (absent or not working on stock WSL)
  or forget `/mnt/c/...` and `*.exe` interop; the user discovers it at run time.
- Fix: when WSL is detected, append to the System row or Rules: "browser / files: `wslview`
  or `explorer.exe`; clipboard: `clip.exe`; Windows drives under `/mnt/<letter>/`". — Cost: XS

### DOC-15 AGENTS.md wrap-up table: one row is not indented like the others
- Severity: suggestion   - Status: VERIFIED (source) / NOT VERIFIED (GitHub rendering, no renderer here)
- Aspect: AGENTS.md   - Location: AGENTS.md:117
- Evidence: `grep -n '^| How an AI' AGENTS.md` → line 117 starts at column 0 while the table
  lives in list item 2 (3-space indent, e.g. line 118 `   | A coding rule ...`). In
  CommonMark a non-indented line ends the list item, so the table is likely split in two.
- Fix: indent line 117 by 3 spaces. — Cost: XS

### DOC-16 Roadmap "Accepted" list is unordered and omits known follow-ups
- Severity: suggestion   - Status: VERIFIED
- Aspect: roadmap   - Location: docs/roadmap.md:53-65, :92-93; docs/handoff.md:63-71
- Evidence: 7 items, no priority; only the handoff suggests an order for three of them. The
  "Did you mean" for a mistyped subcommand is a Known limitation (roadmap.md:92-93) and an
  open question (handoff.md:70-71) but not an Accepted item. The zsh completion test is both
  Accepted and "Not covered yet" (testing.md:112-113) although completion.zsh ships to users.
- Fix: order Accepted as: review fixes (this report's batch) → zsh completion test (shipped
  untested code) → `--choices-from` timeout (Tab freeze) → repeatable flags → opt-in
  inherited flags → aliases + hidden commands → `self plugins install` (security-sensitive,
  last). Add the "Did you mean" item. — Cost: XS

## What is good and must be kept

- The guide's reference is **generated** from plugin-authoring.md (markers), its worked
  example and the complete `flags.sh` example are **executed** by the tests, and doc checks
  fail on any undocumented DSL keyword, `CB_*`, `ui::`, `self` command, config directive or
  lib file (decision 0010, testing.md). Keep and extend (DOC-10 globals check).
- Quoted messages are exact (requires message, refusals of `self new`), and the README
  "Built-in commands" table matches every `self` help text.
- AGENTS.md: short, rule-first, one place for all tools (pointer files are correct), a
  concrete wrap-up checklist; the handoff "Owner preferences" section is precious context.
- Decision records exist for every structural choice, with rejected alternatives; the index
  is complete (the doc check enforces it).
- Guide rules that work: ask-first with a default per question, English texts in files,
  never `sudo <name>`, `requires` instead of `command -v || die`, `ui::select` instead of
  `fzf`, extension paths for official plugins, no `--default 0` on bools, edge case in *Try it*.

## Risks for the future

- Every feature is written 3 times (plugin-authoring, README, guide rules): the doc checks
  verify that names are *mentioned*, not that statements are *true*. Drift will grow (DOC-11).
- The guide is evaluated on happy paths (new names, clean requests). The dangerous cases
  are adversarial: existing names, nested heredocs, renamed plugins, `--no-commands`,
  XDG paths. Add them to the evaluation set of docs/testing.md and, where possible, to
  executed tests (re-run of the worked example must not overwrite; delimiter check).
- Snapshot docs (handoff "Current state") describe the wrap-up PR as if it were `main`.

## Open questions for the owner

1. Change the paste delimiter of the guide from `EOF` to a unique one (`CB_EOF` or similar)
   and amend decision 0010? **Recommendation: yes** (DOC-01, XS, removes a code-execution trap).
2. Should step 1 of every guide answer be a guard ("if this prints ✗, stop"), or should the
   AI chain `self new ... &&` with the first file block? **Recommendation: both** — a sentence
   for the user and `&&` in the block (DOC-02).
3. Should `self new` accept the exposed name of a renamed official plugin? **Recommendation:
   yes** (code fix, other reviewers), and say in the docs that it takes directory names until then (DOC-03).
4. Add to the guide's Setup: absolute config dir, configured package managers, distribution
   (`PRETTY_NAME`)? It reveals a bit more to the external AI. **Recommendation: yes for the
   three**, with `--no-commands` unchanged (DOC-04, DOC-06).
5. Shrink README to a tour + links and keep plugin-authoring.md as the single reference?
   **Recommendation: yes** (DOC-11); keep the README tables that users scan (self commands).
6. Add a CHANGELOG limited to plugin-contract changes? **Recommendation: yes**, short and
   dated; no version number needed while `self update` is `git pull` (DOC-13).
