# user.a75 — VGN A75 keyboard plugin

Configure the VGN A75 hall-effect keyboard from the Omarchy bar: trigger presets,
actuation and release points, rapid trigger and dead zones, globally or per key.
Firmware updates go through the vendor's web hub via a local helper (see below).

## Install

```bash
sudo install -m 644 ~/.config/omarchy/plugins/user.a75/udev/60-omarchy-a75-hidraw.rules /etc/udev/rules.d/
sudo udevadm control --reload
# then unplug and replug the keyboard
~/.config/omarchy/plugins/user.a75/bin/omarchy-a75 status
```

`status` must print `"present": true` and a firmware version before anything else works.

## State

Per-key trigger settings are kept in `~/.local/state/omarchy-a75/profile-<n>.json`
because the keyboard cannot report them back.

## Usage

- Bar: left click opens the panel, middle click cycles profiles, right click refreshes.
- Panel: choose a preset, or move the sliders and press Apply (all keys), or select
  keys in the grid first to apply only to them. Custom values tint the key. The bar
  at the top shows the live travel of whichever key is moving.
- CLI: `bin/omarchy-a75 status | preset <name> | profile <n> | rate <hz> | trigger ... | profile-state | depth ...`
  and `--dry-run` on `trigger` to print the report bytes.
- IPC: `omarchy-shell user.a75 open|close|toggle|refresh`, `omarchy-shell user.a75-engine status|profileState|depth|refresh|run 'a|b|c'`.
- QML edits need `omarchy restart shell`; the hot reload keeps a cached copy of this plugin.

## Firmware updates

The panel's "Open vendor hub" button builds the MonsGeek/Akko Linux driver once
(`~/.local/share/omarchy-a75/`), starts its gRPC server as the user unit
`omarchy-a75-hub`, and opens https://vgn.rongyuan.tech/ — VGN's own configurator,
which performs the update with the vendor's flashing logic. Updating erases the
keyboard's on-board settings; re-apply your profile from the panel afterwards.
Stop the helper with the panel button or `bin/omarchy-a75-hub stop`.

The hub opens in its own Chromium window (`~/.local/share/omarchy-a75/hub-profile`)
with a Windows user agent: the hub's app only renders when it detects Windows or
macOS, and stays blank on Linux otherwise.
