#!/usr/bin/env bash
# All tests: ./tests/run.sh          (end-to-end + doc consistency)
#            ./tests/run.sh --docs   (doc consistency only)
# End-to-end tests work on a copy of the project, with an isolated HOME.
# See docs/testing.md.

ROOT=$(cd -P "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
only_docs=0
[[ ${1:-} == --docs ]] && only_docs=1

pass=0 fail=0
check() { # description, command, substring expected in the output (stdout+stderr)
  local out
  out=$(eval "$2" 2>&1)
  if [[ $out == *"$3"* ]]; then
    ((pass++))
  else
    ((fail++))
    printf '✖ %s\n    command : %s\n    expected: %s\n    got     : %s\n' "$1" "$2" "$3" "${out//$'\n'/$'\n'              }"
  fi
}
status() { eval "$1" >/dev/null 2>&1; echo $?; }

# need <fact description> <file> <literal text that must appear in the file>
# (file relative to the repository, or absolute)
need() {
  local f=$2
  [[ $f == /* ]] || f=$ROOT/$f
  if grep -qF -- "$3" "$f" 2>/dev/null; then
    ((pass++))
  else
    ((fail++))
    printf '✖ docs: %s is not documented in %s (expected to find: %s)\n' "$1" "$2" "$3"
  fi
}

# ---------------------------------------------------------------------------
# Doc consistency: facts extracted from the code must be mentioned in the docs.
# When a check fails, document the new thing — do not weaken the check.
# ---------------------------------------------------------------------------
# contract_checks <file>: the plugin contract extracted from the code (DSL keywords and
# options, CB_* variables, ui:: helpers) is fully described in <file>. Used for
# docs/plugin-authoring.md and for the guide printed by "self guide".
contract_checks() {
  local file=$1 kw opt v h
  # DSL keywords: top-level functions of lib/spec.sh (about, flag, arg…).
  for kw in $(grep -oE '^[a-z]+\(\)' "$ROOT/lib/spec.sh" | tr -d '()'); do
    need "DSL keyword '$kw'" "$file" "\`$kw"
  done

  # DSL options: case patterns of lib/spec.sh (--default, --choices-from…).
  for opt in $(grep -E '^ +--[a-z-]+( \| --[a-z-]+)*\)' "$ROOT/lib/spec.sh" | grep -oE -- '--[a-z-]+' | sort -u); do
    need "DSL option '$opt'" "$file" "\`$opt"
  done

  # Public CB_* variables exported to commands.
  for v in $(grep -hE '^ *export ' "$ROOT/main.sh" "$ROOT/lib/router.sh" | grep -oE '(^|[^_A-Za-z])CB_[A-Z_]+' | grep -oE 'CB_[A-Z_]+' | sort -u); do
    need "variable $v" "$file" "\`$v\`"
  done

  # ui:: helpers.
  for h in $(grep -oE '^ui::[a-z_]+' "$ROOT/lib/ui.sh" | sort -u); do
    need "helper $h" "$file" "\`$h"
  done
}

doc_checks() {
  local d cmd k f md dir link
  cd "$ROOT" || return 1
  contract_checks docs/plugin-authoring.md
  # The part of it embedded in the guide of "self guide".
  need "guide:begin marker" docs/plugin-authoring.md "<!-- guide:begin -->"
  need "guide:end marker" docs/plugin-authoring.md "<!-- guide:end -->"
  need "flags-example markers" docs/plugin-authoring.md "<!-- flags-example:begin -->"
  need "flags-values markers" docs/plugin-authoring.md "<!-- flags-values:begin -->"

  # Built-in self commands.
  while IFS= read -r d; do
    [[ -f $d/flags.sh || -f $d/cmd.sh || -f $d/cmd ]] || continue
    cmd=${d#builtin/}
    cmd=${cmd//\// }
    need "command '$cmd'" docs/architecture.md "$cmd"
    need "command '$cmd'" README.md "$cmd"
  done < <(find builtin/self -mindepth 1 -type d ! -name '_*' | sort)

  # Config directives (case labels of cb::config_load).
  for k in $(sed -n '/^cb::config_load()/,/^}/p' lib/config.sh | grep -oE '^ +[a-z]+\)$' | tr -d ' )'); do
    need "config directive '$k'" docs/architecture.md "$k "
    need "config directive '$k'" README.md "$k "
  done

  # Every lib file is described.
  for f in lib/*.sh; do
    need "file $f" docs/architecture.md "\`$f\`"
  done

  # Every decision record is indexed.
  for f in docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
    need "decision ${f##*/}" docs/decisions/README.md "(${f##*/})"
  done

  # Relative links point to existing files.
  while IFS= read -r md; do
    dir=$(dirname -- "$md")
    while IFS= read -r link; do
      link=${link#*](}
      link=${link%)}
      link=${link%%#*}
      [[ -z $link || $link == *://* || $link == mailto:* ]] && continue
      if [[ -e $dir/$link ]]; then
        ((pass++))
      else
        ((fail++))
        printf '✖ docs: broken link in %s: %s\n' "$md" "$link"
      fi
    done < <(grep -oE '\]\([^)]+\)' "$md")
  done < <(printf '%s\n' AGENTS.md .github/copilot-instructions.md docs/*.md docs/decisions/*.md)
  # Wrap-up marker of docs/handoff.md: present, and a real commit when git is available.
  need "wrap-up marker" docs/handoff.md "Last wrap-up commit: \`"
  local sha
  sha=$(grep -oE 'Last wrap-up commit: `[0-9a-f]+`' docs/handoff.md | grep -oE '[0-9a-f]{7,}')
  if [[ -n $sha ]] && git rev-parse --git-dir >/dev/null 2>&1; then
    if git cat-file -e "$sha^{commit}" 2>/dev/null; then
      ((pass++))
    else
      ((fail++))
      printf '✖ docs: docs/handoff.md references unknown commit %s\n' "$sha"
    fi
  fi
  cd - >/dev/null || return 1
}

summary() {
  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  ((fail == 0))
}

if ((only_docs)); then
  doc_checks
  summary
  exit
fi

# ---------------------------------------------------------------------------
# End-to-end tests
# ---------------------------------------------------------------------------
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/app" "$TMP/home/bin"
cp -R "$ROOT"/{main.sh,init.sh,lib,builtin,core,templates} "$TMP/app/"
mkdir -p "$TMP/app/plugins" "$TMP/app/docs"
cp "$ROOT/docs/plugin-authoring.md" "$TMP/app/docs/" # embedded by "self guide"
ln -s "$TMP/app/main.sh" "$TMP/home/bin/tt"
export HOME=$TMP/home XDG_CONFIG_HOME=$TMP/home/.config PATH=$TMP/home/bin:$PATH NO_COLOR=1
# Prompts (ui::confirm, ui::ask) must never wait on the real terminal: they read _CB_TTY.
export _CB_TTY=/dev/null

P=$TMP/app/plugins
mkdir -p "$P/demo/greet" "$P/demo/router/leaf"
cat >"$P/demo/flags.sh" <<'X'
about "Demo"
X
cat >"$P/demo/greet/flags.sh" <<'X'
about "Greets"
flag loud -l bool "Loud"
flag times -n int "Times" --default 1
flag lang string "Language" --choices "fr en" --default fr
flag key -k string "Key" --required
arg name "Name"
arg rest "Rest" --optional --variadic
X
cat >"$P/demo/greet/cmd.sh" <<'X'
echo "name=$ARG_NAME loud=$FLAG_LOUD times=$FLAG_TIMES lang=$FLAG_LANG key=$FLAG_KEY rest=[$ARG_REST] argc=$#"
X
echo 'about "Router"' >"$P/demo/router/flags.sh"
echo 'echo leaf' >"$P/demo/router/leaf/cmd.sh"
mkdir -p "$P/py" && printf '#!/bin/sh\necho "py flag=$FLAG_X args=$*"\n' >"$P/py/cmd" && chmod +x "$P/py/cmd"
printf '%s\n' 'flag x -x string "X"' 'arg args "Args" --optional --variadic' >"$P/py/flags.sh"

# Help and routing
check "root help lists plugins"            "tt"                         "demo"
check "root help lists self"               "tt --help"                  "self"
check "router without cmd shows help"      "tt demo"                    "greet"
check "generated help: usage"              "tt demo greet -h"           "tt demo greet [options] <name> [rest...]"
check "generated help: choices"            "tt demo greet --help"       "--lang <fr|en>"
check "generated help: default"            "tt demo greet --help"       "(default: 1)"
check "unknown command + suggestion"       "tt dem"                     "Did you mean: demo"
check "unknown subcommand"                 "tt demo gret"               "Did you mean: greet"
check "deep nesting"                       "tt demo router leaf"        "leaf"
check "non-bash executable"                "tt py -x 1 a b"             "py flag=1 args=a b"

# Parsing
check "default values"                     "tt demo greet -k K Bob"     "name=Bob loud=0 times=1 lang=fr key=K rest=[] argc=1"
check "grouped shorts + attached value"    "tt demo greet -lkK -n3 Bob" "loud=1 times=3"
check "--x=val and variadic"               "tt demo greet --key=K Bob a b" "rest=[a b] argc=3"
check "options after arguments"            "tt demo greet Bob -k K -l"  "loud=1"
check "--no-flag"                          "tt demo greet -l --no-loud -k K Bob" "loud=0"
check "end of options --"                  "tt demo greet -k K Bob -- -l" "rest=[-l]"
check "required flag"                      "tt demo greet Bob"          "--key is required"
check "missing argument"                   "tt demo greet -k K"         "missing argument: <name>"
check "invalid integer"                    "tt demo greet -k K -n x Bob" "expects an integer"
check "invalid choice"                     "tt demo greet -k K --lang de Bob" "choices: fr, en"
check "unknown option"                     "tt demo greet --nope"       "unknown option '--nope'"
check "error exit code = 2"                "status 'tt demo greet'"     "2"

# Invalid spec
mkdir -p "$P/bad" && echo 'flag x badtype "X"' >"$P/bad/flags.sh" && echo 'echo' >"$P/bad/cmd.sh"
check "spec error with location"           "tt bad"                     "flags.sh:1: unknown type 'badtype'"
check "doctor detects the invalid spec"    "tt self doctor"             "unknown type 'badtype'"
rm -rf "$P/bad"

# Conflicts, disabling, renaming
mkdir -p "$P/system" && echo 'echo mine' >"$P/system/cmd.sh"
check "user shadows core"                  "tt system"                  "mine"
check "conflict reported"                  "tt self plugins"            "shadowed by user:system"
check "ambiguous name"                     "tt self plugins disable system" "ambiguous"
check "disabling"                          "tt self plugins disable user:system" "disabled"
check "core visible again"                 "tt system info -s"          "·"
check "rename keeps the core plugin"       "tt self plugins enable user:system; echo 'rename core:system sys' >>\$XDG_CONFIG_HOME/tt/config; tt sys info -s" "·"
check "both coexist"                       "tt system"                  "mine"
rm -rf "$P/system"

# Generator
check "self new creates the command"       "tt self new gen sub -a 'My subcommand'" "created"
check "generated command runs"             "tt gen sub"                 "Hello from 'tt gen sub'"
check "about shown in help"                "tt gen --help"              "My subcommand"
check "refused if it already exists"       "tt self new gen sub"        "already has an executable"
check "self is reserved"                   "tt self new self"           "reserved"

# Guide for AI assistants (self guide)
G=$TMP/guide.md
tt self guide >"$G" 2>&1
check "guide: root name substituted"       "head -1 '$G'"               "creating a \`tt\` command"
check "guide: install path substituted"    "cat '$G'"                   "| User commands | \`$TMP/app/plugins/\` |"
check "guide: no placeholder left"         "grep -c '__CB_' '$G'"       "0"
check "guide: lists commands"              "cat '$G'"                   "- \`tt demo greet\` (command, \`plugins/demo/greet/\`): Greets"
check "guide: lists groups"                "cat '$G'"                   "- \`tt demo router\` (group, \`plugins/demo/router/\`): Router"
check "guide: plugin ids and states"       "cat '$G'"                   "### Plugin \`demo\` (id \`user:demo\`, active)"
check "guide: renamed plugin"             "cat '$G'"                   "- \`tt sys info\` (command, \`core/system/info/\`)"
check "guide: help of self new"            "cat '$G'"                   "tt self new [options] <path...>"
check "guide: ask when unclear"            "cat '$G'"                   "**ask questions first**"
check "guide: system of the machine"       "cat '$G'"                   "| System | $(uname -sr)"
check "guide: help texts in English"       "cat '$G'"                   "write everything that goes into the files in"
check "guide: no sudo of the root command" "cat '$G'"                   "Never tell the user to run \`sudo tt ...\`"
check "guide: official plugins not shadowed" "cat '$G'"                  "would **shadow** it, and all its commands"
check "guide: examples use declared flags"  "cat '$G'"                  "must only use the flags and arguments"
check "guide: edge case in Try it"        "cat '$G'"                  "edge case of the logic"
check "guide: settings in CB_CONFIG_DIR"   "cat '$G'"                  "a file under \`\$CB_CONFIG_DIR\` (that is \`~/.config/tt\`)"
check "guide: --no-commands"               "tt self guide --no-commands | grep -c 'plugins/demo/greet/'" "0"
check "guide: --no-commands says so"       "tt self guide --no-commands" "Not shared by the user"
check "guide: reference embedded"          "cat '$G'"                   "## \`flags.sh\` DSL"
check "guide: reference markers stripped"  "grep -c 'guide:begin' '$G'" "0"
# The guide describes the whole plugin contract, like docs/plugin-authoring.md.
contract_checks "$G"
# The worked example of the guide really works: its bash blocks are run as they are.
sed -n '/<!-- example:begin -->/,/<!-- example:end -->/p' "$G" |
  awk '/^```bash$/ { f = 1; next } /^```$/ { f = 0 } f' >"$TMP/example.sh"
check "guide example: uses self new"       "cat '$TMP/example.sh'"     "tt self new test hello"
bash "$TMP/example.sh" >"$TMP/example.out" 2>&1
check "guide example: skeleton created"    "cat '$TMP/example.out'"    "Command 'tt test hello' created"
check "guide example: generated usage"     "cat '$TMP/example.out'"    "tt test hello [options] [name]"
check "guide example: generated help"      "cat '$TMP/example.out'"    "name  Who to greet (default: world) (optional)"
check "guide example: default output"      "grep -cx 'Hello, world!' '$TMP/example.out'" "1"
check "guide example: flags output"        "grep -cx 'HELLO, ALICE!' '$TMP/example.out'" "1"
check "guide example: parent described"    "tt --help"                 "Test commands"
check "guide example: doctor is happy"     "tt self doctor | grep -c 'plugins/test'" "0"
rm -rf "$P/test" "$TMP/example.sh" "$TMP/example.out"
# The complete flags.sh example of the reference (as embedded in the guide) is valid, and
# cmd.sh receives exactly the values it documents.
check "guide: required and optional fields" "cat '$G'"                  "### Required and optional fields"
mkdir -p "$P/backup/db/restore"
echo 'about "Backups"' >"$P/backup/flags.sh"
echo 'about "Databases"' >"$P/backup/db/flags.sh"
sed -n '/<!-- flags-example:begin -->/,/<!-- flags-example:end -->/p' "$G" |
  awk '/^```/ { f = !f; next } f' >"$P/backup/db/restore/flags.sh"
sed -n '/<!-- flags-values:begin -->/,/<!-- flags-values:end -->/p' "$G" |
  awk '/^```/ { f = !f; next } f' >"$TMP/values.expected"
cat >"$P/backup/db/restore/cmd.sh" <<'X'
for v in VERBOSE YES FORMAT JOBS TOKEN HOST; do n=FLAG_$v; echo "$n=${!n}"; done
for v in DB DUMP TABLES; do n=ARG_$v; echo "$n=${!n}"; done
echo "\$@=$*"
X
check "flags example: extracted"           "grep -c '^flag ' '$P/backup/db/restore/flags.sh'" "6"
check "flags example: valid for doctor"    "tt self doctor | grep -c 'backup'" "0"
check "flags example: generated help"      "tt backup db restore --help" "--format <sql|csv>  Dump format (default: sql)"
check "flags example: dynamic choices"     "tt __complete -- backup db restore --host ''" $'db1\tPrimary'
check "flags example: documented values"   "tt backup db restore prod dump.sql users orders --token T -v | diff '$TMP/values.expected' - && echo same" "same"
check "flags example: --token required"    "tt backup db restore prod" "--token is required"
rm -rf "$P/backup" "$TMP/values.expected"
# -o: written to a file; an existing file is overwritten only after confirmation
check "guide -o: written"                  "tt self guide -o '$TMP/g.md'" "Guide written to $TMP/g.md"
check "guide -o: same content as stdout"   "diff '$G' '$TMP/g.md' && echo same" "same"
echo keep >"$TMP/g.md"
check "guide -o: no terminal = not overwritten" "tt self guide -o '$TMP/g.md'; cat '$TMP/g.md'" "keep"
check "guide -o: refusal exit code"        "status \"tt self guide -o '$TMP/g.md'\"" "1"
echo y >"$TMP/yes"
check "guide -o: overwritten after yes"    "_CB_TTY='$TMP/yes' tt self guide -o '$TMP/g.md' >/dev/null 2>&1; head -1 '$TMP/g.md'" "# Guide for AI assistants"
rm -f "$TMP/g.md" "$TMP/yes"
# Missing reference: clear error, nothing printed half-way
mv "$TMP/app/docs/plugin-authoring.md" "$TMP/pa.md"
check "guide: missing reference"           "tt self guide"              "cannot read the reference"
grep -v 'guide:begin' "$TMP/pa.md" >"$TMP/app/docs/plugin-authoring.md"
check "guide: reference without markers"   "tt self guide | grep -c '^# Guide'" "0"
mv "$TMP/pa.md" "$TMP/app/docs/plugin-authoring.md"
rm -f "$G"

# Completion
check "root completion"                   "tt __complete -- ''"        "demo"
check "subcommand completion"              "tt __complete -- demo ''"   "greet"
check "flag completion"                    "tt __complete -- demo greet --l" "--loud"
check "flag choices completion"            "tt __complete -- demo greet --lang ''" "en"
check "argument choices completion"        "tt __complete -- self completion ''" "zsh"
check "generated bash script"              "tt self completion bash"    "complete -o default -F _cb_complete_tt tt"

# Dynamic choices (--choices-from)
mkdir -p "$P/dyn" "$TMP/work"
touch "$TMP/work/alpha.txt" "$TMP/work/beta.txt"
printf 'one\ttwo\n' >"$P/dyn/_values"
cat >"$P/dyn/flags.sh" <<'X'
about "Dynamic choices"
_dyn_envs() { printf '%s\t%s\n' dev "Development" prod "Production"; }
flag env  -e string "Environment" --choices-from _dyn_envs --strict
flag file    string "File of the current directory" --choices-from "ls *.txt"
arg  item          "Item" --choices-from 'tr "\t" "\n" < "$CB_COMMAND_DIR/_values"' --strict
X
echo 'echo "env=$FLAG_ENV file=$FLAG_FILE item=$ARG_ITEM"' >"$P/dyn/cmd.sh"
check "dyn: flags.sh function + descriptions" "tt __complete -- dyn --env ''" $'prod\tProduction'
check "dyn: prefix filtering"             "tt __complete -- dyn -e d | wc -l"  "1"
check "dyn: evaluated in the current dir" "cd '$TMP/work' && tt __complete -- dyn --file ''" "beta.txt"
check "dyn: CB_COMMAND_DIR available"     "tt __complete -- dyn ''"      "two"
check "dyn: --strict validates"           "tt dyn -e staging one"        "invalid value 'staging' (choices: dev, prod)"
check "dyn: --strict accepts"             "tt dyn -e prod two"           "env=prod file= item=two"
check "dyn: non strict = free"            "tt dyn --file other.txt one"  "file=other.txt"
check "dyn: strict arg"                   "tt dyn three"                 "<item>: invalid value 'three' (choices: one, two)"
check "dyn: help"                         "tt dyn --help"                "Tab for possible values"
echo 'flag x string "X" --choices "a" --choices-from "echo b"' >"$P/dyn/flags.sh"
check "dyn: exclusive with --choices"     "tt dyn"                       "flags.sh:1: --x: --choices and --choices-from are mutually exclusive"
echo 'arg x "X" --strict' >"$P/dyn/flags.sh"
check "dyn: --strict alone refused"       "tt dyn"                       "--strict can only be used with --choices-from"
rm -rf "$P/dyn"
mkdir -p "$P/sysx" && echo 'about "Sys X"' >"$P/sysx/flags.sh" && echo 'echo' >"$P/sysx/cmd.sh"
check "plugins disable: dynamic list"     "tt __complete -- self plugins disable ''" $'user:sysx\tSys X'
tt self plugins disable user:sysx >/dev/null 2>&1
check "plugins enable: only disabled ones" "tt __complete -- self plugins enable ''" "user:sysx"
check "plugins enable: not the active ones" "tt __complete -- self plugins enable '' | grep -c core:system" "0"
tt self plugins enable user:sysx >/dev/null 2>&1
check "bash: 'core:sy' completed despite the ':'" \
  "bash -c 'source <(tt self completion bash); COMP_LINE=\"tt self plugins disable core:sy\"; COMP_POINT=\${#COMP_LINE}; COMP_WORDBREAKS=\$\" \\t\\n\\\"\\x27><=;|&(:\"; _cb_complete_tt; printf \"[%s]\" \"\${COMPREPLY[@]}\"'" \
  "[system]"
rm -rf "$P/sysx"

# Bash adapter run as in an interactive shell: bashcomp "<shopt options>" "<command line>"
cat >"$TMP/bashcomp.sh" <<'X'
[[ -n $1 ]] && shopt -s $1
source <(tt self completion bash)
COMP_LINE=$2 COMP_POINT=${#2}
COMP_WORDBREAKS=$' \t\n"\'><=;|&(:'
_cb_complete_tt
printf '[%s]' "${COMPREPLY[@]}"
X
bashcomp() { bash "$TMP/bashcomp.sh" "$@"; }

# Completion: glob characters in candidates (nullglob / failglob)
mkdir -p "$P/globby/restore" && echo 'about "Glob"' >"$P/globby/flags.sh"
echo 'about "Restore a database [experimental]?"' >"$P/globby/restore/flags.sh"
echo 'echo' >"$P/globby/restore/cmd.sh"
check "bash: candidates kept under nullglob" "bashcomp nullglob 'tt globby '" "[restore]"
check "bash: candidates kept under failglob" "bashcomp failglob 'tt globby '" "[restore]"
rm -rf "$P/globby"

# Completion: attached value --flag=<TAB>
check "flag=value completion"              "tt __complete -- demo greet --lang="  "--lang=en"
check "flag=value: prefix filtering"       "tt __complete -- demo greet --lang=f | wc -l" "1"
check "flag=value: bool flag has no value" "tt __complete -- demo greet --loud= | wc -l" "0"
check "bash: flag=value completed"         "bashcomp '' 'tt demo greet --lang=e'" "[en]"

# Completion: a negative number is a positional, as for the parser
mkdir -p "$P/neg"
printf '%s\n' 'arg count "Count"' 'arg unit "Unit" --choices "kb mb"' >"$P/neg/flags.sh"
echo 'echo "count=$ARG_COUNT unit=$ARG_UNIT"' >"$P/neg/cmd.sh"
check "parser: negative number positional" "tt neg -5 kb"                  "count=-5 unit=kb"
check "completion: after a negative number" "tt __complete -- neg -5 ''"   "kb"
rm -rf "$P/neg"

# doctor: the status of the last command of flags.sh does not matter
mkdir -p "$P/cond"
printf '%s\n' 'about "Conditional"' 'false && flag podman bool "Use podman"' >"$P/cond/flags.sh"
echo 'echo cond' >"$P/cond/cmd.sh"
check "doctor: flags.sh ending with a false test is valid" \
  "tt self doctor 2>&1 | grep -c 'cond.*flags.sh'" "0"
rm -rf "$P/cond"

# self new: a refused run writes nothing
mkdir -p "$P/bk" && echo 'echo bk' >"$P/bk/cmd.sh"
check "self new: refused on an existing cmd.sh" "tt self new bk"          "already has an executable"
check "self new: refused run wrote no flags.sh" "test -e '$P/bk/flags.sh'; echo \$?" "1"
check "self new: under an existing command"   "tt self new bk db"         "created"
check "self new: existing parent left as is"  "test -e '$P/bk/flags.sh'; echo \$?" "1"
rm -rf "$P/bk"

# Config kept as a symlink (dotfiles)
cfg=$XDG_CONFIG_HOME/tt/config
mv "$cfg" "$TMP/dotconfig" && ln -s "$TMP/dotconfig" "$cfg"
tt self plugins disable core:system >/dev/null 2>&1
check "config symlink: still a symlink"       "test -L '$cfg'; echo \$?"  "0"
check "config symlink: target updated"        "cat '$TMP/dotconfig'"      "disable core:system"
tt self plugins enable core:system >/dev/null 2>&1
rm -f "$cfg" && mv "$TMP/dotconfig" "$cfg"

# Bash version guard (the framework needs Bash >= 4.2)
check "main.sh refuses Bash 4.1"  "bash -c 'BASH_VERSION=4.1.17; source \"\$0\"' '$TMP/app/main.sh'" "requires Bash >= 4.2"
check "init.sh refuses Bash 4.1"  "bash -c 'BASH_VERSION=4.1.17; source \"\$0\"' '$TMP/app/init.sh'" "requires Bash >= 4.2"

# init.sh without a name: usage, nothing touched
mkdir -p "$XDG_CONFIG_HOME" && echo keep >"$XDG_CONFIG_HOME/completion.bash"
check "init.sh without name: usage"           "bash '$TMP/app/init.sh'"   "Usage:"
check "init.sh without name: exit 2"          "status \"bash '$TMP/app/init.sh'\"" "2"
check "init.sh --uninstall without name: usage" "bash '$TMP/app/init.sh' --uninstall" "Usage:"
check "init.sh without name: nothing touched" \
  "cat '$XDG_CONFIG_HOME/completion.bash'; test -e '$HOME/.local/bin/cmd-builder' || echo no-link" $'keep\nno-link'
rm -f "$XDG_CONFIG_HOME/completion.bash"

# init.sh --uninstall: rc block without its end marker is left untouched
printf '%s\n' 'alias a=1' '' '# >>> cmd-builder: zz >>>' 'export X=1' 'alias b=2' >"$HOME/.bashrc"
check "uninstall: missing end marker reported" "bash '$TMP/app/init.sh' --uninstall zz" "file left untouched"
check "uninstall: rc file kept intact"         "cat '$HOME/.bashrc'"      "alias b=2"
check "uninstall: incomplete = exit 1"         "status \"bash '$TMP/app/init.sh' --uninstall zz\"" "1"
printf '%s\n' 'alias a=1' '' '# >>> cmd-builder: zz >>>' 'export X=1' '# <<< cmd-builder: zz <<<' 'alias b=2' >"$HOME/.bashrc"
check "uninstall: complete block removed"      "bash '$TMP/app/init.sh' --uninstall zz >/dev/null 2>&1; cat '$HOME/.bashrc'" $'alias a=1\nalias b=2'
rm -f "$HOME/.bashrc"

# init.sh install: how to load completion in the current terminal
zzblock=$'# >>> cmd-builder: zz >>>\n# <<< cmd-builder: zz <<<'
printf '%s\n' "$zzblock" >"$HOME/.bashrc"
check "install: source hint for bash"          "SHELL=/bin/bash bash '$TMP/app/init.sh' zz" "source ~/.bashrc"
printf '%s\n' "$zzblock" >"$HOME/.zshrc"
check "install: source hint for the user's shell" "SHELL=/bin/zsh bash '$TMP/app/init.sh' zz" "source ~/.zshrc"
rm -f "$HOME/.bashrc" "$HOME/.zshrc"
check "install: no hint when no rc configured"  "SHELL=/bin/bash bash '$TMP/app/init.sh' zz | grep -c 'source '" "0"
bash "$TMP/app/init.sh" --uninstall zz >/dev/null 2>&1
rm -f "$HOME/.bashrc" "$HOME/.zshrc"

# Prompts: answers come from _CB_TTY, so the "yes" path is testable too
echo y >"$TMP/yes"
check "prompt: yes read from _CB_TTY"          "_CB_TTY='$TMP/yes' SHELL=/bin/bash bash '$TMP/app/init.sh' zz" "added to ~/.bashrc"
check "prompt: yes path wrote the rc block"    "cat '$HOME/.bashrc'"      "# >>> cmd-builder: zz >>>"
check "prompt: no terminal = no"               "bash '$TMP/app/init.sh' --uninstall zz" "configuration kept"
_CB_TTY=$TMP/yes bash "$TMP/app/init.sh" --uninstall zz >/dev/null 2>&1
check "prompt: yes removes the configuration"  "test -e '$XDG_CONFIG_HOME/zz'; echo \$?" "1"
rm -f "$HOME/.bashrc" "$HOME/.zshrc" "$TMP/yes"

# Repository language: no French left in code comments
check "code comments are in English" \
  "grep -rnE '^[[:space:]]*#.*( : |[àâçéèêëîïôûùüÿœ])' '$ROOT'/{lib,builtin,core,templates,main.sh,init.sh} | wc -l" "0"

# Doc consistency
doc_checks
summary
