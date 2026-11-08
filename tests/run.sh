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
need() {
  if grep -qF -- "$3" "$ROOT/$2" 2>/dev/null; then
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
doc_checks() {
  local kw opt v h d cmd k f md dir link
  cd "$ROOT" || return 1
  # DSL keywords: top-level functions of lib/spec.sh (about, flag, arg…).
  for kw in $(grep -oE '^[a-z]+\(\)' lib/spec.sh | tr -d '()'); do
    need "DSL keyword '$kw'" docs/plugin-authoring.md "\`$kw"
  done

  # DSL options: case patterns of lib/spec.sh (--default, --choices-from…).
  for opt in $(grep -E '^ +--[a-z-]+( \| --[a-z-]+)*\)' lib/spec.sh | grep -oE -- '--[a-z-]+' | sort -u); do
    need "DSL option '$opt'" docs/plugin-authoring.md "\`$opt"
  done

  # Public CB_* variables exported to commands.
  for v in $(grep -hE '^ *export ' main.sh lib/router.sh | grep -oE '(^|[^_A-Za-z])CB_[A-Z_]+' | grep -oE 'CB_[A-Z_]+' | sort -u); do
    need "variable $v" docs/plugin-authoring.md "\`$v\`"
  done

  # ui:: helpers.
  for h in $(grep -oE '^ui::[a-z_]+' lib/ui.sh | sort -u); do
    need "helper $h" docs/plugin-authoring.md "\`$h"
  done

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
cp -R "$ROOT"/{main.sh,lib,builtin,core,templates} "$TMP/app/"
mkdir -p "$TMP/app/plugins"
ln -s "$TMP/app/main.sh" "$TMP/home/bin/tt"
export HOME=$TMP/home XDG_CONFIG_HOME=$TMP/home/.config PATH=$TMP/home/bin:$PATH NO_COLOR=1

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

# Completion
check "root completion"                    "tt __complete -- ''"        "demo"
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

# Doc consistency
doc_checks
summary
