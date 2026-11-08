# plugins/

Your personal plugins. This directory is ignored by the cmd-builder repository: each plugin
can have **its own git repository** (work, personal…), updated by `<name> self update`.

```bash
mu self new backup --git          # creates plugins/backup/ + git init
git clone git@github.com:me/my-cmds.git plugins/my-cmds   # or clone an existing plugin
```

A plugin with the same name as an official plugin (core/) shadows it. To keep both, rename
one of them in `~/.config/<name>/config`: `rename core:system core-system`.
