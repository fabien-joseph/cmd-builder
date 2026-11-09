# portability — portability of the whole code base (lib/, main.sh, init.sh, builtin/, core/, templates/, tests/run.sh, CI)

## Scope and method

- Read in full: main.sh, init.sh, every file of lib/, templates/completion.{bash,zsh}, core/system/info/cmd.sh,
  builtin/self/doctor/cmd.sh; targeted reads/greps of the other builtin/self commands, tests/run.sh,
  .github/workflows/tests.yml, README.md, docs/conventions.md, decisions 0004/0008/0011.
- Inventory by grep of every external command and every Bash feature newer than 4.0 (table below).
- CI cross-check (read-only `gh`): run 42524920126 (merge of PR #14), per-job logs.
- Experiments in sandboxes (Bash 5.2.x, Debian 13 on WSL2, glibc 2.41, GNU coreutils, dash as /bin/sh):
  CRLF files; a Git clone with `core.autocrlf=true`; `sh`/`dash`/`bash --posix`/Bash-as-`sh`/`POSIXLY_CORRECT`;
  the full flow (init, run, completion harness, `self new`, `self doctor`, `self rename`) from a directory named
  `sbx-por x&[y]'z*é$v`; rc blocks generated for HOME containing `"` and a backtick; locales `C`, `C.UTF-8`,
  `en_US.UTF-8` and `tr_TR.UTF-8` (the last two compiled with `localedef` from the system sources into a scratch
  dir, used through `LOCPATH`); sort vs glob order; `patsub_replacement`; a `chmod` shim without `--reference`
  (BusyBox/BSD-like); exported `CDPATH`; a login Bash without `~/.bash_profile`.
- NOT covered / NOT VERIFIED: real macOS, real BusyBox/Alpine, Bash 4.2/4.1 and 3.2 at runtime (no binaries, no
  docker daemon), zsh (not installed), drvfs `/mnt/c` (forbidden to write there: static only).
- Note: the sandboxes were lost in a machine reboot after the experiments; all outputs below were captured before.

## Grade

- **Bash version discipline: A.** Only 4.0-4.2 features are used (table below), consistently with decision 0008;
  the CI really runs Bash 4.2.53 and 441/442 checks pass there (the missing one is a docs check, see Risks).
- **External tools: B.** Short, conservative list, almost all POSIX; one BSD-only fallback that misbehaves on
  BusyBox (POR-07). No GNU-only flag in tests/run.sh (it passes on macOS CI).
- **Paths with special characters: B.** Everything is quoted carefully: install, run, completion, self new,
  doctor and rename all work from `…/sbx-por x&[y]'z*é$v/`. Only the generated rc block is unsafe (POR-04).
- **Locales: D.** Name validation and `FLAG_*` upper-casing follow the user's locale: Turkish users lose every
  name containing `i`, accented names pass validation in `en_US.UTF-8` then vanish at export (POR-05). Sort and
  glob orders agree within a locale (no inconsistency between root help, sub-help and extensions).
- **Shells (sh/dash/posix/zsh): B.** The guard works for dash/sh=dash/zsh/old Bash; POSIX-mode Bash slips through
  (POR-03). zsh adapter reviewed statically only, no defect proven.
- **macOS: C (static).** CI covers Homebrew Bash for running commands, not the interactive integration: login
  shells never read the `~/.bashrc` block (POR-06).
- **WSL / Windows line endings: C.** No `.gitattributes` (POR-01); CRLF user files give garbled or misleading
  errors and doctor is blind to them (POR-02).
- **`patsub_replacement` (Bash 5.2): A.** `cb::dq` round-trips `&` and `\`; the only variable replacements are
  `$func` (sanitized) and `$CB_NAME` (validated); see Risks.

### Inventory — external commands used by the framework (not tests)

| Command / option | Where | Status |
|---|---|---|
| `sed 's/…/…/g'`, `sed -E` | lib/util.sh:105, update/cmd.sh:44, core/system/info/cmd.sh:4 | POSIX (`-E` in POSIX 2024); GNU, BSD, BusyBox ≥1.22 OK |
| `sort`, `sort -u` | lib/plugins.sh:57, lib/deps.sh:105, lib/util.sh:48 | POSIX; locale-dependent order (same as glob order in a given locale, verified C / en_US) |
| `grep -qF` | lib/install.sh:30,33,64 | POSIX |
| `cut -f 1`, `head -n 1` | doctor/cmd.sh:126, 47 | POSIX |
| `xargs printf '%s\n'` (quote splitting) | doctor/cmd.sh:18 | POSIX; BusyBox needs FEATURE_XARGS_SUPPORT_QUOTES (Alpine: enabled, NOT VERIFIED) |
| `readlink --`, `dirname --` | main.sh:17-18, lib/util.sh:7-11, lib/install.sh:95, init.sh:80 | readlink: POSIX 2024, everywhere; `--` OK (getopt) |
| `ln -sfn` | init.sh:126, rename/cmd.sh:75 | `-n` not POSIX but GNU/BSD(macOS)/BusyBox OK |
| `chmod --reference` → `stat -f %Lp` | lib/install.sh:88 | GNU-only → BSD-only fallback; broken on BusyBox (POR-07) |
| `cmp -s`, `mv -f --`, `rm -f --`, `rmdir --`, `mkdir -p`, `cat` | rename, install, config | POSIX |
| `uname -s/-r/-n/-sr` | deps.sh:15, guide/cmd.sh:69-71, system info | POSIX |
| `hostname` (fallback `uname -n`) | system info:1 | not POSIX, fallback OK |
| `uptime` parsed with `sed -E 's/.*up +([^,]*),.*/\1/'` | system info:4 | not POSIX; procps-ng, macOS, BusyBox, toybox formats all yield the first component ("3 days", "2:03", "5 min"), hours dropped when > 1 day; empty if `uptime` is absent (slim containers). Static |
| `git -C`, `rev-parse --abbrev-ref @{u}`, `rev-list --count`, `log --oneline` | update/cmd.sh, new/cmd.sh:101, doctor:53 | git ≥ 1.8.5 |
| `script -qec` / `script -q /dev/null` | CI only | util-linux vs BSD handled in tests.yml |
| `env` (shebang `#!/usr/bin/env bash`) | all entry points | POSIX path on Linux/macOS/BusyBox |

### Inventory — Bash features newer than 4.0

| Feature | Introduced | Used? |
|---|---|---|
| `mapfile -t` (no `-d`) | 4.0 | yes (many); `mapfile -d` (4.4): no |
| `${v^^}` / `${v,,}` | 4.0 | lib/parse.sh:164,168, lib/ui.sh:39 (locale issue: POR-05) |
| `read -t 0.1` (fractional) | 4.0 | lib/ui.sh:101 |
| `\|&` | 4.0 | tests/run.sh:364,373 only |
| associative arrays | 4.0 | yes; `declare -gA` at top level only (decision 0011 workaround) |
| `exec {fd}<…`, `{fd}<&-` | 4.1 | lib/ui.sh:72,93,105,116 |
| `declare -g` | 4.2 | lib/config.sh, plugins.sh, spec.sh, parse.sh, deps.sh |
| negative subscript in a *reference* `${a[-1]}` | 4.2 (assignment/unset with negative subscript: 4.3) | lib/spec.sh:240, lib/complete.sh:147 — reference only, OK |
| `${!prefix@}` | 2.x | lib/parse.sh:162 |
| `local -n`, `declare -n` (4.3), `${v@Q}` (4.4), `wait -n` (4.3), `[[ -v ]]` (4.2; `-v a[k]` 4.3), `printf -v a[k]` (4.1/4.2), `;;&` (4.0), `&>>` (4.0), negative substring length (4.2), `globasciiranges` (4.3, default on 5.0), `patsub_replacement` (5.2) | — | not used |
(Versions from Bash CHANGES as remembered; the 4.2 rows are confirmed by the green Bash 4.2 CI job.)

CI cross-check (run 42524920126): Linux Bash 5.3.9 **442 passed**, macOS Homebrew Bash 5.3.20 **442 passed**,
Bash 4.2.53 (musl) **441 passed**, Bash 4.1 guard message OK.

## Findings

### POR-05 Name validation and `FLAG_*`/`ARG_*` upper-casing depend on the user's locale: under `tr_TR.UTF-8` every name containing an `i` is rejected; under `en_US.UTF-8` accented names pass validation, then fail at export
- Severity: major   - Status: VERIFIED (Bash 5.2, glibc 2.41; locales compiled from the system sources with `localedef`, used through `LOCPATH`)
- Aspect: locales   - Location: regex ranges lib/util.sh:16, lib/install.sh:16, lib/config.sh:15, lib/spec.sh:139, 147, 161, 192, 224; case conversion lib/parse.sh:164, 168
- Evidence:
  ```
  $ LC_ALL=tr_TR.UTF-8 bash -c 'for c in {a..z}; do [[ $c =~ ^[a-z]$ ]] || printf "%s " "$c"; done'
  i
  $ LC_ALL=tr_TR.UTF-8 tt system info --short            # the official plugin
  ✗ unknown subcommand 'info'
  $ LC_ALL=tr_TR.UTF-8 tt self plugins          -> ✗ unknown subcommand 'plugins'
  $ LC_ALL=tr_TR.UTF-8 tt self completion bash  -> ✗ unknown subcommand 'completion'
  $ LC_ALL=tr_TR.UTF-8 tt self guide            -> ✗ unknown subcommand 'guide'
  $ LC_ALL=tr_TR.UTF-8 tt self new x            -> ✗ APP/builtin/self/new/flags.sh:8: invalid flag name 'git' (usage: ...)
  $ LC_ALL=tr_TR.UTF-8 bash init.sh cli         -> ✗ invalid name 'cli' (lower case letters, digits, - and _, starting with a letter)
  # user plugin: flag title / flag dir / arg file
  $ LC_ALL=tr_TR.UTF-8 tt tr show --title T --dir D f.txt
  ✗ .../plugins/tr/show/flags.sh:2: invalid flag name 'title' (usage: ...)
  $ LC_ALL=C tt tr show --title T --dir D f.txt
  title=[T] dir=[D] file=[f.txt]
  # and the upper-casing alone would also break the contract:
  $ LC_ALL=tr_TR.UTF-8 bash -c 'n=title; v=FLAG_${n^^}; echo "$v"; export "$v=x"'
  FLAG_TİTLE
  bash: 1. satır: export: `FLAG_TİTLE=x': geçerli bir tanımlayıcı değil
  # en_US.UTF-8: in a regex [a-z] matches "é" and "ı"; C.UTF-8 does not
  $ LC_ALL=C.UTF-8 tt acc --café x
  ✗ .../plugins/acc/flags.sh:2: invalid flag name 'café' (usage: ...)
  $ LC_ALL=en_US.UTF-8 tt acc --café x      # cmd.sh: echo "[${FLAG_CAFE:-unset}]"; env | grep -c "^FLAG_"
  .../app/lib/parse.sh: line 165: export: `FLAG_CAFÉ=x': not a valid identifier
  [unset]
  0                                          <- the command still runs, without its flag
  ```
  `=~` uses the C library regex, whose ranges follow the locale (POSIX leaves ranges undefined outside the POSIX locale); `globasciiranges` does not apply to `=~`. `${v^^}` follows LC_CTYPE (Turkish `i` → `İ`).
- Impact: every Turkish (or Azerbaijani) locale user: the official `system info`, `self plugins|completion|guide|new`, the root name `cli`, and every plugin/command/flag/argument with an `i` are unusable, with messages blaming the name. In common UTF-8 locales, accented names are accepted or rejected depending on the locale of the moment (cron, ssh with `LANG=C`), and an accepted accented flag never reaches cmd.sh.
- Fix: (1) replace ranges by explicit lists, e.g. `_CB_AZ=abcdefghijklmnopqrstuvwxyz` and `[[ $1 =~ ^[${_CB_AZ}0-9][${_CB_AZ}0-9_-]*$ ]]` — checked under tr_TR: `title info git cli 9x` all match; (2) upper-case with `local LC_ALL=C` in cb::export_values — checked on 5.2: inside the function `${v^^}` = `TITLE`, the caller's locale is restored after return (NOT VERIFIED on 4.2) — or an ASCII lookup string; (3) CI step running a few checks under `tr_TR.UTF-8` (`localedef` on the Ubuntu runner); (4) one line in docs/conventions.md: "no `[a-z]` ranges in `=~`, no `^^`/`,,` on names without `LC_ALL=C`". — Cost: S
- Decision: none covers locales (docs never mention them).

### POR-01 No `.gitattributes`: a clone made with Git for Windows defaults is unusable from WSL
- Severity: major   - Status: VERIFIED
- Aspect: WSL / line endings   - Location: repository root (no `.gitattributes`), main.sh:1, init.sh:1
- Evidence: Git for Windows installs with `core.autocrlf=true` by default; simulated with a read-only clone:
  ```
  $ git clone -q -c core.autocrlf=true /home/fabien/repo/fabien/cmd-builder "$SB/winclone"; cd "$SB/winclone"
  $ head -1 main.sh | od -c | head -2
  0000000   #   !   /   u   s   r   /   b   i   n   /   e   n   v       b
  0000020   a   s   h  \r  \n
  $ ./init.sh tt2
  env: ‘bash\r’: No such file or directory
  $ bash init.sh tt2
  init.sh: line 12: $'\r': command not found
  init.sh: line 13: syntax error near unexpected token `$'in\r''
  ```
- Impact: a Windows/WSL user cloning with Git for Windows (e.g. into `C:\…`, used from `/mnt/c`) cannot install, and the message says nothing about line endings. Same for user plugin repos.
- Fix: `.gitattributes` with `* text=auto eol=lf` (git then checks out LF whatever `core.autocrlf`); optionally `self new --git` writes it into new plugin repos; a WSL note in README. — Cost: XS
- Decision: none.

### POR-06 macOS Bash users: the rc block goes to `~/.bashrc`, which login shells (Terminal.app, iTerm2) do not read; if the stock Bash 3.2 reads it, the completion script fails
- Severity: major   - Status: mechanism VERIFIED on Linux; macOS NOT VERIFIED
- Aspect: macOS shells   - Location: init.sh:151-156, lib/install.sh:22 (only `~/.bashrc`/`~/.zshrc`), templates/completion.bash:14 (`mapfile`, 4.0), README.md:14
- Evidence: sandbox HOME with the block in `~/.bashrc`, no `~/.bash_profile`/`~/.profile` (the macOS default):
  ```
  $ grep -c 'cmd-builder: tt' ~/.bashrc
  2                                       <- begin + end markers
  $ env -i HOME="$HOME" PATH=/usr/bin:/bin TERM=dumb bash -l -i -c 'type tt; complete -p tt'
  bash: type: tt: not found
  bash: complete: tt: no completion specification
  ```
  A login Bash reads `~/.bash_profile`, `~/.bash_login` or `~/.profile`, never `~/.bashrc`; Linux skeleton files source `~/.bashrc`, macOS ships none and its terminals start login shells. Static: a user keeping `/bin/bash` 3.2 interactively (`brew install bash` does not change it) whose `~/.bash_profile` sources `~/.bashrc` runs completion.bash in 3.2 → `mapfile: command not found` at every Tab. README only says "on macOS: brew install bash".
- Impact: macOS users whose shell is Bash: after "All set! Open a new terminal", the command is not in PATH and there is no completion (or it errors). The macOS CI job cannot see it.
- Fix: on Darwin, or when `~/.bash_profile` exists without a reference to `.bashrc`, also write the block to `~/.bash_profile` (or offer to add `[ -f ~/.bashrc ] && . ~/.bashrc`), and include it in cb::rc_files for uninstall/rename; start templates/completion.bash with `[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || return 0`; one README line. — Cost: S
- Decision: 0004/0008 unchanged (the interactive shell is another program, possibly older).

### POR-02 CRLF in a user's `flags.sh` / `cmd.sh` / config: silent value corruption, garbled or misleading errors, and `self doctor` sees nothing
- Severity: minor   - Status: VERIFIED
- Aspect: WSL / Windows editors   - Location: lib/spec.sh:93-103, lib/config.sh:21-24, builtin/self/doctor/cmd.sh:100-128
- Evidence (files written with `\r\n`):
  ```
  # flags.sh: flag name -n string "Who" --default world\r ; cmd.sh: echo "hello $FLAG_NAME"\r
  $ tt win hello | cat -A
  hello world^M^M$                      <- FLAG_NAME silently is "world\r"
  # flags.sh: arg file "A file" --optional\r
  $ tt win two x | cat -A
  ✗ .../plugins/win/two/flags.sh:2: unknown option '--optional^M' for arg file$
  # as a terminal renders it (CR moves the cursor back):
  ' for arg filee-1000/-home-fabien-...flags.sh:2: unknown option '--optional
  # cmd.sh: if [[ -n $ARG_FILE ]]; then\r ... fi\r
  $ tt win two x
  .../plugins/win/two/cmd.sh: line 4: syntax error: unexpected end of file
  # config: disable core:system\r / package-manager apt\r
  $ tt --help | grep system
    system  System information and tools        <- still enabled
  $ tt self doctor
    ✗ config line 1: expected 'disable <core|user>:<plugin>'      <- the line looks exactly like that
    ✗ config line 2: expected 'package-manager <apt|dnf|pacman|zypper|apk|brew>'
  # with only the CRLF flags.sh + cmd.sh:
  $ tt self doctor | tail -1
  ✓ Everything is fine.
  ```
- Impact: WSL users editing from a Windows editor (new files default to CRLF there): invisible `\r` in values, unreadable errors, a config line rejected although it looks right, and the diagnostic says everything is fine.
- Fix: `line=${line%$'\r'}` in cb::config_load and both config rewriters; doctor warns for each `flags.sh`/`cmd.sh`/config containing `$'\r'` (pure Bash `[[ $(<"$f") == *$'\r'* ]]`) with the portable fix `sed 's/\r$//' f > f.new && mv f.new f`; optionally cb::spec_load dies with "Windows (CRLF) line endings" before sourcing. — Cost: S

### POR-03 POSIX-mode Bash passes the version guard, then dies on `` `cb::realpath': not a valid identifier `` (`sh init.sh` on Fedora/Arch/openSUSE, `POSIXLY_CORRECT`)
- Severity: minor   - Status: VERIFIED
- Aspect: shells / version guard   - Location: main.sh:6-12, init.sh:13-19, lib/run.sh:1-4, lib/util.sh:4
- Evidence (`$SB/shbash/sh` = symlink to /bin/bash, as `/bin/sh` on Fedora, RHEL, Arch, openSUSE):
  ```
  $ sh init.sh tt                          # Debian: dash -> guard OK
  cmd-builder requires Bash >= 4.2 (current: none).
  $ dash main.sh                           -> same guard message (OK)
  $ "$SB/shbash/sh" "$APP/init.sh" tt
  .../app/lib/util.sh: line 13: `cb::realpath': not a valid identifier
  $ bash --posix "$APP/main.sh" --help     -> same error
  $ POSIXLY_CORRECT=1 tt system info --short   -> same error (every command)
  ```
  POSIX mode forbids non-identifier function names; the guard only checks `BASH_VERSION`.
- Impact: `sh init.sh mu` where sh is Bash, and users exporting `POSIXLY_CORRECT` (also reaches lib/run.sh via `exec "$BASH"`): obscure message instead of the guard's.
- Fix: `set +o posix` right after the version `case` of main.sh and init.sh, and as the first line of lib/run.sh. Prototyped in a sandbox copy: Bash-as-`sh main.sh --help` prints the root help, `POSIXLY_CORRECT=1 tf system info --short` works, dash still gets the guard message. Add tests. — Cost: XS
- Decision: 0004/0008 not questioned; this makes the guard's promise true.

### POR-04 The rc block writes `$HOME` / `$XDG_CONFIG_HOME` unescaped inside double quotes: `$`, `"`, backtick or `\` break the user's shell startup
- Severity: minor   - Status: VERIFIED
- Aspect: special characters in paths   - Location: lib/install.sh:40-41 (cb::rc_block), via init.sh:146 and self rename
- Evidence: full flow from `$SCR/sbx-por x&[y]'z*é$v/` (app + HOME inside): install, `--help`, `system info`, completion harness (`[system]`), `self new demo hello` + run, `self doctor` ("Everything is fine"), `self rename tu` all OK; `bash -n ~/.bashrc` OK. But:
  ```
  $ grep -A2 '>>> cmd-builder: tu' ~/.bashrc
  case ":$PATH:" in *":$SCR/sbx-por x&[y]'z*é$v/home/.local/bin:"*) ;; *) export PATH="$SCR/sbx-por x&[y]'z*é$v/home/.local/bin:$PATH" ;; esac
  [ -f "$SCR/sbx-por x&[y]'z*é$v/home/.config/tu/completion.bash" ] && . "…/completion.bash"
  $ env -i HOME="$W/home" PATH=/usr/bin:/bin bash -c 'source ~/.bashrc; echo "PATH=$PATH"; type tu; complete -p tu'
  PATH=$SCR/sbx-por x&[y]'z*é/home/.local/bin:/usr/bin:/bin      <- "$v" expanded to nothing
  bash: line 1: type: tu: not found
  bash: line 1: complete: tu: no completion specification
  $ HOME='/home/a"b' → cb::rc_block tt bash > rcblk.txt; bash -n rcblk.txt
  rcblk.txt: line 2: syntax error near unexpected token `;;'
  $ HOME='/home/a`id`b' → cb::rc_block … ; env -i PATH=/usr/bin:/bin bash -c 'source rcblk.txt; echo "$PATH"'
  /home/auid=1000(fabien) gid=1000(fabien) groups=1000(fabien)…   <- `id` runs at every shell start
  ```
- Impact: only HOME/XDG_CONFIG_HOME containing `$ " \` \` (rare): PATH and completion silently fail, the rc file gets a syntax error, or a command substitution runs at every shell start (bash and zsh blocks).
- Fix: escape both paths with the existing `cb::dq` (lib/util.sh:109) in cb::rc_block; markers unchanged, so old blocks still uninstall. Test with HOME containing `$` and `"`. — Cost: XS

### POR-07 rc rewrite permission fallback is BSD-only: with BusyBox (Alpine) `chmod` it prints `chmod: invalid mode` and widens a 600 `~/.bashrc` to 644
- Severity: minor   - Status: VERIFIED by simulation (`chmod` shim rejecting `--reference`; GNU `stat`); real BusyBox NOT VERIFIED
- Aspect: Alpine/BusyBox   - Location: lib/install.sh:88, reached by `init.sh --uninstall` and `self rename`
- Evidence:
  ```
  $ chmod 600 ~/.bashrc; stat -f %Lp ~/.bashrc 2>/dev/null || echo 644      # GNU: -f = file-system status
    File: "/tmp/.../home/.bashrc"
      ID: 6a2acb75d12e22b6 Namelen: 255     Type: tmpfs
  Block size: 4096 …                                        (6 lines, then "644")
  $ PATH="$SB/shim:$PATH" bash "$APP/init.sh" --uninstall tt
  chmod: invalid mode: ‘  File: "/tmp/.../home/.bashrc"\n    ID: … \n644’
  Try '/usr/bin/chmod --help' for more information.
  $ ls -l ~/.bashrc | cut -c1-10
  -rw-r--r--                                               <- was -rw-------
  ```
  `stat -f %Lp` is BSD syntax (fine on macOS); BusyBox `chmod` has no `--reference` and BusyBox `stat -f` means file-system status as in GNU. apk is a supported manager (lib/config.sh:13); the Bash 4.2 CI job installs GNU coreutils so never sees BusyBox; no test checks the rc mode.
- Impact: Alpine users uninstalling/renaming: alarming error, and a private rc file (tokens) becomes world-readable.
- Fix: `cp -p -- "$real" "$tmp"` (POSIX) before writing it with `>"$tmp"` (truncation keeps the mode), then `mv`; drop chmod/stat. Test: `chmod 600 ~/.bashrc`, uninstall, still 600. — Cost: XS

### POR-08 An exported `CDPATH` breaks `bash path/to/init.sh` (and `bash path/to/main.sh`)
- Severity: minor   - Status: VERIFIED
- Aspect: environment robustness   - Location: init.sh:21, main.sh:17, 21, lib/util.sh:7, 11
- Evidence:
  ```
  $ cd "$SB"; CDPATH=".:$HOME" bash app/init.sh tt
  app/init.sh: line 36: ./app
  /tmp/.../sbx-por.Lc3s9Q/app/lib/core.sh: No such file or directory
  ```
  `cd` prints the directory when a CDPATH entry is used, so CB_ROOT gets two lines. `./init.sh` and the installed link (absolute) are not affected.
- Impact: users who export CDPATH and run the installer from another directory.
- Fix: `unset CDPATH` right after the guard in main.sh and init.sh. — Cost: XS

### POR-09 `cb::completion_script` uses an unquoted replacement: under Bash 5.2 `patsub_replacement`, a `&` in the root name is replaced by `__CB_NAME__`
- Severity: suggestion   - Status: VERIFIED (5.2); 4.2 behaviour of a quoted replacement NOT VERIFIED
- Aspect: Bash 5.2   - Location: lib/complete.sh:163-164
- Evidence:
  ```
  $ CB_NAME='a&b' … cb::completion_script bash | tail -1
  complete -o default -F _cb_complete_a_b a__CB_NAME__b
  $ CB_NAME='a\b' … → complete -o default -F _cb_complete_a_b a\b
  # cb::dq (lib/util.sh:109) round-trips "a&b", "a\b", 'x"y$z`w&\&', '&&\\' correctly (eval check).
  ```
- Impact: none today: init.sh and `self rename` only accept `^[a-z][a-z0-9_-]*$`; only a hand-made link with `&` triggers it.
- Fix: quote the replacement (`${tpl//__CB_NAME__/"$CB_NAME"}`), or validate CB_NAME in main.sh; check on 4.2 in CI first (decision 0011 job). — Cost: XS

### POR-10 Static notes: WSL `/mnt/c` checkouts, zsh adapter, BusyBox coverage in CI
- Severity: suggestion   - Status: NOT VERIFIED (no drvfs writes allowed, no zsh, no BusyBox)
- Aspect: WSL / zsh / CI   - Location: templates/completion.zsh, .github/workflows/tests.yml:56-70, builtin/self/doctor/cmd.sh:120
- WSL drvfs: without the `metadata` mount option every file is 0777 → doctor's "cmd is not executable" never fires and `chmod +x` is a no-op (harmless); directories created by Windows are case-insensitive → `self new Foo` next to `foo` fails with a bare "File exists"; 9P is much slower on metadata: baseline here on Linux fs is 30 ms per root Tab, 54 ms for `self <Tab>`, 21 ms for flags (help and completion load every child's flags.sh in subshells) → expect several times more on `/mnt/c`. Recommend in README: keep the checkout in the Linux filesystem (`~/…`), not `/mnt/c`.
- zsh adapter: no `emulate -L zsh` at the top of the function, so user options (`KSH_ARRAYS`, `SH_WORD_SPLIT`) change `words[2,CURRENT]` / `${#cands}`; `words` keeps the user's quoting (`'a b` reaches `__complete` with its quote); running `compinit` inside the file when `compdef` is missing can double-initialise with frameworks that call it later (slower startup). Suggest `emulate -L zsh` and `${(Q)words[2,CURRENT]}`.
- CI: add a job on plain Alpine (`bash:5` image + `git` only, BusyBox for the rest) running the end-to-end part, to catch POR-07-like issues; the Bash 4.2 job adds GNU tools on purpose and cannot.

## What is good and must be kept

- Disciplined feature set: nothing newer than 4.2, globals declared at top level (Bash 4.2 `declare -gA` bug, decision 0011), the `cb::tilde` comment documenting the 4.2 `${p/#$HOME/\~}` difference: the team knows the version traps.
- Real Bash 4.2 and 4.1 in CI (441/442 checks on 4.2, the missing one being a docs check), macOS Homebrew Bash, and a pseudo-terminal run on both script flavours.
- Symlink resolution without `readlink -f`, `--` on every path-taking command, `mapfile` instead of `$(...)` word splitting in the bash adapter (nullglob/failglob safe), quoting throughout: the whole flow works from a directory named `x&[y]'z*é$v`.
- The version guard is written so that dash, zsh and Bash 3.x parse it (`case`, no `[[`): verified with dash.
- Pure-Bash prompts with `_CB_TTY` and "no terminal = no".

## Risks for the future

- Any new `=~ [a-z]`, `${x^^}` or `sort`-dependent output reintroduces POR-05; add the convention and a tr_TR CI check.
- Pattern substitutions with a variable replacement must be quoted (POR-09) or they change meaning on 5.2.
- Writing paths into shell code (rc files, generated scripts) should always go through `cb::dq` (POR-04).
- The Bash 4.2 job silently skips one check: probably the handoff-sha check (tests/run.sh:122), because git inside the container refuses the bind-mounted repo owned by another uid ("dubious ownership"). NOT VERIFIED; `git config --global --add safe.directory /w` in the job would make the counts equal and a lower count meaningful.

## Open questions for the owner

1. Should names stay ASCII-only whatever the locale? Recommendation: yes, enforce it with explicit lists (POR-05) and say so in the docs.
2. Is Alpine/BusyBox a supported runtime (apk is a supported package manager)? Recommendation: yes, fix POR-07 and add the small Alpine CI job (POR-10).
3. On macOS, may init.sh touch `~/.bash_profile`? Recommendation: yes, after a confirmation, with its own marker block (POR-06).
4. Is a checkout under `/mnt/c` supported on WSL? Recommendation: no, document "keep it in the Linux filesystem", and add `.gitattributes` anyway (POR-01).
