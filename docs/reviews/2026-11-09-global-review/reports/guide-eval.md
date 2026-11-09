# guide-eval — evaluation of the AI guide (`mu self guide`) with 7 simulated chat answers

Status: COMPLETE. Note: a machine reboot wiped /tmp after the runs; the sandboxes, `runs/*.log`, `blocks/`, `tools/` and `fixtures/` cited below are gone. The quoted outputs were copied from them before the reboot (verbatim, trimmed).
`$SCR` = `$SCR`.

## Scope and method

- Read: `templates/ai-guide.md` (all), the generated guide `$SCR/guide-eval/guide.md` (Setup
  table, Existing commands, `requires`, `ui::` reference), `docs/testing.md:117-157`,
  `builtin/self/guide/cmd.sh:68-71`, `tests/run.sh:633-690` (select keys, fake apt-get/sudo).
- Method of `docs/testing.md:117-146`. For each answer: fresh sandbox
  (`mksandbox.sh ge-<id> mu --init`); the ```bash blocks after `--- USER: ok ---` (else all) are
  extracted in order by `$SCR/guide-eval/tools/extract.sh` (de-indented like a chat "copy"
  button), template path replaced by `$SB/app`; fakes first in PATH (`tools/mkfakes.sh`: sudo
  runs "$@", apt-get/apt/dnf/brew log and create a dummy command, xdg-open / wslview /
  explorer.exe / cmd.exe / powershell.exe / sensible-browser / firefox / open only log);
  `EDITOR=VISUAL=true`, `_CB_TTY=/dev/null`, `NO_COLOR=1`, `timeout 60 bash -x answer.sh`.
  Then `mu self doctor`, `--help`, the suggested runs and my own edge cases.
- Unmodified blocks: `$SCR/guide-eval/blocks/<answer>.sh`. Logs: `$SCR/guide-eval/runs/<answer>.log`
  (full `bash -x` run) and `<answer>.edge.log` (doctor + edge cases).
- jq is not installed (no python either): for R3 the `requires` / `self deps install` path was
  run with the fakes, then the logic was tested with `$SCR/guide-eval/tools/minijq`, a FAKE jq
  that only implements the exact filters of the two answers on one-object-per-line fixtures
  (`$SCR/guide-eval/fixtures/`). Results that depend on real jq are marked "emulated jq".
- `df` edge cases (95 % / exactly 90 % / mount point with a space / `-` line) use a fake `df`
  (`$SB/fakedf/df`); colours were checked in a pseudo-terminal (`script -qec`) without `NO_COLOR`.
- R5 ran only inside throwaway repos `$SB/repo`, `$SB/repo2` (main, merged, unmerged, `main-x`,
  current branch, detached HEAD, master-only repo). The real repository was never entered.
- Not covered: real terminals / real paste behaviour (bracketed paste), real jq, real Windows
  interop (`explorer.exe`, `cmd.exe`), other models than the 7 answers given.

## Grade

| Aspect | Grade | Comment |
|---|---|---|
| Framework rules (extension, `requires`, `ui::select`, English, heredocs, no `--default 0`) | A | 7/7 answers follow them; `self doctor` is clean everywhere; every heredoc is paste-safe. |
| Asking questions | B | All 4 answers that asked used one numbered list with defaults; 2 over-ask on points the guide already settles (menu tool, error reporting, hidden files). |
| Destructive actions | B | Both commands that delete confirm (default No) with `--yes`/`--dry-run`; but nothing protects the user's data in the *try* step (GDE-01). |
| Using the *System* row | C | WSL is used well when obvious (browser), ignored otherwise: both `system disk` answers raise a permanent false red alert on this WSL2 machine (GDE-02). |
| Correctness of the generated commands | B | All 7 work on the main path; 6 small edge-case bugs (model errors, see per-answer). |

## Per-answer results

### R1-haiku — `mu files big` (precise request) — verdict: works, mild over-asking

| Step | Result | Evidence |
|---|---|---|
| Questions | OK (mild over-ask) | 2 questions, numbered, defaults (recursion: legitimate; hidden files: a detail to state, `ai-guide.md:64-66`) |
| `self new files big` + parent `about` | OK | `runs/R1-haiku.log`: `+ plugins/files/...` |
| flags.sh / examples | OK | `self doctor`: `✓ 20 valid command(s)` (`runs/R1-haiku.edge.log`) |
| Main runs | OK | sizes sorted, `.hidden` and `big file.iso` (space) listed, `NO_COLOR`/pipe clean |
| Edge cases | OK | `-n 0`/`-n -3` → `✗ --number must be at least 1` exit 1; `-n abc`/`1.5` → parser exit 2; `nope` → `✗ Not a folder: nope`; empty dir → `› No file in ...` on stderr, exit 0, nothing on stdout |
| Filename with a newline | FAIL (minor) | `cmd.sh: line 12: printf: line: invalid number` + a bogus `0 B` line (`runs/R1-haiku.edge.log`) |
| Try step hygiene | FAIL (minor) | `mkdir -p ~/empty-test && mu files big ~/empty-test` leaves a directory in the user's home |

Problems: (b) newline in file names not handled (`find -printf '%s\t%p\0'` + `sort -z` would);
(b) "hidden files?" asked instead of stated; (a) test fixture created in `~` and never removed
→ GDE-01 (the guide gives no rule for test data). Cosmetic: the sample output is misaligned.

### R2-haiku — `mu system disk` (official plugin) — verdict: extension correct, false alarm on WSL2

| Step | Result | Evidence |
|---|---|---|
| No question, choices stated | OK | request precise; threshold, filters, colour behaviour stated |
| Extension | OK | `✓ Command 'mu system disk' created (added to the official plugin 'system', in plugins/+system/)`; `plugins/` = `README.md +system`; `mu system --help` lists `disk` and `info`; `mu system info` exit 0 |
| No parent flags.sh, no `requires` (df standard) | OK | as the guide says (`ai-guide.md:81-82,157`) |
| Red / NO_COLOR / stderr | OK | pty: `^[[31m/dev/sda1 ... 95%`, 90 % not red (strictly above), `! 2 partition(s) above 90 %` on stderr; `NO_COLOR=1`: no escape codes |
| Real run on this WSL2 machine | FAIL (major for the user) | `/dev/sdb 97M 97M 0 100% /usr/lib/linux-tools/6.18.54.1-microsoft-standard-WSL2` → `! 1 partition(s) above 90 %` at every run; `none`, `drivers`, `rootfs`, `/mnt/wslg/*` listed as "partitions" (`runs/R2-haiku.log`) |
| Edge cases given | FAIL (minor) | "`-t 0`: every partition in red" is wrong: 0 % partitions are not `> 0`; `-t -5`/`-t 150` accepted without range check |

Problems: (a)+(b) WSL specifics ignored although the Setup says WSL → GDE-02; (b) wrong
expected output for its own edge case; (b) no range validation.

### R2-sonnet — `mu system disk` — verdict: extension correct, range checked, same WSL2 false alarm

| Step | Result | Evidence |
|---|---|---|
| No question, choices stated (strictly above, exit 0 on alert) | OK | answer lines 1-7 |
| Extension, no parent flags.sh | OK | `plugins/` = `README.md +system`; `mu system info` exit 0 |
| Range check | OK | `-t 101` → `✗ --threshold must be between 0 and 100` exit 1 |
| Red / NO_COLOR / stderr | OK | pty: `^[[31m/dev/sda1 ...^[[0m`, bold header; warning on stderr |
| Real run on this WSL2 machine | FAIL (major for the user) | `-x squashfs -x overlay` does not exclude the WSL image (it is `ext4`): `/dev/sdb ... 100% /usr/lib/linux-tools/...` → `! 1 partition(s) above 90% usage` at every run |
| `-` in the Use% column | FAIL (minor) | `cmd.sh: line 12: ((: -: syntax error: operand expected (error token is "-")` then `-%` row (fake df; real `df` without `-a` rarely prints `-`) |

Problems: (a)+(b) GDE-02; (b) unguarded arithmetic on df output (R2-haiku guards it with a regex).

### R3-haiku — bookmarks menu (jq, WSL) — verdict: very good

| Step | Result | Evidence |
|---|---|---|
| Questions | OK | 4 questions, defaults: name, Windows opener (WSL-aware), jq (installed by `self deps install`), file |
| `requires jq` + separate `mu self deps install` step before the try | OK | without terminal: `Commands to run: sudo apt-get update / sudo apt-get install jq` → `✗ cancelled`; the command then refuses: `✗ 'mu bookmarks open' needs 'jq', not installed / Install: mu self deps install` (`runs/R3-haiku.log`) |
| deps install with "y" | OK | fakes log `sudo apt-get update`, `sudo apt-get install jq`; `✓ jq installed`; again → `✓ Nothing to install.` |
| `ui::select`, no fzf | OK | menu `1) Example  (https://example.com) ...`; down+Enter → `OPENER wslview https://example.org/?q=a&b=c` (emulated jq) |
| Errors | OK | absent file, invalid JSON, JSON object, `[]` → clear `✗` messages, exit 1; no terminal → `✗ Cancelled` exit 1 |
| Fallback without wslview | OK | `OPENER cmd.exe /c start  https://example.com` |
| Try step hygiene | FAIL (minor) | `echo '[]' > ~/empty.json` overwrites a user file of that name and is never removed |

Problems: (a) GDE-01 (test data in `~`); (b) `wslview` tested with `command -v` but not declared
`requires wslview --apt wslu --optional`, so `self deps` never offers it (GDE-05); the `&`
problem of the `cmd.exe` fallback is stated by the AI itself.

### R3-sonnet — bookmarks menu — verdict: works, over-asks, opens "null"

| Step | Result | Evidence |
|---|---|---|
| Questions | OK but over-asks | 6 questions; #4 (use `ui::select`?) and #6 (clear error on bad file?) are settled by the guide (`ai-guide.md:137-139`) |
| `requires jq` + separate deps step | OK | same messages as R3-haiku (`runs/R3-sonnet.log`) |
| `ui::select`, `explorer.exe ... || true` | OK | `OPENER explorer.exe https://example.org/?q=a&b=c` (emulated jq) |
| Test data | OK | fixtures in `/tmp/bm-*.json`, "your real `~/bookmarks.json` is not touched" |
| Entry without "url" | FAIL (minor) | menu shows `3) No URL (null)`, picking it → `› Opening null`, `OPENER explorer.exe null` (emulated jq; `"\(.url)"` of a missing key is the string `null` in jq) |

Problems: (a)+(b) over-asking → GDE-03; (b) `null` not filtered (R3-haiku's `select(.url)` does).

### R4-haiku — "my notes" (vague) — verdict: good questions and code, but the try block destroys real data

| Step | Result | Evidence |
|---|---|---|
| Questions | OK | 4 numbered questions with defaults (features, storage, confirmation, name) then the full answer |
| 4 × `self new`, parent `about`, 9 heredocs | OK | `runs/R4-haiku.log`; `self doctor` `✓ Everything is fine.` |
| Runs | OK | output identical to the answer's expected text (add/list/search/rm 99/rm 1 -y) |
| Confirmation | OK | `rm 1` without terminal → `? Delete this note? [y/N]` → `✗ Cancelled, nothing deleted` exit 1; with "y" → deleted |
| Validation | OK | `rm 0`, `-1`, `abc`; `add` without text → `✗ missing argument: <text>` exit 2 |
| Search with a backslash | FAIL (minor) | `notes search 'sure \t'` → `› No note contains 'sure \t'.` although the note exists (`awk -v` interprets escapes) |
| **Try block on a user who already has `~/notes/notes.txt`** | **FAIL (major)** | before: `2024-01-02 ... Bank account PIN reminder` / `2025-06-01 ... Passport renewal`; after pasting the try block: `Passport renewal`, `Buy milk for tomorrow`, `Call the dentist on Monday` — the user's oldest real note is deleted without confirmation (`mu notes rm 1 -y`) and two test notes are added (`runs/R4-haiku.edge.log`) |

Problems: (a) GDE-01; (a) the storage place: the guide only covers *settings*
(`ai-guide.md:148-151`), not data → GDE-04 (the path is hard-coded in 4 `cmd.sh`).

### R5-haiku — `mu git clean-branches` (destructive) — verdict: very good

| Step | Result | Evidence |
|---|---|---|
| No question, choices stated | OK | base `main` (`--base`), current branch kept, local only, confirmation default No, `--dry-run`, `--yes`, `git branch -d` |
| `requires git` + deps step | OK | `✓ Nothing to install.` (git is present; harmless) |
| Try block | OK | only `--help` and `--dry-run`: nothing destructive is pasted |
| Dry run / no terminal | OK | `feat-a feat-b main-x` listed on stdout, messages on stderr; no terminal → `› Cancelled, nothing deleted.`, all branches kept |
| Deletion with "y", on unmerged `wip` | OK | `feat-a`, `feat-b`, `main-x`, `topic` deleted; `wip`, `main` kept; `! Kept feat-c: error: the branch 'feat-c' is not fully merged` (as the answer warned) |
| Errors | OK | `--base nope`, not a repo, master-only repo → `✗ ...` exit 1 |
| Detached HEAD | FAIL (minor) | `› Merged into 'main' (2): (HEAD detached at refs/heads/main) feat-c` then `! Kept (HEAD detached ...): error: branch '(HEAD detached at refs/heads/main)' not found` (`git for-each-ref --merged "$base" refs/heads/` avoids it) |

Problems: (b) detached-HEAD pseudo entry. Note R5 keeps its try block non-destructive (`--dry-run`),
which is exactly what R4 failed to do: the behaviour depends on the model, not on the guide.

## Findings

Guide weaknesses (a) first; model errors the guide already covers are listed per answer above.

### GDE-01 The "Try it" step has no rule protecting the user's real data
- Severity: major   - Status: VERIFIED (R4 sandbox)
- Aspect: destructive actions / try step   - Location: templates/ai-guide.md:90-96, :121-122
- Evidence: R4-haiku try block (`mu notes add ...`, `mu notes rm 99`, `mu notes rm 1 -y`, ...) pasted by a user who already has `~/notes/notes.txt` (the default path they accepted):
  ```text
  before: 2024-01-02 09:00  Bank account PIN reminder: ask the bank
          2025-06-01 10:00  Passport renewal before July
  after:  2025-06-01 10:00  Passport renewal before July
          2026-11-08 23:50  Buy milk for tomorrow
          2026-11-08 23:50  Call the dentist on Monday
  ```
  The oldest real note is deleted with no confirmation, and two test notes are added. Smaller cases: R1 `mkdir -p ~/empty-test` (never removed), R3-haiku `echo '[]' > ~/empty.json` (overwrites a user file with that name). R3-sonnet (`/tmp/bm-*.json`) and R5 (`--dry-run` only) did it right, so whether the data is safe depends on the model.
- Impact: any data-handling command (notes, todo, backups, cleaning). Data is lost when the user pastes the try step, the one step they paste without reading.
- Fix: add to step 5 after line 93: "The try runs must not change the user's real data. Show a destructive command with `--dry-run` (or let it ask and answer `n`), never with `--yes`. Run it on throwaway data in a temporary directory (`t=$(mktemp -d)` ... then `rm -rf "$t"`), never in the user's home or on their real files. A command that works on a data file of its own gets a way to point to another file (for example `--file`), so the try runs can use a temporary one." Add a test `check "guide: try runs leave real data alone"`. Cost: XS-S.

### GDE-02 The *System* row is not used: both `system disk` answers show a false red alert on every run on WSL2
- Severity: major   - Status: VERIFIED (R2-haiku, R2-sonnet on this machine)
- Aspect: Setup / system   - Location: templates/ai-guide.md:28-32, :140-141; builtin/self/guide/cmd.sh:69-70
- Evidence: real `df` here: `/dev/sdb 97M 97M 0 100% /usr/lib/linux-tools/6.18.54.1-microsoft-standard-WSL2`. That mount is a read-only WSL image (`findmnt`: `ext4 ro,relatime`), so it is always 100 % full. Both answers then print `! 1 partition(s) above 90 %` at every run. They also list `none`, `drivers` (9p), `rootfs /init` and `/mnt/wslg/*` as "partitions". R2-sonnet's `-x squashfs -x overlay` does not catch it, because the image is ext4. The guide only adds "(WSL: Linux under Windows)" to the System row. Nothing tells the AI what follows from it. The R3 answers did handle WSL for the browser, but only because that request was obviously about Windows.
- Impact: the main feature of the command (the warning) is permanently wrong on the user's own machine. The same will happen with other system requests (mounts, network, services without systemd, opening files).
- Fix: add a rule after line 141: "Take the *System* into account and say how. On WSL, for example: the Windows drives are under `/mnt/<letter>`. WSL adds its own mounts (`/usr/lib/wsl/...`, `/mnt/wslg/...`, read-only images that can be 100 % full). URLs and files open with Windows programs (`explorer.exe`, or `wslview` from `wslu`)." Alternative or complement: add the distribution (`PRETTY_NAME` of `/etc/os-release`, here "Debian GNU/Linux 13 (trixie)") to the System row in `builtin/self/guide/cmd.sh:69-71`. This also tells the AI which tools count as standard (`ai-guide.md:157`; compare R5's hesitation about `requires git`). Cost: XS (+S with the distribution and a test).

### GDE-03 The "grey areas" list invites questions that the guide already settles
- Severity: minor   - Status: VERIFIED (from the answers)
- Aspect: asking questions   - Location: templates/ai-guide.md:49, :52-55 vs :64-66, :137-139
- Evidence: R3-sonnet asks 6 questions. #4 "Menu: I suggest `ui::select` ... (yes)" and #6 "missing or bad file: clear error and stop (yes)" are both decided by the Rules: `ui::select`, `ui::die`. Line 49 lists "how errors must be reported" as a grey area, and lines 52-55 put the menu tool among the questions. R1 asks about hidden files, a detail that should be stated (line 64-66).
- Impact: an extra round trip and noise. The defaults keep it cheap, but weak models copy the list as-is.
- Fix: line 49 → "what it prints (format, columns, colours);". Lines 52-55 → "which external tools it needs: ask only when one must be installed (it is declared with `requires`, see *Rules*), and propose a pure-Bash way when there is a simple one. Do not ask about what this guide settles: menus use `ui::select`, errors `ui::die`, confirmations `ui::confirm`." Cost: XS.

### GDE-04 Where to keep the data a command manages is not covered (only settings are)
- Severity: minor   - Status: VERIFIED (guide text + R4)
- Aspect: data location   - Location: templates/ai-guide.md:148-151; docs/testing.md:145-146
- Evidence: the guide puts *settings* under `$CB_CONFIG_DIR`. docs/testing.md lists "dynamic data stored in `CB_CONFIG_DIR` (notes)" as an evaluation case, but the guide never says so. R4 asked (good), chose `~/notes/notes.txt`, and hard-coded `$HOME/notes/notes.txt` in 4 `cmd.sh` files.
- Impact: a different location in every answer, paths duplicated across files, and nothing that allows a temporary file in the try runs (see GDE-01).
- Fix: once the owner decides (see the open questions), add: "Data the command manages (notes, history, cache): propose a file under `$CB_CONFIG_DIR` (or the place the user prefers), with its path in one place (a `--file` flag with that default, or the settings file)." Cost: XS.

### GDE-05 Odd values in another tool's output are missed (4/7 answers)
- Severity: minor   - Status: VERIFIED (R2-sonnet, R5, R1; R3-sonnet with emulated jq)
- Aspect: correctness   - Location: templates/ai-guide.md:90-93 (the edge-case rule only says *run* one)
- Evidence: R2-sonnet `((: -: syntax error: operand expected` on a `-` Use% line. R3-sonnet `› Opening null` for an entry without "url" (jq turns a missing key into the string `null`). R5 in detached HEAD lists `(HEAD detached at refs/heads/main)` as a branch and tries to delete it. R1 prints `printf: line: invalid number` for a file name with a newline. In every case the model picked an edge case of the *input it gets from the user*, never of the data it parses from another tool.
- Fix: add a rule: "Data read from another tool can be odd: handle the cases you know (`-` instead of a number in `df`, `null` for a missing key in `jq`, a detached HEAD in git, file names with spaces or newlines), and skip what you cannot use." Cost: XS.

### GDE-06 The fallback tool of a "first available" chain is not declared `--optional`
- Severity: suggestion   - Status: VERIFIED (R3-haiku)
- Location: templates/ai-guide.md:157-162
- Evidence: R3-haiku tests `wslview` → `cmd.exe` → `xdg-open` with `command -v`, without `requires wslview --apt wslu --optional`. `self deps` never offers `wslu`, and the `cmd.exe` fallback mishandles `&` in URLs (the AI says so itself).
- Fix: "When the command uses the first available of several tools, declare the preferred one with `--optional` so that `self deps` lists it." Cost: XS.

### GDE-07 The worked example breaks its own "edge case" rule
- Severity: suggestion   - Status: VERIFIED (reading)
- Location: templates/ai-guide.md:90-93 vs :213-226
- Evidence: step 5 requires at least one edge-case run. The worked example only runs `--help`, `test hello` and `test hello Alice -u`. 6/7 answers added edge-case runs anyway, so the impact is low.
- Fix: add, for example, `mu test hello "Ada Lovelace"` → `Hello, Ada Lovelace!`. It must not print `Hello, world!` again, because `tests/run.sh:279` counts that line exactly once. Cost: XS.

## Synthesis

### What the guide does well (keep)
- **Extensions for official plugins:** 2/2 `system disk` answers used `self new system disk`, wrote only `plugins/+system/disk/` and no parent `flags.sh`. `mu system info` is untouched.
- **`requires` with a separate `self deps install` step before the try:** 3/3 (R3 ×2, R5). There is no `command -v jq || ui::die`. Without a terminal the command refuses with `Install: mu self deps install`.
- **`ui::select` instead of fzf:** 2/2. `ui::confirm` with default No plus `--yes`/`--dry-run` on both deleting commands.
- **Question format:** numbered, all at once, a default for each, "ok" accepted (4/4 that asked). Precise requests got no questions (R2 ×2, R5).
- **Files:** in English and ASCII in 7/7; absolute paths and `<<'EOF'` in 7/7 with no delimiter collision; no `--default 0` on bools; examples only use declared flags (`self doctor` clean 7/7).

### Guide changes, ranked by impact
1. GDE-01: the try runs must not touch real data (`--dry-run`, `mktemp -d`, never `--yes`). This prevents data loss.
2. GDE-02: tell the AI to use the System row (WSL specifics; maybe add the distribution).
3. GDE-05: handle odd values from other tools.
4. GDE-03: remove error reporting and the menu tool from the grey areas.
5. GDE-04: say where data lives (owner decision first).
6. GDE-06 and GDE-07: small wording fixes.

### Permanent evaluation set (docs/testing.md:142-146)
- Keep `git clean-branches` (R5) and `system disk` (R2). Add to the latter: "check that the alert is not always on for the machine's own mounts (WSL)".
- Add **the bookmarks request** (R3: JSON → jq via `requires` + `ui::select` + browser on WSL). It covers three rules at once.
- Keep **"my notes"** (R4) and add the check "the try block must not modify the user's existing data". This is the request that revealed GDE-01.
- R1 (`files big`) is a low-signal baseline (everything passed). Keep it only as an over-asking check.

## What is good and must be kept
See "What the guide does well" above. Also the "no terminal → no" contract (`ui::confirm`, `self deps install`). It made every pasted block safe in an automated run.

## Risks for the future
- **Interactive command in the middle of a block.** Simulated with `_CB_TTY` as a file: the next pasted line `mu bookmarks open -f ~/absent.json<Enter>` drove the R3-haiku menu. The `k` wrapped to the last entry, Enter selected it, and `wslview`/`cmd.exe` opened `https://nameless.example`, which the user never chose. In a real terminal, bracketed paste (Bash ≥ 5.1, zsh) usually prevents this. NOT VERIFIED in a real terminal. No answer did this. Worth one sentence at `ai-guide.md:121-122`: "a command that asks (menu, confirmation, `self deps install`) goes alone in its block, or last".
- Expected outputs are invented: R2-haiku claims "`-t 0`: every partition in red", which is false. That is harmless while the AI says the output is illustrative.

## Open questions for the owner
1. Where should data managed by a command live: `$CB_CONFIG_DIR` (as docs/testing.md implies), `~/.local/share/<name>`, or ask the user? Recommendation: `$CB_CONFIG_DIR` by default, stated in the guide, with the path in a single `--file` default (GDE-04).
2. Should the System row include the distribution (`/etc/os-release`)? Recommendation: yes. It is cheap and tells the AI which tools are standard and which package names to use. Update `ai-guide.md:31-32` accordingly (GDE-02).
