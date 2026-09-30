# col-omarchy-personalization

Everything customized on my Omarchy (Arch + Hyprland) machine, plus a script to
put it onto another Omarchy install.

## Layout

```
home/     mirrors $HOME          (e.g. home/.config/omarchy/shell.json)
system/   mirrors /              (e.g. system/etc/udev/rules.d/...)
manifest.txt        which paths are tracked (read by both scripts)
rsync-exclude.txt   what never leaves the machine (.git, __pycache__, *.bak, ...)
sync.sh             machine → repo
apply.sh            repo → machine
lib.sh              shared helpers
```

## What is inside

- **Omarchy shell** — `shell.json` (bar layout, idle, notifications), `shell.toml`,
  `grid.json` + `monitor-workspaces.json` (window grid / per-monitor workspaces),
  the custom menu row in `extensions/omarchy-menu.jsonc`, and 13 user plugins:
  `user.bar`, `user.indicators`, `user.workspaces`, `user.notifications`,
  `user.gravity-field` (animated dot-field wallpaper overlay), `user.snip`,
  `user.gpu`, `user.mouse`, `user.a75` (VGN A75 keyboard), `user.bluetooth`
  (A2DP codec picker, LDAC quality, prefer hi-res on connect), `user.torrent`,
  `user.devsrv`, `user.flac`.
- **Hyprland** — `bindings.lua`, `monitors.lua`, `looknfeel.lua`, `autostart.lua`,
  `hyprland.lua` (only the files that differ from Omarchy's templates).
- **Scripts** — `~/.local/bin/omarchy-grid` and `omarchy-monitor-workspace`,
  which the keybindings depend on.
- **Terminals** — alacritty, foot, kitty, ghostty (font size 8, clipboard keys).
- **Neovim** — LazyVim starter plus custom Lua (remote clipboard, theme
  hot-reload, transparency).
- **Misc** — tmux, git config (no identity, no credentials), mimeapps,
  user-dirs, Firefox Wayland env, `.bash_profile`, 7 launchers, Avenir fonts.
- **Claude Code** — `settings.json`, hooks, theme, pilotfish roles, plugin and
  marketplace lists. No credentials, no memory.
- **udev** — hidraw access rules for the A75 keyboard and Razer mouse widgets
  (installed only with `--system`).

Not tracked on purpose: credentials of any kind, `~/.claude.json`, Claude memory,
the NTFS/Limine/Windows boot fixes, package lists, navidrome/mise/bun setup, the
`user.a75` vendor reference bundle.

## Apply on another Omarchy machine

```
git clone https://github.com/roodzofatoz/col-omarchy-personalization.git
cd col-omarchy-personalization
./apply.sh --dry-run          # see what would change
./apply.sh                    # user-level files; backs up existing ones first
./apply.sh --system           # also install the udev rules (sudo)
./apply.sh --skip-monitors    # keep Omarchy's monitor layout on a different display setup
```

Backups land in `~/.local/state/col-omarchy/backup-<timestamp>/`. The script
reloads Hyprland and restarts the Omarchy shell at the end (`--no-restart` to skip).

Things to review afterwards on different hardware:

- Monitor names `DP-1` / `DP-2` / `HDMI-A-1` in `monitors.lua`, `bindings.lua`
  (`workspace_bases`), `shell.json` (`hideOnMonitors`, `notifications.monitors`),
  `grid.json`, `monitor-workspaces.json`.
- `user.flac` in `shell.json` targets a Focal Bathys DAC and a music library path.
- Packages the config expects: `brave-bin`, `tidal-hifi-bin`, `transmission-cli`,
  `libldac`, `libfreeaptx`, `typora`, `docker`.

## Keep the repo current

```
./sync.sh                       # copy live files in, show git status
git diff                        # review
./sync.sh --commit "msg" --push # only when you mean it
```

`sync.sh` never commits or pushes on its own. The two plugins that have their own
git history on the source machine (`user.a75`, `user.bluetooth`) are stored
flattened here; their `.git` directories stay local.
