source "$CB_ROOT/lib/core.sh"

command -v git >/dev/null || ui::die "git not found"

repos=("$CB_ROOT")
for d in "$CB_ROOT"/plugins/*/; do
  d=${d%/}
  [[ -e $d/.git ]] && repos+=("$d")
done

available=0 updated=0 root_updated=0
for repo in "${repos[@]}"; do
  if [[ $repo == "$CB_ROOT" ]]; then
    ui::title "$CB_NAME (core + official plugins)"
  else
    ui::title "plugin ${repo##*/}"
  fi

  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    ui::warn "not a git repository, skipped"
    echo
    continue
  fi
  if ! upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
    ui::warn "no upstream branch, skipped"
    echo
    continue
  fi
  if ! git -C "$repo" fetch --quiet 2>/dev/null; then
    ui::warn "cannot reach the remote repository (network? permissions?)"
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
  git -C "$repo" log --oneline --no-decorate -n 20 'HEAD..@{u}' | sed 's/^/    /'
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
    fi
  else
    ui::info "skipped"
  fi
  echo
done

((root_updated)) && cb::completion_install

if ((available == 0)); then
  ui::success "Everything is up to date."
elif [[ $FLAG_CHECK == 1 ]]; then
  ui::info "$available repository(ies) to update: run '$CB_NAME self update'"
else
  ui::success "$updated/$available repository(ies) updated."
fi
