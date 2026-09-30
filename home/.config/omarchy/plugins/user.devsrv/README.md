# user.devsrv — local dev servers in the Omarchy bar

A bar widget (right section, before the FLAC player) showing how many local
instances are up. Its panel lists every running instance and the ones that ran
before, so any of them is one click (or `Enter`) from running again.

```
manifest.json        kinds ["service","bar-widget"]
Engine.qml           the service: polls the scanner, runs actions, IPC target user.devsrv
Widget.qml           the bar button + KeyboardPanel (one per monitor)
Model.js             glyphs, time formatting, row flattening
bin/omarchy-devsrv   scan | start | stop | open | terminal | logs | url | forget | add
```

## What counts as an instance

Every process of yours that **listens on a TCP port** from a directory that looks
like a project (`package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `.git`,
`Makefile`, `docker-compose.yml`, …), plus well-known server binaries wherever
they run (`redis-server`, `postgres`, `mongod`, …). Steam, browsers and system
daemons are ignored.

**Docker** instances are listed too: each running Compose project is one row
(named after the project, folder = its working directory, ports = every
published host port, containers listed under the name) and each standalone
container is a row of its own. Rows are marked with a whale glyph. Docker is
talked to directly, or through `newgrp docker` when the shell process predates
your docker-group membership (no re-login needed).

The command shown is the **topmost ancestor in the same folder that is not a
shell** — so you see `npm run dev`, not the `sh -c vite` / `node` grandchild.
Whatever you started from a terminal is picked up automatically the next scan
and remembered in `~/.local/state/omarchy-devsrv/history.json`, together with
the environment variables that differed from your desktop session
(`NODE_OPTIONS`, `DOTENV_CONFIG_PATH`, `PORT`, a mise-adjusted `PATH`, …) so a
re-run reproduces the original.

## Using it

- **Bar icon**: left click opens the panel, right click rescans. The dots under it
  are one per running instance (max 6); the icon turns accent-coloured when > 0.
- **Running** rows: ports, uptime, and buttons for **browser** (first port),
  **folder** (Files), **terminal** (in the project folder), **log**, **restart**
  and **stop**.
- **Ran before** rows: last-seen time and **run again**, **folder**, **terminal**,
  **log**, **forget**.
- **Keys**: `↑/↓` or `j/k` move, `Enter` opens a running one in the browser /
  starts a stopped one, `s` stop, `R` restart, `o` folder, `t` terminal, `l` log,
  `x` forget, `r` rescan, `Esc` close, `Tab` next panel.
- **CLI**: `omarchy-shell shell toggle user.devsrv`,
  `omarchy-shell user.devsrv list|start <id>|stop <id>|rescan`, or the script
  directly: `~/.config/omarchy/plugins/user.devsrv/bin/omarchy-devsrv scan`.
  Remember a command without running it: `omarchy-devsrv add <folder> <cmd…>`.

## How start / stop work

- **Start** runs the remembered command as a transient systemd user unit
  `devsrv-<id>.service` (`bash -lc` in the project folder, with the remembered
  env), output appended to `~/.local/state/omarchy-devsrv/logs/<id>.log`. Units
  survive `omarchy restart shell` and plugin reloads.
- **Stop** stops the unit if there is one; for an instance started elsewhere
  (a terminal, an agent) it sends `SIGTERM` to the command and all its
  descendants, then `SIGKILL` after 6 s to whatever is left.
- **Restart** of a terminal-started instance re-runs it as a managed unit.
- **Docker**: run again = `docker compose -f … up -d` (or `docker start`), stop =
  `docker compose down` (or `docker stop`), log = `docker compose logs -f` in a
  terminal. Standalone containers have no folder, so folder/terminal are disabled.

## Settings (inline on the `user.devsrv` entry in `~/.config/omarchy/shell.json`)

| key | default | meaning |
|---|---|---|
| `pollSeconds` | `5` | rescan interval while the panel is closed (1.5 s while open) |
| `showDotsInBar` | `true` | show one dot per running instance under the icon |
| `historyLimit` | `30` | how many "ran before" rows to show |
