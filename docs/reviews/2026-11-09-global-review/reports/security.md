# security — security of the whole project

## Threat model

### Assets
- **A1** the user's interactive shell and rc files (`~/.bashrc`, `~/.zshrc`): whatever lands there runs at every shell start.
- **A2** the framework config and generated files under `$CB_CONFIG_DIR` (the completion scripts are sourced by the rc).
- **A3** the home directory and the user's own plugins (`plugins/`, often not under git).
- **A4** sudo rights (package installs by `self deps`).
- **A5** secrets that plugins keep under `$CB_CONFIG_DIR`, receive as flags, or ask for at a prompt.
- **A6** what leaves the machine (`self guide` sent to an external AI service).

### Actors
| Actor | Trust | Entry points |
|---|---|---|
| The user | trusted | everything |
| Authors of the official plugins and the user's own plugins | trusted: plugin code is code (decisions 0001, 0005, 0006) | `flags.sh` sourced in the framework process, `cmd.sh` exec'ed |
| Third-party plugins cloned into `plugins/` | trusted **by design** from the moment they are cloned, which users do not expect (SEC-03) | `flags.sh` at Tab / `--help` / `self *`, `cmd.sh`, `requires` packages, about texts copied into the guide |
| The AI chat whose answers the user pastes | untrusted text that ends up in an interactive shell | the paste format of `templates/ai-guide.md` (SEC-01, SEC-02) |
| A malicious or compromised git remote | untrusted until merged | `self update`: fetch, log display, pull (SEC-04) |
| Other local users | untrusted | world-readable files, `ps` / `/proc` (SEC-05, SEC-09, SEC-13) |
| Content of the current directory at Tab time | untrusted | `--choices-from` snippets run in the cwd (SEC-10) |
| The process environment | as trusted as the user's session | internal `_CB_*` variables, `CDPATH` (SEC-06, SEC-11) |

### Trust boundaries
B1 AI text → interactive shell (the paste) · B2 git remote → checkout (`self update`) · B3 cwd → snippets run at Tab time · B4 user → root (`sudo` in `self deps`) · B5 the user's files → other local users (file modes, `ps`) · B6 machine → external AI (the guide) · B7 environment → framework.

### Accepted by design (not reported as bugs)
- Plugin code runs with the user's rights; `flags.sh` is sourced by the framework itself (0001/0005). A plugin can do anything the user can. Only how *visible* that is to users is in scope (SEC-03).
- `--choices-from` is `eval`ed at each Tab, in the cwd (0006).
- `_CB_TTY` is an internal override of the prompt input (0009). Reviewed in SEC-06.
- The guide is sent to an external AI, with the list of commands included by default (0010).
- Extensions can replace official subcommands, and doctor reports it (0013).
- `self deps` runs sudo package-manager commands after one confirmation. A pacman update is `-Syu` (0014, known limitation in the roadmap).

### In scope
Any way for an actor **other than plugin code** to run code, change files or gain privileges. Any place where the trust given to plugin code is not obvious to users. Secrets and file modes. What leaves the machine.

## Scope and method
- **Read:** all of `lib/*.sh`, `main.sh`, `builtin/self/{new,update,deps/*,guide,completion}`, part of `doctor` / `rename` / `init.sh` (validation, `CB_ROOT`), `templates/completion.{bash,zsh}`, the format and rules of `templates/ai-guide.md`, decisions 0005/0006/0009/0010/0013/0014, the roadmap, the handoff, and targeted greps of the README and docs.
- **Experiments** (sandbox `mksandbox.sh security tt --init`; Bash 5.2.37, git 2.47.3, umask 022; each output is quoted in its finding):
  - which entry points source a cloned plugin's `flags.sh`;
  - a guide-format AI answer pasted into `bash -i`;
  - 17 payloads through `self new -a` → `cb::dq`, with `patsub_replacement` on and off;
  - config modes after each kind of rewrite;
  - `_CB_NO_DYNAMIC` set in the environment;
  - the completion script for a link named `x$(touch${IFS}PWNED3)`;
  - Tab on a command line containing `$(...)` and backquotes;
  - what `self guide --no-commands` contains, and the mode of the `-o` file;
  - `self update` against a local bare remote (escape-sequence subject, modified `flags.sh`);
  - `self deps install` with fake `sudo`/`apt-get` and an Enter-only answer;
  - a symlinked mode-600 rc through `self rename`;
  - `ui::ask` under a pty;
  - Tab with git snippets inside a repository that sets `core.fsmonitor`;
  - an exported `CDPATH`;
  - doctor with a hostile example;
  - a plugin named `self`.
- **Hypotheses refuted (no finding):**
  - `eval` of `--choices-from` (lib/spec.sh:43): only `flags.sh` content reaches it. Typed words are never evaluated: the bash adapter splits the line with `read -ra` and passes the words as arguments. Tab on `tt $(touch PWNED4) \`touch PWNED5\` sys` created nothing.
  - `eval` of package-manager commands (builtin/self/deps/_common.sh:40): managers come from the fixed list (lib/config.sh:44), names are validated by `requires` (lib/spec.sh:139, :147) and quoted again with `printf %q` (lib/deps.sh:58). Even a `flags.sh` that writes `_CB_R_PKG` directly cannot inject (and it runs code anyway).
  - `cb::dq` (lib/util.sh:109) through `self new -a`: 16 of 17 payloads round-trip exactly (`"`, `$(...)`, backquotes, `\`, a trailing `\`, `\\`, a newline, `'`, `%s %d`, `&` / `\&`, `${HOME}`, `$((1+1))`, `!!`, a tab, 70 kB, `a\"b\$c`), and nothing ran. Only a trailing newline is dropped (command substitution, cosmetic). Same result with `patsub_replacement` off and on.
  - doctor's example check (builtin/self/doctor/cmd.sh:18): `xargs printf` evaluates nothing. `example 'exa $(touch PWNED7) \`touch PWNED8\` ; touch PWNED9'` created no file; doctor reported "unexpected argument '$(touch'". (An example written in *double* quotes is expanded when `flags.sh` is sourced: that is plugin code.)
  - Names: plugin and command directories that fail `cb::valid_name` are ignored (lib/plugins.sh:27, :69). `rename` values are validated (lib/config.sh:37). Root names are validated by init.sh:39 and builtin/self/rename/cmd.sh:17. A plugin named `self` is refused and reported ("'self' is reserved"). The only gap is SEC-08.
  - `FLAG_*` / `ARG_*` inherited from the environment are cleared before exec (lib/parse.sh:162). `CB_ROOT`, `CB_NAME` and `CB_CONFIG_DIR` are recomputed by main.sh.
  - rc rewrite: follows symlinks, keeps the mode, refuses a block without its end marker (lib/install.sh:56-90).
  - git hooks in `self update`: a remote never sends hooks; only a local actor (that is, plugin code) can plant one.
  - sudo: the `EUID` check is correct (lib/deps.sh:59), brew never runs with sudo, and there is no `-y`.
- **Not covered:**
  - zsh template: static review only (no zsh installed); nothing found besides SEC-08.
  - macOS `stat -f`, Bash 4.2.
  - ACLs (no `setfacl`), and a second local user (visibility in `ps`).
  - Real brew / dnf behaviour: documented behaviour only.
  - `BASH_ENV` / `SHELLOPTS` / `GLOBIGNORE`: static review only. They are set by the user, and I found no security impact; `GLOBIGNORE` enables `dotglob`, but names starting with `.` fail `cb::valid_name`.
- The sandbox was lost in a machine reboot after the experiments; all outputs below were captured before that.

## Grade
| Aspect | Grade | Comment |
|---|---|---|
| Injection hygiene (quoting, eval, escaping, names) | A- | `cb::dq` passed fuzzing, package names are quoted again with `%q`, names are validated everywhere, and the Tab line is never evaluated. One gap: the root name in the completion templates (SEC-08). |
| AI-guide paste flow | D | The default answer format can silently truncate a file and run the rest of it in the user's interactive shell (SEC-01). After a refused `self new`, it overwrites existing code without asking (SEC-02). This is the documented way to create commands with a chat AI. |
| Visibility of the plugin trust model | C | Cloning a plugin means its code runs at the next `tt <Tab>` or `tt --help`. The README recommends `git clone … plugins/` without saying so (SEC-03), and nothing warns that snippets run in the cwd (SEC-10). |
| Update channel | C+ | There is a confirmation, but the only review offered is the remote's raw commit subjects, the default is yes, and the pulled code runs inside the update itself (SEC-04). |
| Privileged actions (sudo) | B | Commands are shown, a missing terminal means no, the EUID check is correct, and there is no `-y`. Weak spots: Enter runs sudo, and any package name containing `/` is accepted (SEC-07). |
| Secrets and file modes | C | Rewrites widen the config mode (SEC-05). Temp files use predictable names and the umask (SEC-13). The reference example passes a token as a flag, and there is no prompt that hides input (SEC-09). |
| Environment robustness | B- | Inherited `FLAG_*`/`ARG_*` are cleared, but internal `_CB_*` inputs are honoured from the environment (SEC-06), and `CDPATH` is not neutralised (SEC-11). |
| Privacy of the guide | B | There is an opt-out (`--no-commands`), but what is always sent is not stated (SEC-12). |

## Findings

### SEC-01 AI-guide paste format: a line `EOF` inside a generated file truncates it and runs the rest in the user's interactive shell
- Severity: major   - Status: VERIFIED
- Aspect: AI guide / paste format   - Location: templates/ai-guide.md:102-112 (format), templates/ai-guide.md:184-210 (worked example)
- Evidence: I wrote an answer that follows the guide's format exactly, for a `cmd.sh` that creates its default settings file with its own heredoc (the guide itself asks for settings files under `$CB_CONFIG_DIR`, templates/ai-guide.md:149-151). I then pasted it into an interactive bash (`bash -i < answer.txt`):
  ```
  cat > '<root>/plugins/backup/cmd.sh' <<'EOF'
  conf=$CB_CONFIG_DIR/backup.conf
  if [[ ! -f $conf ]]; then
    mkdir -p "$CB_CONFIG_DIR"
    cat > "$conf" <<EOF        <- inner heredoc, very common in scripts
  dest=$HOME/backups
  EOF                          <- ends the OUTER heredoc
    chmod 600 "$conf"          <- from here on: run as commands in the user's shell
  fi
  source "$conf"
  [[ -d $ARG_SOURCE ]] || { ui::error "not a directory: $ARG_SOURCE"; exit 1; }
  ...
  ```
  Actual output (trimmed):
  ```
  chmod: cannot access '': No such file or directory
  bash: syntax error near unexpected token `fi'
  bash: : No such file or directory
  bash: ui::error: command not found
  exit
  == shell exit status: 1          <- the user's terminal closes
  == resulting cmd.sh: 6 lines, ends at "dest=$HOME/backups" (silently truncated)
  ```
- Impact:
  - Any generated file that contains a line that is exactly `EOF` is silently truncated. Such lines are frequent in AI-written Bash: usage texts, default config files, `psql` input, `ssh host <<EOF`.
  - Every line after it runs **in the user's interactive shell**, with the user's rights and none of the script's variables. `exit` closes the terminal (shown above). `set -e`, `set -u`, `cd` and `trap` change the session. `rm`, `mv` and `sudo` lines run with empty variables, on paths nobody intended.
  - The owner pastes several blocks at once (handoff), so the whole answer runs before anything can be noticed.
  - The tests do not catch it: the worked example contains no heredoc.
- Fix: use a delimiter that cannot plausibly occur in a file, e.g. `<<'CB_FILE_END'`, in the format, the worked example and the extraction test. Add a rule that the delimiter line must never appear alone inside the content. Make the extraction test fail if a block's content contains its own delimiter line. — Cost: XS. Stronger alternative: `mu self write <path>`, which reads stdin and checks a length or checksum to detect a truncated paste. — Cost: M
- Decision: 0010 chose ready-to-paste `cat > … <<'EOF'` blocks. That choice can stay; only the delimiter must change.

### SEC-02 AI-guide paste: when `self new` is refused, the following blocks still overwrite the existing command
- Severity: major   - Status: VERIFIED
- Aspect: AI guide / data loss   - Location: templates/ai-guide.md:102-112, :123-124; builtin/self/new/cmd.sh:38-41
- Evidence: the user already has a command `notes` with its own `cmd.sh`. The answer is `tt self new notes -a "Take notes"` followed by two `cat > '<root>/plugins/notes/...' <<'EOF'` blocks, pasted at once:
  ```
  $ tt self new notes -a "Take notes"
  ✗ 'tt notes' already has an executable: plugins/notes/cmd.sh
  == notes/cmd.sh now:
  echo generated              <- was "# 200 lines of my own code / echo my-notes"
  ```
- Impact:
  - `self new` refuses precisely to protect existing commands ("a refused run must leave existing commands untouched", builtin/self/new/cmd.sh:38). But the blocks that follow it in the answer do not depend on it, so the user's code is replaced without a prompt.
  - This happens whenever the AI does not know the command exists:
    - a guide made with `--no-commands`;
    - a guide older than the command;
    - an AI that ignores templates/ai-guide.md:123 (small models do).
  - User plugins are often not under git (`--git` is opt-in), so the code is lost.
- Fix: make the files depend on `self new` in the answer format: `mu self new <path> -a "..." && { cat > … <<'CB_FILE_END' … CB_FILE_END … }` (heredocs work inside `{ }`). A refusal then writes nothing. Test: paste the extracted answer twice and check that the second paste changes nothing. — Cost: S
- Decision: 0010 (format). Keep the format, chain it.

### SEC-03 Installing a third-party plugin runs its code at the next Tab or `--help`, and nothing says so
- Severity: major   - Status: VERIFIED
- Aspect: trust boundary / documentation   - Location: lib/spec.sh:99 (`source flags.sh`), called from lib/help.sh:104, lib/complete.sh:65, builtin/self/guide/cmd.sh:54, lib/deps.sh:93, builtin/self/update/cmd.sh:76-79, doctor; README.md:212, plugins/README.md:8 (recommend `git clone … plugins/…` without a warning)
- Evidence: a fixture `plugins/cloned/flags.sh` appends a line to a marker file each time it runs. Number of runs per entry point:
  ```
  tt                       -> 1      tt self doctor               -> 3
  tt --help                -> 1      tt self guide                -> 1
  tt __complete -- ''      -> 1      tt self guide --no-commands  -> 0
  tt __complete -- cl      -> 1      tt self deps                 -> 1
  tt system info           -> 0      tt self update --check       -> 1
  ```
  `tt __complete -- ''` is what the shell runs for `tt <Tab>`.
- Impact:
  - `git clone <url> plugins/x` gives that repository code execution as the user at the first `tt <Tab>` or `tt --help`. That is before the user ever runs or reads the plugin.
  - The code runs again in `self update`, `doctor`, `guide` and `deps`, and the same applies after every update of the plugin (SEC-04).
  - This is accepted by design, but users reasonably believe that a plugin they do not use is inert. The only hint is "it is read at each Tab" (templates/ai-guide.md:152).
- Fix: document the trust model in README.md (next to `git clone`), plugins/README.md and docs/plugin-authoring.md. Suggested wording: "a plugin is code: its `flags.sh` runs at every Tab on `mu`, at `mu --help` and in `self doctor/guide/deps/update`. Only install plugins whose code you have read or whose author you trust." The planned `self plugins install <git-url>` (roadmap) should say exactly that, show the URL, the commit and the file list, ask with **default no**, and run no plugin code before the answer. — Cost: XS (docs) / S (with the command)
- Decision: none to change.

### SEC-04 `self update`: pulled plugin code runs inside the update itself; the only review offered is the remote's raw commit subjects, default yes
- Severity: minor   - Status: VERIFIED
- Aspect: update / malicious remote   - Location: builtin/self/update/cmd.sh:44, :51, :76-79
- Evidence: `plugins/remote` is cloned from a bare repository. A new commit changes its `flags.sh` (it appends to a marker) and has the subject `Fix typo\e[1A\e[2K\r    abc1234 Fix typo in README`. Output of `_CB_TTY=<file "y"> tt self update`, through `cat -v`:
  ```
  plugin remote
  › 1 new commit(s) on origin/main:
      bb1c49d Fix typo^[[1A^[[2K^M    abc1234 Fix typo in README     <- ESC sequences reach the terminal
  ? Update? [Y/n] ✓ updated
  == marker after update:
  pulled flags.sh ran inside: tt self update                          <- new code ran at once
  ```
- Impact:
  - Answering Enter executes the plugin's new code immediately (through `cb::deps_collect` at the end of the update), not only at the next Tab.
  - The only thing shown before the question is up to 20 subjects, written by the remote and printed raw. Escape sequences can rewrite the terminal (cursor moves, line clears, OSC), even with `--check`, which pulls nothing.
  - This is not an escalation (a remote that can push already gets code execution at the next Tab), but it removes the user's last chance to notice.
- Fix:
  1. Filter control characters out of the subjects (`git log --format='%h %s' … | LC_ALL=C tr -d '\000-\010\013-\037\177'`) — XS.
  2. Show `git diff --stat HEAD..@{u}` and the remote URL.
  3. For plugins, default to no or say "the new code runs immediately".
  4. Collect deps only for the reminder, or skip it when nothing was updated.
  — Cost: S
- Decision: none (rule 5 is met).

### SEC-05 Config rewrites reset the file mode to the umask (a `chmod 600` config becomes 644)
- Severity: minor   - Status: VERIFIED
- Aspect: file permissions   - Location: lib/config.sh:91, lib/config.sh:107
- Evidence (umask 0022):
  ```
  before: 600
  after self plugins disable: 644
  after self plugins enable: 644
  after self deps managers add: 644
  ```
  For reference, the config directory is 755 and `completion.bash` is 644.
- Impact:
  - `cb::config_set_disabled` and `cb::config_set_package_managers` write `$f.tmp` with the umask, then `mv` it over the config (or over its symlink target, e.g. a dotfiles repository).
  - This silently widens a mode the user chose.
  - `cb::rc_replace` does preserve the mode (lib/install.sh:88), so the two rewrite paths are inconsistent.
  - Minor, because the config holds no secret by itself.
- Fix: one shared helper `cb::rewrite_file`:
  1. `mktemp "$f.XXXXXX"` (created 0600, unpredictable name);
  2. `chmod --reference` (fallback `stat -f %Lp`) before writing the content;
  3. `mv`.
  Use it in lib/config.sh and lib/install.sh, with a test that mode 600 survives disable / enable / `managers add`. — Cost: S
- Decision: none.

### SEC-06 Internal variables are honoured from the environment: `_CB_NO_DYNAMIC=1` disables every `--strict` check; `_CB_TTY=<file>` answers every prompt
- Severity: minor   - Status: VERIFIED
- Aspect: environment inheritance   - Location: lib/spec.sh:58 (`${_CB_NO_DYNAMIC:-}` is never initialised, only set in doctor's subshell, builtin/self/doctor/cmd.sh:46); lib/ui.sh:35, :52, :72 (`_CB_TTY`)
- Evidence: the plugin declares `arg env "Environment" --choices-from "printf '%s\\n' dev staging" --strict`:
  ```
  $ tt deploy prod
  ✗ <env>: invalid value 'prod' (choices: dev, staging)
  $ _CB_NO_DYNAMIC=1 tt deploy prod
  deploying to prod
  $ _CB_NO_DYNAMIC=1 tt deploy '../../../etc'
  deploying to ../../../etc
  ```
  `_CB_TTY` pointing to a file containing an empty line runs `sudo apt-get …` without a keypress (SEC-07).
- Impact:
  - `--strict` is the documented run-time validation of a dynamic value. A plugin may rely on it as an allow-list, e.g. `source "$CB_CONFIG_DIR/envs/$ARG_ENV"`.
  - Any process that sets the user's environment (a wrapper, CI, `sudo` with `env_keep`) silently disables it.
  - Minor, because controlling the environment is usually game over already. The fix is trivial.
- Fix: initialise every internal input at load time (`_CB_NO_DYNAMIC=` in lib/spec.sh; doctor sets it after loading). Honour `_CB_TTY` only when a second marker set by tests/run.sh is present. Add a test that `_CB_NO_DYNAMIC=1` does not bypass `--strict`. — Cost: XS
- Decision: amend 0009 to say that `_CB_TTY` is honoured in production, and either why that is acceptable or how it is restricted.

### SEC-07 `self deps install/update`: the sudo commands run on Enter (default yes), and `requires` accepts any package containing `/`
- Severity: minor   - Status: VERIFIED (default yes, accepted names) / NOT VERIFIED (what brew and dnf do with such names: neither is installed)
- Aspect: sudo / dependencies   - Location: builtin/self/deps/_common.sh:37 (`ui::confirm "Run them?" y`), lib/spec.sh:147 (package pattern), lib/deps.sh:55-74
- Evidence: fake `sudo`/`apt-get` are first in PATH. A third-party plugin declares `requires zzfoo --apt zzfoo-pkg --brew evil/tap/formula --dnf x/local.rpm`, and the user only presses Enter:
  ```
  Commands to run:
    sudo apt-get update
    sudo apt-get install zzfoo-pkg
  ? Run them? [Y/n] $ sudo apt-get update
  [fake sudo] apt-get update
  [fake sudo] apt-get install zzfoo-pkg
  == with package-manager brew:
    brew install evil/tap/formula
  ```
- Impact:
  - Rule 5 is met: the commands are shown, and no terminal means no.
  - But the most privileged action of the project defaults to yes, and its package names come from third-party `flags.sh`.
  - The `/` lets a plugin name a brew `user/tap/formula`. Per brew's documentation, that taps and installs from an arbitrary GitHub repository. dnf and zypper may read `x/local.rpm` as a local file relative to the cwd. Both are NOT VERIFIED.
  - Not an escalation for a malicious plugin, but it contradicts what the "restrictive" design of 0014 suggests.
- Fix: `ui::confirm "Run them?" n`. Flag names that are not plain package names ("from tap evil/tap: third-party repository"), or reject `/` except for explicitly allowed brew taps. — Cost: XS-S
- Decision: 0014. Keep the design; add this to its consequences.

### SEC-08 The root name is not escaped in the completion templates: a hand-made link with an odd name injects code into the generated script
- Severity: minor   - Status: VERIFIED
- Aspect: names reaching shell code   - Location: lib/complete.sh:161-164 (only `__CB_FUNC__` is sanitised; the replacement `$CB_NAME` is unquoted), templates/completion.bash:14, :21, templates/completion.zsh
- Evidence: a link named `x$(touch${IFS}PWNED3)` points to main.sh. I ran `"$odd" self completion bash > f; bash -c 'source ./f'`:
  ```
  14:  mapfile -t out < <(x$(touch${IFS}PWNED3) __complete -- "${words[@]:1}" 2>/dev/null)
  21:complete -o default -F _cb_complete_x__touch__IFS_PWNED3_ x$(touch${IFS}PWNED3)
  PWNED3     <- created when the script was sourced
  ```
- Impact:
  - init.sh and `self rename` validate the name, but main.sh accepts any link name.
  - `self completion` and `self update` (`cb::completion_install`) generate the script for that name as is.
  - It needs a link the user named oddly, hence minor.
  - The unquoted replacement would also turn `&` into the pattern under Bash 5.2 `patsub_replacement`.
- Fix: in `cb::completion_script` and `cb::completion_install`, refuse names that fail `cb::valid_root_name`, and quote the replacement. — Cost: XS
- Decision: none.

### SEC-09 Secrets: the reference example passes an access token as a flag, and `ui::ask` echoes what is typed
- Severity: minor   - Status: VERIFIED (echo) / NOT VERIFIED (visibility to a second local user: only one user available)
- Aspect: secrets   - Location: docs/plugin-authoring.md:105, :113-114, :129 (shipped in `self guide`); lib/ui.sh:52 (`read -r` without `-s`)
- Evidence: the reference `flags.sh` declares `flag token string "Access token" --required`, with examples `--token T`. Under a pty:
  ```
  $ printf 'hunter2\n' | script -qec "bash -c 'source lib/ui.sh; ui::ask \"Access token\" >/dev/null'" /dev/null
  hunter2                  <- echoed on the terminal (the answer itself went to /dev/null)
  ? Access token
  ```
- Impact:
  - The example that AIs and users copy puts a token on the command line. It ends up in `~/.bash_history`, in `--help` examples, and in `ps` / `/proc/<pid>/cmdline` (readable by other users on a default Linux). `FLAG_TOKEN` is also exported to every child process (0005).
  - The alternative, `ui::ask`, shows the secret on screen and in the scrollback. No helper reads input without echo.
  - The guide's rule "chmod 600 the settings file that holds a token" (templates/ai-guide.md:149-151) is right, but the reference example contradicts it.
- Fix: replace `--token` in the example and add a rule: never take a secret as a flag or argument. Add `ui::ask -s` (`read -rs`), a compatible extension of the contract (rule 2). Recommend `(umask 077; …)` instead of a `chmod` after writing. — Cost: S
- Decision: 0005. Keep it; document what it means for secrets.

### SEC-10 Dynamic choices run in the current directory at every Tab: a `git` snippet executes the hooks of an untrusted repository
- Severity: minor   - Status: VERIFIED
- Aspect: current directory at Tab time   - Location: lib/spec.sh:43; docs/plugin-authoring.md:186; builtin/self/new/cmd.sh:73 (template comment suggesting a git snippet)
- Evidence: a repository whose `.git/config` sets `core.fsmonitor = "touch …/PWNED6; false"` (as it would arrive in an archive or on a shared drive), with git 2.47.3:
  ```
  $ cd untrusted; tt2 __complete -- gitx br ''        # --choices-from "git branch --format=..." (documented example)
    -> git branch: nothing ran
  $ tt2 __complete -- gitx changed ''                 # --choices-from "git diff --name-only"
    -> PWNED6 exists
  ```
- Impact:
  - Tab inside a hostile directory, after a command whose snippet runs `git status`/`diff`, runs that directory's code.
  - This is git's behaviour (git-aware prompts have the same problem), and `safe.directory` does not protect files the user owns.
  - The framework's part: snippets run automatically in the cwd, and the docs never warn about it.
- Fix: one sentence in the reference and in the guide rules: "the snippet runs in the user's current directory at every Tab: avoid tools that execute project configuration (`git status`/`diff` → add `-c core.fsmonitor=false`; no `make`/`npm`/`direnv`)". — Cost: XS
- Decision: 0006. Keep it; add this to its consequences.

### SEC-11 An exported `CDPATH` breaks `main.sh`/`init.sh` invoked by a relative path (and could redirect `source`)
- Severity: minor   - Status: VERIFIED (breakage) / NOT VERIFIED (redirection, theoretical)
- Aspect: inherited environment   - Location: main.sh:17, :21; init.sh:21; lib/util.sh:7, :11
- Evidence: `CDPATH=$SB/cdp bash app/main.sh --help`, with `$SB/cdp/app/` existing:
  ```
  app/main.sh: line 29: <SB>/cdp/app
  <SB>/cdp/app/lib/core.sh: No such file or directory
  ```
  `cd` found `app` through `CDPATH` and printed the path, then `pwd` printed it again, so `CB_ROOT` is two lines.
- Impact:
  - Only with an exported `CDPATH` and an invocation such as `bash cmd-builder/init.sh`. The PATH link is absolute and not affected.
  - Whoever controls a `CDPATH` entry could create the matching `app<newline>…` tree and get their own `lib/core.sh` sourced. Very unlikely.
- Fix: `CDPATH= cd -P -- "$(dirname -- …)" && pwd`, or `unset CDPATH` at the top of main.sh and init.sh. — Cost: XS
- Decision: none.

### SEC-12 `self guide --no-commands` still sends the absolute install path (user name), kernel and Bash versions; `-o` writes 0644
- Severity: suggestion   - Status: VERIFIED
- Aspect: privacy of the guide   - Location: builtin/self/guide/cmd.sh:69-71, :86-88, :109
- Evidence: `tt self guide --no-commands` still contains:
  - 7 occurrences of the absolute install path;
  - `| System | Linux 6.18.54.1-microsoft-standard-WSL2 (WSL: Linux under Windows) |`;
  - `Bash version | 5.2.37(1)-release`.

  `-o out.md` produces a file with mode 644. By default, the guide includes every plugin's about text, and building it sources every `flags.sh` (SEC-03).
- Impact: 0010 presents `--no-commands` as the privacy switch. Users may believe that nothing personal is sent. The path (`/home/<user>/…`) is needed by the paste blocks, so this is mostly a documentation gap.
- Fix: state in `--help` and the README what the guide always contains. Optional: `--no-paths`, producing blocks with `~/…` paths. — Cost: XS
- Decision: 0010, wording only.

### SEC-13 Rewrites use predictable temp names created with the umask: the rc content is briefly world-readable, hard links and ACLs are lost
- Severity: suggestion   - Status: VERIFIED (mode kept, symlink followed, new inode) / NOT VERIFIED (ACLs: no setfacl; the race window)
- Aspect: rc and config rewrites   - Location: lib/install.sh:62-89 (`$real.cb-uninstall.tmp`), lib/config.sh:91, :107 (`$f.tmp`)
- Evidence: `~/.bashrc` is a symlink to `dotfiles/bashrc` (mode 600). After `tt self rename tt2`:
  - before: `inode 40907 -rw-------`; after: `inode 57205 -rw-------`;
  - the symlink is kept and both `tt2` markers are present.

  Statically, the temp file is written by `printf … >"$tmp"` (umask mode) and only then `chmod --reference`'d.
- Impact: rc files often hold exported tokens, and they are readable by others between the write and the chmod. A hard-linked rc file is split into two files, and ACLs/xattrs are dropped. A predictable name in a shared, writable directory can be raced (unlikely in `$HOME`).
- Fix: the same helper as SEC-05 (`mktemp` in the same directory, chmod before writing, then `mv`). — Cost: S (together with SEC-05)
- Decision: 0007. Unchanged; the replacement stays atomic.

## What is good and must be kept
- `cb::dq` (fuzzed, immune to `patsub_replacement`), and the `guide` `sub()` helper that avoids special `&`.
- Package-manager command lines: validated names, quoted again with `printf %q`, managers from a fixed list, no `-y`, brew without sudo, correct EUID check.
- The Tab line is never evaluated (`read -ra`, words passed as arguments), and `mapfile` avoids glob expansion of candidates.
- Names are validated everywhere; odd directories are ignored; `self` is reserved and the conflict reported.
- Prompts read `/dev/tty`, never stdin: piped input cannot answer a question, and no terminal means no.
- The rc rewrite is atomic, follows symlinks, keeps the mode, and refuses when the end marker is missing.
- Inherited `FLAG_*`/`ARG_*` are cleared before exec. `self guide -o` asks before overwriting. `--no-commands` exists.
- doctor checks examples with `xargs`, which evaluates nothing.

## Risks for the future
- `self plugins install <git-url>` (roadmap): the warning wording, default no, and no plugin code run before the answer (no doctor or deps collection on it).
- Other dependency sources (pip, npm, install scripts) would greatly widen the sudo / remote-code surface. Keep them restrictive: shown first, default no.
- Inherited flags, aliases and hidden commands mean more code paths that source `flags.sh`. Keep `flags.sh` free of side effects, and say so.
- About texts of third-party plugins are embedded in the guide sent to the AI. They can steer its answer, which the user then pastes (prompt injection combined with SEC-01). NOT VERIFIED.
- A timeout for `--choices-from`: kill the whole process group, or a slow snippet keeps running after Tab.

## Open questions for the owner
1. Change the guide's delimiter to `CB_FILE_END` and chain each answer as `self new … && { … }` (SEC-01, SEC-02)? **Recommended: yes**, XS-S, with an extraction test.
2. Default to no for `self deps` sudo commands, and for plugin updates in `self update` (SEC-04, SEC-07)? **Recommended: yes for `self deps`, and for plugins**; keep yes for the framework's own update.
3. Add `ui::ask -s` and replace `--token` in the reference example (SEC-09)? **Recommended: yes**. It is a compatible extension of the contract.
4. Restrict `_CB_TTY` to the test suite, and initialise `_CB_NO_DYNAMIC` (SEC-06)? **Recommended: yes**, XS. Amend decision 0009.
5. Document the plugin trust model in the README now, without waiting for `self plugins install` (SEC-03)? **Recommended: yes**, with the wording proposed in SEC-03.
