source "$CB_ROOT/lib/core.sh"

command -v git >/dev/null || ui::die "git not found"

repos=("$CB_ROOT")
for d in "$CB_ROOT"/plugins/*/; do
  d=${d%/}
  [[ -e $d/.git ]] && repos+=("$d")
done

# Subjects of the remote's commits are shown before asking: no control characters (an
# escape sequence in a subject could rewrite the terminal).
clean() { LC_ALL=C tr -d '\000-\010\013-\037\177'; }

available=0 updated=0 failed=0 skipped=0 root_updated=0
for repo in "${repos[@]}"; do
  if [[ $repo == "$CB_ROOT" ]]; then
    ui::title "$CB_NAME (core + official plugins)"
  else
    ui::title "plugin ${repo##*/}"
  fi

  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    ui::warn "not a git repository, skipped"
    ((skipped++))
    echo
    continue
  fi
  if ! upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
    ui::warn "no upstream branch, skipped"
    ((skipped++))
    echo
    continue
  fi
  if ! git -C "$repo" fetch --quiet 2>/dev/null; then
    ui::error "cannot reach the remote repository (network? permissions?)"
    ((failed++))
    echo
    continue
  fi

  behind=$(git -C "$repo" rev-list --count 'HEAD..@{u}')
  if ((behind == 0)); then
    ui::success "up to date"
    echo
    continue
  fi

  ((available++))
  ui::info "$behind new commit(s) on $upstream:"
  git -C "$repo" log --oneline --no-decorate -n 20 'HEAD..@{u}' | clean | sed 's/^/    /'
  ((behind > 20)) && echo "    …"

  if [[ $FLAG_CHECK == 1 ]]; then
    echo
    continue
  fi
  if ui::confirm "Update?" y; then
    if git -C "$repo" pull --ff-only --quiet; then
      ui::success "updated"
      ((updated++))
      [[ $repo == "$CB_ROOT" ]] && root_updated=1
    else
      ui::error "update failed (local changes or diverged history?)"
      ((failed++))
    fi
  else
    ui::info "skipped"
  fi
  echo
done

# The rest runs in a new process: after a pull of the main repository, this one still holds
# the old code, which must not be mixed with the new files (review of 2026-11-09, ROB-06).
"$BASH" -c '
  source "$CB_ROOT/lib/core.sh"
  source "$CB_ROOT/lib/deps.sh"
  (($1)) && cb::completion_install
  cb::config_load
  cb::plugins_load
  cb::deps_collect
  if ((${#_CB_DEP_TOOLS[@]})); then
    ui::info "Tools needed by your plugins (${_CB_DEP_TOOLS[*]}): update them with '"'"'$CB_NAME self deps update'"'"'"
  fi
' post-update "$root_updated"

# Exit codes: 0 everything done or up to date, 1 a repository could not be checked or
# updated, 10 (--check only) updates are available.
if ((failed)); then
  ui::error "$failed repository(ies) could not be checked or updated (see above)"
  exit 1
fi
if [[ $FLAG_CHECK == 1 ]]; then
  if ((available)); then
    ui::info "$available repository(ies) to update: run '$CB_NAME self update'"
    exit 10
  fi
elif ((available)); then
  ui::success "$updated/$available repository(ies) updated."
  exit 0
fi
if ((skipped)); then
  ui::success "Up to date ($skipped repository(ies) skipped, see above)."
else
  ui::success "Everything is up to date."
fi
