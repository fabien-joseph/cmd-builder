# robustness — everything that changes the user's system (idempotence, interruptions, no-terminal behaviour, exit codes)

## Scope and method

- Read: `init.sh`, `lib/install.sh`, `lib/config.sh`, `lib/ui.sh`, `lib/deps.sh`, `lib/util.sh`, `main.sh`,
  `builtin/self/{rename,update,deps/**,plugins/disable,plugins/_resolve.sh}`, decisions 0007, 0009, 0012, 0014,
  the exit-code table (docs/architecture.md:104-111), known limitations (docs/roadmap.md:79-93),
  templates/ai-guide.md:148-150, interruption tests in tests/run.sh (:613-626).
- Ran 8 experiment scripts (exp1..exp8), each in a fresh sandbox from `mksandbox.sh` (isolated HOME /
  XDG_CONFIG_HOME / PATH, `_CB_TTY` pointing to `/dev/null` or to a file containing `y`), fake
  `sudo`/`apt-get`/`brew`/`chmod`/`ln` first in PATH, local bare git repos only. Baseline suite: 442 passed.
  Note: the sandboxes and scripts were lost in a machine reboot (/tmp wiped); the outputs below were
  captured verbatim before that. Sandbox paths are shortened to `$SB` / `~`.
- Interruptions: partial states reproduced by hand or with a failing fake binary (half rc block, failing `ln`),
  the other steps checked by reading (see Grade). No kill-at-N-calls wrapper.
- NOT covered: real zsh, BusyBox, macOS/BSD tools, Bash 4.2 (not installed: static analysis or simulation),
  real package managers and network, concurrent writers (two config writes at once).

## Grade

| Aspect | Grade | Comment |
|---|---|---|
| Idempotence / resumability (rule 4) | C | Uninstall, install and config writers (temp + `mv`) are resumable; rename re-run after an interruption is tested. But a failed step in `self rename` is not checked (ROB-04), a half rc block is never repaired (ROB-10), and `--keep-old` round trips lose data (ROB-01, ROB-02). |
| Data safety (config, plugin data, rc files) | D | One silent config loss with "Done"/exit 0 (ROB-01), one behind a default-yes question (ROB-02), plugin data stranded by rename (ROB-03), rc mode lost on BusyBox (ROB-07). |
| Confirmation / no terminal (rule 5) | B | Every prompt goes through `ui::confirm`/`ui::select`, "no terminal = no" holds everywhere (verified). Weak points: a default-yes deletion (ROB-17), invisible prompts when stderr is redirected (ROB-14), "Replace it?" hides that a regular file is deleted (ROB-12). |
| Exit codes / error reporting | D | `self update` always exits 0, even after "update failed" (ROB-05); init.sh and rename print success after failed writes (ROB-09, ROB-04); table incomplete (ROB-16). |
| rc file handling | B | Atomic rewrite, symlink following, broken-block refusal, blank-line handling and two side-by-side installs all correct (verified). Gaps: CRLF/indented markers (ROB-08), ZDOTDIR/XDG drift (ROB-11), mode fallback (ROB-07). |

Prompt inventory (every prompt of the project):

| Location | Question | Default | Without terminal | Judgement |
|---|---|---|---|---|
| init.sh:83 | Also remove your configuration (…/config)? | **Y** | no, kept (verified) | irreversible deletion with default yes; hides sharing (ROB-02, ROB-17) |
| init.sh:117 | Replace it? | N | cancelled, exit 1 (verified) | OK, but should say what is replaced (ROB-12) |
| init.sh:121 | Install anyway (one will hide the other…)? | N | cancelled, exit 1 | OK |
| init.sh:145 | Enable '<name>' completion in ~/.bashrc? | Y | not added | OK (additive, reversible) |
| lib/deps.sh:31 | Package manager … (`ui::select`) | best detected | default saved (verified) | accepted by 0014; see ROB-18 |
| builtin/self/deps/_common.sh:37 | Run them? (sudo + network) | Y | cancelled, exit 1 (verified) | acceptable: commands shown first |
| builtin/self/update/cmd.sh:51 | Update? | Y | skipped, exit 0 (verified) | acceptable (`--ff-only`) |
| builtin/self/guide/cmd.sh:106 | … already exists. Overwrite it? | N | cancelled, exit 1 | OK |
| builtin/self/rename/cmd.sh:63 | Rename? | N | cancelled, exit 1 (verified) | OK |

## Findings

### ROB-01 `self rename` back to the old name after `--keep-old` deletes the configuration
- Severity: critical   - Status: VERIFIED
- Aspect: data safety of `self rename`   - Location: builtin/self/rename/cmd.sh:81-96 (line 89), decision 0012
- Evidence (exp2): `disable core:system` added to `tt`'s config, `tt self rename xx --keep-old` (so `~/.config/tt/config -> ~/.config/xx/config`), then going back with `xx self rename tt`, answer `y`:
  ```
  tt/config -> ~/.config/xx/config
  › link ~/.local/bin/tt: already there
  › ~/.config/tt/config: already moved
  ✓ configuration: ~/.config/tt/config
  ✓ ~/.bashrc: 'xx' block replaced by 'tt'
  › ~/.config/xx kept (it still contains files)
  ✓ link ~/.local/bin/xx removed
  ✓ Done: the command is now 'tt'.
  exit=0
  tt/config -> ~/.config/xx/config; disable lines: 0
    system             core:system           active
  ```
  Same with three names (exp1: `tt→xx`, `xx→yy --keep-old`, `yy→xx`): `disable lines now: 0`, header back to the default `# Configuration of "xx"`.
- Impact: every user setting (`disable`, `rename`, `package-manager`) silently replaced by the default file, with "Done" and exit 0. Going back after trying a name with `--keep-old` is the natural use of that option. Cause: the checks accept the pair because `same_config` is true (`nc` links to `oc`); step 2 only handles "`oc` is the link" (line 81); otherwise line 89 assumes `nc` is an identical *copy* and runs `rm -f -- "$oc"`, deleting the only real file; `nc` is now dangling, so line 95 (`cb::config_ensure`, `[[ -f ]]` false) writes a default config through the dangling link.
- Fix: never `rm` a path that is not a symlink. When `same_config` and `oc` is the real file: `rm -f -- "$nc" && mv -- "$oc" "$nc"`. Keep the "identical copy" branch for `! same_config && cmp -s` only. Test both sequences (`a→b --keep-old; b→a` and `a→b --keep-old; a→b`). — Cost: S
- Decision: 0012 stays valid; its step list should cover the link in both directions.

### ROB-02 Uninstalling the name that owns a shared config silently removes the other name's config (default: yes)
- Severity: major   - Status: VERIFIED
- Aspect: confirmation (rule 5) / data safety   - Location: init.sh:71-90 (prompt :83), decision 0012
- Evidence (exp2): `tt` with `disable core:system`, `tt self rename xx --keep-old`, then `./init.sh --uninstall xx`, answer Enter:
  ```
  ? Also remove your configuration (~/.config/xx/config)? [Y/n] ✓ ~/.config/xx/config removed
  ✓ ~/.config/xx removed
  ✓ 'xx' is uninstalled. Open a new terminal for it to take effect.
  exit=0
  tt/config: -> ~/.config/xx/config; target exists? NO
    system             core:system           active
  $ tt self plugins disable core:system
  .../lib/config.sh: line 60: ~/.config/tt/config: No such file or directory
  .../lib/config.sh: line 78: ~/.config/tt/config: No such file or directory
  .../lib/util.sh: line 11: cd: ~/.config/xx: No such file or directory
  ✓ core:system disabled (re-enable: tt self plugins enable core:system)
  ```
  `tt self doctor` only says `! no config file (~/.config/tt/config)`, exit 0 (exp7).
- Impact: with `--keep-old` the real file lives under the *new* name; dropping that name (keeping the old one) deletes the config the remaining name uses. The question names only `~/.config/xx/config` and defaults to yes. Decision 0012 only describes uninstalling the old name.
- Fix: in `uninstall_config`, look for other `${XDG_CONFIG_HOME:-$HOME/.config}/*/config` symlinks resolving to this file; if one exists, move the file onto that link instead of asking. Make `self doctor` say "dangling link to …". — Cost: S

### ROB-03 `self rename` leaves plugin data of `$CB_CONFIG_DIR` behind; plan and `--help` say the directory moves
- Severity: major   - Status: VERIFIED
- Aspect: rename / plugin contract   - Location: builtin/self/rename/cmd.sh:48 (plan), :79-99 (only `config` moves), builtin/self/rename/flags.sh:2, templates/ai-guide.md:148-150, docs/decisions/0012-self-rename.md:24
- Evidence (exp1): fixture plugin `notes` reading `$CB_CONFIG_DIR/notes.txt` (the layout the AI guide prescribes for plugin settings, `chmod 600` for secrets):
  ```
  $ tt notes            -> token=abc   exit=0
  $ tt self rename xx   (answer y)
    ~/.local/bin/tt → ~/.local/bin/xx
    ~/.config/tt/ → ~/.config/xx/          <- plan: the directory moves
  › ~/.config/tt kept (it still contains files)
  ✓ Done: the command is now 'xx'.   exit=0
  $ xx notes
  ✗ no notes in ~/.config/xx/notes.txt   exit=1
  ~/.config/tt: notes.txt
  ~/.config/xx: completion.bash completion.zsh config
  # --keep-old (notes copied to xx/ by hand): xx self rename yy --keep-old
  yy notes -> ✗ no notes in ~/.config/yy/notes.txt (exit 1); xx notes -> token=abc (exit 0)
  ```
- Impact: every plugin following the guide loses its settings (connections, tokens) after a rename, although the plan and `--help` ("Moves … ~/.config/$CB_NAME/ …") promise the directory moves. With `--keep-old` both names see different data. (`init.sh --uninstall` keeping such files is right, and reported.)
- Fix: move every entry of `old_dir` except generated files (`completion.*`, `config.tmp`), refusing in the checks phase on a conflicting entry; with `--keep-old`, leave a symlink per entry. Cheaper alternative (S): list the other entries in the plan and fix the wording. — Cost: M
- Decision: 0012 says "config file moved"; it predates the guide's advice. Update it.

### ROB-04 `self rename` removes the old link even when the new one could not be created: no command left, "Done", exit 0
- Severity: major   - Status: VERIFIED (failure simulated with a fake `ln`)
- Aspect: resumability (rule 4)   - Location: builtin/self/rename/cmd.sh:72-77 (result of `ln` ignored), :127-134 (old link removed regardless)
- Evidence (exp8): fake `ln` first in PATH failing like ENOSPC/EDQUOT, `tt self rename zz`, answer `y`:
  ```
  ln: failed to create symbolic link: No space left on device
  ✓ configuration moved to ~/.config/zz/config
  ✓ ~/.bashrc: 'tt' block replaced by 'zz'
  ✓ ~/.config/tt removed
  ✓ link ~/.local/bin/tt removed
  ✓ Done: the command is now 'zz'.
  exit=0
  type tt: none, type zz: none
  ```
- Impact: rare trigger (disk full, quota), but it breaks the guarantee of decision 0012 ("old link last, so … the command can be run again"): neither name exists, `tt self rename zz` cannot be re-run; recovery needs `./init.sh zz` from the checkout, with no hint.
- Fix: after step 1, `cb::link_is_ours "$new_link" || ui::die "cannot create $new_link: nothing else changed"`; more generally stop at the first failed step (each step `|| ui::die`). — Cost: XS

### ROB-05 `self update` always exits 0 and reports success after failures
- Severity: major   - Status: VERIFIED
- Aspect: exit codes / reporting   - Location: builtin/self/update/cmd.sh:29-33, :56-58, :67-73, :80-82 (last statement decides the status), docs/architecture.md:109
- Evidence (exp4; checkout + plugins `pl`, `+system` (extension with `.git`, correctly included), `broken` (remote path missing)):
  ```
  ### all up to date except unreachable "broken"
  ! cannot reach the remote repository (network? permissions?)
  ✓ Everything is up to date.                          => exit=0
  ### one upstream commit: --check, then no terminal
  › 1 repository(ies) to update: run 'mu self update'  => exit=0
  › skipped                                            => exit=0
  ### dirty tree conflicting with upstream, answer y
  ✗ update failed (local changes or diverged history?)
  ✓ 0/1 repository(ies) updated.                       => exit=0
  ### diverged (local commit), answer y: same lines    => exit=0
  ### detached HEAD in plugin pl: ! no upstream branch, skipped (by design)
  ```
- Impact: no failure (fetch, refused fast-forward, dirty tree) is visible to a script or bootstrap; `--check` cannot be used as a test. The summary misleads the user too (unreachable counted as up to date; 0/1 with the success symbol).
- Fix: count failed/unreachable repos, summarise with `ui::warn`/`ui::error`, exit 1 on any failure; for `--check`, a distinct documented code when updates exist (as `dnf check-update` uses 100), or document 0. Add to the exit-code table. — Cost: S

### ROB-06 After pulling the main repo, `self update` mixes old in-memory code with new files (proven break)
- Severity: minor   - Status: VERIFIED (with a fabricated upstream commit)
- Aspect: update safety   - Location: builtin/self/update/cmd.sh:65 (old `cb::completion_install` + new templates), :76-79 (new `lib/deps.sh` sourced into the old process)
- Evidence (exp4): upstream commit adding `cb::new_helper` to `lib/util.sh` and calling it from `cb::deps_collect`, then `mu self update`, answer `y`:
  ```
  ✓ 1/1 repository(ies) updated.
  $SB/install/lib/deps.sh: line 78: cb::new_helper: command not found
    => exit=0
  ```
- Impact: today only the end of one run breaks; a future change of template placeholders or spec-loader output would make the old `cb::completion_install` write a broken completion script right after an update, for every user. Invisible constraint for contributors.
- Fix: after a successful pull of `$CB_ROOT`, run the post-update work (completion, deps reminder) in a new `bash` process loading the new code (e.g. a small `lib/post-update.sh`); document the rule in docs/architecture.md. — Cost: S

### ROB-07 rc rewrite loses the file mode where `chmod --reference` is missing (BusyBox/Alpine), with a cryptic error
- Severity: minor   - Status: VERIFIED by simulation (fake `chmod` rejecting `--reference`, GNU `stat`); NOT VERIFIED on real BusyBox
- Aspect: rc files   - Location: lib/install.sh:88
- Evidence (exp3): `~/.bashrc` mode 600, `./init.sh --uninstall tt`:
  ```
  GNU: mode after rewrite 600
  chmod: invalid mode: ‘  File: "$SB/h3/.bashrc"
  Try '/bin/chmod --help' for more information.
  no --reference: mode after rewrite 644
  what the fallback computes: [  File: "~/.bashrc"
      ID: 6a2acb75d12e22b6 Namelen: 255     Type: tmpfs
  ```
  For GNU and BusyBox `stat`, `-f` is a flag (file-system status) and `%Lp` a file operand; only BSD `stat -f %Lp` prints the mode.
- Impact: on Alpine (`apk` is supported, decision 0014) every uninstall/rename prints a chmod error and makes a private rc file (tokens) world-readable.
- Fix: `cp -p -- "$real" "$tmp"` then write the content with `>"$tmp"` (keeps the mode, POSIX). Alternative: `stat -c %a || stat -f %Lp`, validated against `^[0-7]{3,4}$`. — Cost: XS

### ROB-08 Uninstall says "block removed" (every time) when the begin marker has a CRLF or leading spaces; the block stays
- Severity: minor   - Status: VERIFIED
- Aspect: rc files / idempotence   - Location: lib/install.sh:30, :64-65 (substring `grep -F`) vs :69, :72 (exact `==`)
- Evidence (exp3): begin marker given a trailing `\r` (Windows editor, WSL), or two leading spaces:
  ```
  ✓ 'tt' block removed from ~/.bashrc
  ✓ 'tt' block removed from ~/.bashrc        <- second run
  markers left: 2
  ✓ 'tt' block removed from ~/.bashrc
  markers left (indented): 2
  ```
- Impact: false success; rename in that state claims "block replaced" without writing the new block. Harmless leftover content. (End marker damaged instead: safe, file untouched.)
- Fix: compare markers after stripping `\r` and surrounding blanks, or detect "nothing removed" and report it. — Cost: XS

### ROB-09 `init.sh` prints "command installed" / "added to ~/.bashrc" / "All set!" (exit 0) when the write failed
- Severity: minor   - Status: VERIFIED
- Aspect: error reporting   - Location: init.sh:124-127, init.sh:145-147
- Evidence (exp3):
  ```
  # ~/.bashrc read-only (444; same for a home-manager rc linked into a read-only store)
  ? Enable 'tt' completion in ~/.bashrc? [Y/n] .../lib/install.sh: line 47: ~/.bashrc: Permission denied
  ✓ added to ~/.bashrc
  ✓ All set! Open a new terminal, or run this in the current one:
  exit=0 block present: 0
  # ~/.local/bin is a regular file
  mkdir: cannot create directory ‘~/.local/bin’: File exists
  ln: failed to access '~/.local/bin/tt': Not a directory
  ✓ command installed: ~/.local/bin/tt → $SB/app/main.sh
  ✓ All set! ...                                             exit=0
  ```
- Impact: the user is told to `source ~/.bashrc` / run `tt --help`, which fails with no hint. Same pattern in `self rename` is worse (ROB-04).
- Fix: `ln -sfn … || ui::die "cannot create $link"`; `cb::rc_append … || { ui::warn "cannot write $rc"; return 1; }`. — Cost: XS

### ROB-10 Interrupted rc append: re-running the install says "already configured" and keeps a half block
- Severity: minor   - Status: VERIFIED (partial state reproduced by hand)
- Aspect: interruptions (rule 4)   - Location: lib/install.sh:47-49 (several writes), init.sh:141-143 (only `cb::rc_has`)
- Evidence (exp3): block cut after its PATH line, then `./init.sh tt` and `./init.sh --uninstall tt`:
  ```
  › already configured in ~/.bashrc
  ! ~/.bashrc: '# >>> cmd-builder: tt >>>' found but not '# <<< cmd-builder: tt <<<'; file left untouched, remove the block by hand
  ! 'tt' is uninstalled, except the rc file block(s) reported above.
  exit=1
  ```
- Impact: small window (kill or ENOSPC between writes), but the install never repairs nor reports it; uninstall then needs a hand edit (accepted by 0007 for hand-edited files only).
- Fix: build the block in a variable, write it with one `printf`; in `rc_block()`, test `cb::rc_broken` and warn. — Cost: XS

### ROB-11 `ZDOTDIR` and `XDG_CONFIG_HOME` are read from the current environment only: uninstall/rename miss what the install wrote
- Severity: minor   - Status: VERIFIED
- Aspect: rc files / config dir   - Location: init.sh:35, :46, lib/install.sh:19, :22, main.sh:26
- Evidence (exp3, exp7):
  ```
  # install with ZDOTDIR=~/.zdot, uninstall without it
  ✓ 'tt' is uninstalled. Open a new terminal for it to take effect.
  exit=0 blocks left in ~/.zdot/.zshrc: 1
  # install with XDG_CONFIG_HOME=~/xdg, then without it: t2 self plugins disable core:system; ./init.sh --uninstall t2 (y)
  [ -f "$SB/h8/xdg/t2/completion.bash" ] && . "$SB/h8/xdg/t2/completion.bash"     <- rc block keeps install-time path
  ✓ core:system disabled ...      (written to a new ~/.config/t2/config; install-time settings ignored)
  uninstall exit=0
  left: ~/xdg/t2/config ~/xdg/t2/completion.bash ~/xdg/t2/completion.zsh
  ```
- Impact: leftover block or config dir, false "uninstalled"; rename from bash leaves the zsh block and gives the new name no zsh completion. ZDOTDIR is usually set in `~/.zshenv`, which bash never reads.
- Fix: record the rc files and config dir written at install (e.g. a small state file in the config dir) and use it in uninstall/rename; `self doctor` warns when an rc block's completion path is not under the current `$CB_CONFIG_DIR`. — Cost: S

### ROB-12 "Replace it?" deletes a user's own script in `~/.local/bin` without saying so and without backup
- Severity: minor   - Status: VERIFIED
- Aspect: confirmation (rule 5)   - Location: init.sh:114-126
- Evidence (exp3): `~/.local/bin/tt2` is a regular script, `./init.sh tt2`, answer `y`:
  ```
  ! ~/.local/bin/tt2 already exists and does not point to this cmd-builder
  ? Replace it? [y/N] ✓ command installed: ~/.local/bin/tt2 → $SB/app/main.sh
  $ ls -A ~/.local/bin  ->  tt2   (now a symlink; the script is gone)
  ```
- Impact: same question for "a link to another checkout" (harmless) and "your own file" (irreversible). Default `n`, hence minor.
- Fix: say what is there (regular file / link to X / directory); move a regular file to `<name>.cb-backup`; refuse a directory. — Cost: XS

### ROB-13 `self deps update` assumes the first configured manager owns every tool, and stops at the first failure
- Severity: minor   - Status: VERIFIED with fake managers (real `brew` message NOT VERIFIED)
- Aspect: `self deps`   - Location: builtin/self/deps/update/cmd.sh:3-11, lib/deps.sh:45-51, builtin/self/deps/_common.sh:38-42
- Evidence (exp5): managers `brew apt`, tool `foo` installed outside brew:
  ```
  Commands to run:
    brew upgrade foo
  ? Run them? [Y/n] $ brew upgrade foo
  Error: foo not installed
  ✗ failed: brew upgrade foo
  exit=1
  ```
- Impact: tools are updated with the first manager that *could* package them (all, by default), not the one that installed them; with Homebrew first (macOS, Linuxbrew), tools from apt/dnf or installed by hand make the update fail, later managers never run, nothing lists what was skipped.
- Fix: ask each manager whether it owns the package (`dpkg -s`, `rpm -q`, `pacman -Q`, `zypper se -i`, `apk info -e`, `brew list --versions`) and group by owner; report tools owned by none; on failure continue and summarise. — Cost: M

### ROB-14 Prompts go to stderr but read `/dev/tty`: with `2>/dev/null` the command waits on an invisible question
- Severity: minor   - Status: VERIFIED (inside `script`, a real pseudo-terminal)
- Aspect: no-terminal behaviour   - Location: lib/ui.sh:31-42, :45-54, :59-76; decision 0009
- Evidence (exp5): `timeout 8 script -qec "unset _CB_TTY; tt self rename zz 2>/dev/null" /dev/null`:
  ```
    ~/.config/tt/ → ~/.config/zz/
    ~/.bashrc: 'tt' block replaced by a 'zz' block
  Session terminated, killing shell... ...killed.
  exit=124 after 10s
  ```
- Impact: looks like a hang; typing blindly answers an unseen question (Enter = yes for 4 of the 8 confirmations).
- Fix: when `_CB_TTY` is unset and stderr is not a terminal, write the prompt/menu to `/dev/tty` (as ssh/sudo do). — Cost: XS

### ROB-15 Config directory symlinked into a dotfiles repo (stow folding): rename empties the repo, misreports the leftover
- Severity: minor   - Status: VERIFIED
- Aspect: dotfiles   - Location: builtin/self/rename/cmd.sh:80-91, lib/install.sh:121-126; decision 0012 (only a symlinked *file* considered)
- Evidence (exp6): `~/.config/xx -> ../dotfiles/xx` committed in `~/dotfiles`, `xx self rename zz`:
  ```
  ✓ configuration moved to ~/.config/zz/config
  › ~/.config/xx kept (it still contains files)
  exit=0
  dotfiles repo status:  D xx/completion.bash  D xx/completion.zsh  D xx/config
  xx -> ../dotfiles/xx        zz (plain directory)
  ```
- Impact: the config silently leaves the dotfiles repo; the message is wrong (`rmdir` fails on a symlink, the dir is empty). Same message from uninstall.
- Fix: if `old_dir` is a symlink, move the link itself when `new_dir` does not exist (or refuse with a hint); `cb::config_dir_remove` says "is a symlink, left in place". — Cost: XS

### ROB-16 Exit-code table incomplete and inconsistent with the code
- Severity: minor   - Status: VERIFIED
- Aspect: exit codes   - Location: docs/architecture.md:104-111, init.sh:39, builtin/self/rename/cmd.sh:17
- Evidence (exp7):
  ```
  exit=2 : tt self rename BAD        exit=1 : bash init.sh Bad      (same "invalid name" error)
  exit=1 : tt self rename while      exit=2 : bash init.sh
  exit=1 : tt self rename zz (no terminal = cancelled)   exit=1 : bash init.sh other (cancelled)
  exit=0 : tt self deps managers add dnf (not installed, warning)
  ```
- Impact: the table does not list `self update` (always 0, ROB-05), `self deps update` failures (1), `init.sh` cancelled (1); invalid name is 2 in rename but 1 in init.sh.
- Fix: `ui::die … 2` at init.sh:39; complete the table. — Cost: XS

### ROB-17 "Also remove your configuration?" defaults to yes
- Severity: suggestion   - Status: VERIFIED (see prompt table, ROB-02)
- Location: init.sh:83
- Every other destructive prompt defaults to N ("Replace it?", "Rename?", "Overwrite it?"); this is the only irreversible deletion behind Enter. Rule 5 is respected literally (it asks; no terminal = no). Recommend `[y/N]`. — Cost: XS

### ROB-18 `self deps install` saves the suggested manager before the "Run them?" refusal
- Severity: suggestion   - Status: VERIFIED
- Location: lib/deps.sh:26-39, builtin/self/deps/_common.sh:15-17
- Evidence (exp5, no terminal, apt-get detected, nothing configured):
  ```
  ✓ package manager: apt (change it with 'tt self deps managers')
  ? Run them? [Y/n]
  ✗ cancelled
  exit=1 config now: package-manager apt
  ```
- Accepted by decision 0014 ("without a terminal the suggestion is kept, it is only a preference"), so not a defect. Suggestion: in `_deps_run`, keep the choice in memory and save it only after "yes". — Cost: XS

## What is good and must be kept

- Uninstall: each step re-checks its state; refusal on a missing end marker instead of truncating (decision 0007). Two installs side by side: uninstalling one leaves the other block intact, blank lines handled (verified, exp6).
- Atomic rc rewrite (temp + `mv`) following symlinked rc files; mode kept with GNU `chmod --reference` (verified 600 → 600).
- Config writers (`cb::config_set_*`) use temp + `mv` and write through dotfile symlinks: an interruption leaves the old or new file; leftovers cleaned.
- "No terminal = no" holds for every confirmation (verified with `_CB_TTY=/dev/null`); answers never come from piped stdin (decision 0009).
- `self rename`: all checks before one plan and one confirmation; refusal when both configs differ (verified); resumption tested in tests/run.sh:613-626.
- `self update` uses `--ff-only`, skips detached HEAD / no upstream / non-git dirs, includes extensions `plugins/+x`.

## Risks for the future

- No step-status discipline: the scripts have no `set -e` and many steps ignore failures (ROB-04, ROB-09). A rule in docs/conventions.md ("every system-changing step is `|| ui::die`/checked") would prevent new ones.
- `self update` runs old code against new files (ROB-06): any change to templates, spec format or deps.sh can break the run that installs it.
- Install-time paths depend on the environment (ROB-11); a state file recorded at install would make uninstall/rename/doctor exact.
- `--keep-old` sharing by symlink multiplies cases (ROB-01, ROB-02, ROB-15); each new config-dir feature must be tested in both directions.

## Open questions for the owner

1. Should `self rename` move the whole config directory (plugin data included)? Recommendation: yes (ROB-03), refusing on conflicts.
2. Should `self update --check` signal available updates through its exit code? Recommendation: yes, a distinct documented code; failures exit 1 (ROB-05).
3. Default of "Also remove your configuration?": keep Y or switch to N? Recommendation: N (ROB-17).
4. Should the install record what it wrote (rc files, config dir) in a state file? Recommendation: yes, small and makes uninstall/rename exact (ROB-11).
