# user.torrent — download and stream torrents from the Omarchy bar

Bar widget + engine service. Downloads run in a per-user `transmission-daemon`
(transient systemd unit `omarchy-torrent-daemon`, config in
`~/.local/state/omarchy-torrent/daemon/`, RPC bound to 127.0.0.1 only, no auth).
Media files can be played while they download.

## Using it

- **Bar icon**: magnet glyph; turns into a download glyph with the live speed and
  one dot per active download. Left click = panel, right click = refresh,
  middle click = add the magnet link currently in the clipboard.
- **Keybinding**: `SUPER + ALT + T` toggles the panel (in `~/.config/hypr/bindings.lua`).
- **Adding**: paste a magnet link / `.torrent` URL / local path into the field and
  press Enter, click the file button to pick a `.torrent`, or just click a magnet
  link in the browser (the plugin registers itself as the `magnet:` and
  `application/x-bittorrent` handler). When the panel opens with a magnet link
  in the clipboard it offers to add it.
- **Streaming**: the ▶ button on a torrent plays its largest video/audio file;
  unfold a torrent (chevron / `f`) to play a specific file. Playback starts as
  soon as the first pieces arrive and seeking jumps the download ahead.
- **Keys in the panel**: `↑↓` move · `Enter`/`Space` play · `s` pause/resume ·
  `f` files · `q` sequential on/off · `w` want/skip file · `o` folder ·
  `x` remove (keep files) · `X X` remove and delete files · `a` add field ·
  `p` add clipboard · `O` pick .torrent · `r` refresh · `Esc` close.
- **Power button** in the panel title stops/starts the daemon.

## Settings (`shell.json` entry, hot-reloaded)

| key | default | meaning |
|---|---|---|
| `downloadDir` | `~/Downloads/Torrents` | where files land (no `.part` renaming, no incomplete dir) |
| `rpcPort` | `9091` | Transmission RPC port on localhost |
| `seedRatioLimit` | `2.0` | stop seeding at this ratio, `0` = seed forever |
| `player` | `mpv` | player command for streams; mpv gets cache/timeout flags, others just the URL |
| `pollSeconds` | `4` | refresh interval while the panel is closed (1 s while open) |
| `showSpeedInBar` | `true` | speed label beside the bar icon while downloading |
| `handleMagnetLinks` | `true` | register the xdg handler on shell start |

## How streaming works

`bin/omarchy-torrent stream <id> <file>` starts `omarchy-torrent-stream-<id>-<file>`,
a systemd user unit running a local HTTP range server over the file in the
download folder. It switches the torrent to sequential download, marks the file
wanted/high priority, and for every 1 MiB chunk requested it waits until the
covering pieces are reported present in Transmission's `pieces` bitfield before
reading from disk. A `Range` request past the current frontier sets
`sequential_download_from_piece`, so seeks (and mp4 files with the index at the
end) are fetched next. The player is launched against `http://127.0.0.1:<port>/<name>`;
when it exits the server lingers 20 s (a replay reuses it) and then stops.

## CLI / IPC

```
omarchy-torrent status|add <src>|pause <id>|resume <id>|remove <id> [--data]|
                stream <id> <file>|stop-stream <id> [file]|open <id>|daemon start|stop|restart
omarchy-shell user.torrent add "<magnet>" | list | stream <id> [file] | pause <id> | resume <id> | rescan
transmission-remote -l            # the stock CLI talks to the same daemon
```

Logs: `~/.local/state/omarchy-torrent/logs/{daemon,stream-<id>-<file>}.log`.
