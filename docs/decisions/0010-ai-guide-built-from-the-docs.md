# 0010. `self guide`: a guide for AI assistants built from the docs

- Status: Accepted (amended 2026-11-09: paste protocol, Setup rows, safe "Try it")
- Date: 2026-11-08

## Context
The owner wants to create commands with the help of an AI chat (ChatGPT, Claude.ai,
Gemini…) that has no access to the machine, unlike terminal agents that can read
`AGENTS.md` and the code. Such an AI needs one document it can be given: how to answer
(step by step, `mu self new …` then the files), the user's setup (root name, paths) and the
full plugin contract. The main risk of such a document is to drift from the framework.

## Decision
`mu self guide [-o file] [--no-commands]` prints a Markdown guide generated at run time:

- `templates/ai-guide.md` holds only what is specific to the AI: how to answer, the rules,
  a worked example. Placeholders (`__CB_NAME__`, `__CB_ROOT__`, `__CB_BASH__`, `__CB_SYSTEM__`, and the
  line placeholders `__CB_COMMANDS__`, `__CB_SELF_NEW_HELP__`, `__CB_REFERENCE__`) are
  filled by `builtin/self/guide/cmd.sh`.
- The reference is **not duplicated**: it is the part of `docs/plugin-authoring.md`
  between `<!-- guide:begin -->` and `<!-- guide:end -->`, read at run time. The help of
  `self new` and the list of existing commands come from the live installation.
- Default answer format asked from the AI: blocks ready to paste (`cat > '<abs path>'
  <<'EOF'`); plain file contents only if the user asks. The list of the user's commands is
  included by default (to avoid name conflicts) and can be left out with `--no-commands`,
  since the guide is sent to an external service.
- `-o` on an existing file asks for confirmation (rule 5); without a terminal it refuses.
- The guide gives the system (`uname -sr`, WSL and macOS flagged) and tells the AI to
  assume nothing else about the machine, to write for that system (portable only on
  request), never to suggest `sudo <name> …` (root has no `~/.local/bin` in its PATH; use
  `sudo` inside `cmd.sh` for the one tool that needs it), and to write the files' texts in
  **English** unless the user explicitly asks for another language (the conversation
  itself stays in the user's language). Owner choices, after a test with a small model.
- Evaluated on 2026-11-08 with 10 sub-agents (8 Haiku, 2 Sonnet, see `docs/testing.md`):
  every generated command worked; the guide then gained rules against shadowing an
  official plugin, for `--sudo` as an option when root only adds details, on completion
  working at once, and against checking standard tools or writing `--default 0` on bools.
  A re-run showed `--core` chosen to keep `mu system uptime`: the guide now makes a user
  plugin with another name the default and `--core` only an explained alternative.
- Second evaluation, 2026-11-08, 10 sub-agents (8 Haiku, 2 Sonnet): 5 Spring JPA entity
  generators run against real PostgreSQL 17 and MariaDB 11.8 (every entity compiled with
  `javac`), plus HTTP checks, logs, env profiles, git standup, CSV stats: all worked. Found:
  a `--help` example using undeclared flags, a sample config missing an engine offered by the
  command, and a date-boundary bug no test step would reveal. The guide now requires
  examples to use declared flags only, settings files under `$CB_CONFIG_DIR` covering every
  choice (`chmod 600` with secrets), and an edge case in the *Try it* step.
- When the request is unclear or leaves grey areas (name, inputs, behaviour, output,
  destructive actions, external tools), the AI must **ask questions first**, all at once,
  each with a suggested default, and only then give the guide; a clear request gets the
  guide directly. (Owner request: guide the user rather than guess.)

Kept up to date by tests:
- the generated guide must mention every DSL keyword and option, `CB_*` variable and `ui::`
  helper (same extraction as the doc checks, `contract_checks` in `tests/run.sh`);
- the bash blocks of the worked example are **extracted from the generated guide and run**
  in the sandbox: the command must be created and print the expected output;
- the complete `flags.sh` example of `docs/plugin-authoring.md` (between `flags-example`
  markers) is installed and run: `cmd.sh` must receive exactly the values documented
  between the `flags-values` markers;
- the markers must stay in `docs/plugin-authoring.md`.

## Amendment (2026-11-09, global review)

The review found that the paste format could destroy or run user code, and the guide's
signature here was outdated (`mu self guide [request] [-o file] [--no-commands]`;
extensions replaced the "another plugin name" advice, decision 0013). Now:

- Delimiter `<<'CB_EOF'`, never `EOF`: a generated file with its own `EOF` heredoc ended
  the paste early and the rest ran in the user's interactive shell.
- Every file block of a new command starts with a guard on the placeholder written by
  `self new` (`grep -q 'Hello from' '<cmd.sh>' &&`, `grep -q 'TODO: describe' ...` for a
  new parent), `cmd.sh` last: when `self new` refuses an existing command, nothing is
  overwritten. The user is told to stop on a line starting with ✗. A test pastes the worked
  example again over an existing command.
- "Try it" runs never change real data (`--dry-run`, `mktemp -d`, no `--yes`, nothing in
  the home directory): an evaluated answer deleted a real note.
- Setup gains the distribution (`/etc/os-release`), the configured package managers and the
  absolute config directory; WSL gets a short note (Windows openers, clipboard, its own
  read-only mounts in `df`). The owner's condition: the guide must not encourage extra
  dependencies; a tool that is really needed is declared with `requires`.
- The embedded reference's headings are one level below the guide's sections.

## Alternatives considered
- *The guide in French or other languages* (roadmap idea): rejected by the owner, the
  guide stays in English and the AI talks in the user's language.
- *A hand-written, standalone guide*: duplicates `plugin-authoring.md`, drifts silently.
- *Ship `AGENTS.md` / the whole `docs/`*: written for contributors of the framework, not for
  helping a user write a plugin; too long and off-topic.
- *Copy to the clipboard*: needs `xclip`, `pbcopy`, `clip.exe`… (rule 1: no dependencies).
  Stdout and `-o` cover it (`mu self guide | clip.exe` stays possible).
- *Commands list left out by default*: safer for privacy, but the AI would then propose
  names that already exist. The owner chose "included, `--no-commands` to leave out".

## Consequences
`docs/plugin-authoring.md` is now read at run time: it ships with the install (it already
did, the install is a git checkout) and the test sandbox copies it. Text between the
markers must stay self-contained (no relative links). Changing the plugin contract or
`self new` may require updating the worked example or the rules of `templates/ai-guide.md`;
the executed example fails if they no longer work.
