host=$(hostname 2>/dev/null || uname -n)
os=$(uname -s)
kernel=$(uname -r)
up=$(uptime 2>/dev/null | sed -E 's/.*up +([^,]*),.*/\1/')

if [[ $FLAG_SHORT == 1 ]]; then
  printf '%s · %s %s · up %s\n' "$host" "$os" "$kernel" "$up"
  exit 0
fi

ui::title "System"
printf '  %-8s %s\n' Machine "$host" OS "$os" Kernel "$kernel" Uptime "$up" Shell "${SHELL##*/}"
