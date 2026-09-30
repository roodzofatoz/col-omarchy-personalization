# user.mouse

Bar widget for a wireless mouse: battery, DPI, polling rate, and a switch for
pointer acceleration. Sits in the bar's right section next to network,
bluetooth and audio.

## Interactions

| Action | Result |
|---|---|
| Left click | Open the popup |
| Right click | Toggle pointer acceleration |
| Middle click | Show/hide the battery percentage next to the bar icon |
| Hover | Tooltip: name, battery, DPI, acceleration state |

The popup shows battery level, a charge bar, the acceleration switch, and a
device readout (DPI, polling rate, firmware) with the on-device DPI stages,
active stage highlighted. Stages are read-only -- cycle them with the button
on the mouse.

Keyboard: an arrow key arms the cursor, then Enter toggles acceleration.
Enter alone does nothing, so the popup taking focus cannot flip the setting
by accident.

## Where the numbers come from

UPower does not see Razer mice, so `bin/omarchy-mouse-status` speaks the Razer
HID protocol directly: a 90-byte report written and read back as HID feature
report 0 on the device's control interface. No kernel module, no daemon, no
OpenRazer. Any other mouse falls back to UPower, which supplies battery only.

Two failure modes are handled explicitly, both found the hard way:

- **Concurrency.** The bar builds one widget instance per monitor, so a poll
  fires this script once per screen simultaneously. The control interface
  collides under that and all but one caller gets a failed status, which made
  the widget vanish on a multi-monitor setup. One process now takes an flock
  and the rest read a ~2.5s cache in `$XDG_RUNTIME_DIR`.
- **Sleep and timing.** An idle mouse answers the first report with status
  0x04 (timeout), and reading the reply too soon gets the same. Every command
  retries with a lengthening settle.

Battery is reported as 0 when the dongle is connected but the mouse is off;
that is shown as "asleep" rather than a flat battery.

## Access

`/dev/hidraw*` is root-only by default. `/etc/udev/rules.d/60-omarchy-mouse-hidraw.rules`
tags Razer HID nodes with `uaccess`, so systemd-logind grants an ACL to the
user on the active seat -- no group membership and no world-readable device.

```
KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="1532", TAG+="uaccess"
```

## Acceleration

This Hyprland runs the Lua config parser, which rejects `hyprctl keyword`
("keyword can't work with non-legacy parsers"), so `bin/omarchy-mouse-accel`
applies the change with `hyprctl eval` and `hl.config` instead. hyprctl exits
0 even when it rejects the call, so the reply text is checked.

Off is persisted as `~/.local/state/omarchy/toggles/hypr/mouse-no-accel.lua`,
which Omarchy sources on config load; on simply removes it. Verified to
survive `hyprctl reload` with no config errors.

```bash
bin/omarchy-mouse-accel get|on|off|toggle
```

## IPC

```bash
omarchy-shell user.mouse toggle       # popup
omarchy-shell user.mouse toggleAccel  # bind this to a key if you want
omarchy-shell user.mouse refresh
```

## Settings

`showPercentage` (bool) and `refreshIntervalSec` (int, default 120) on the
widget's `shell.json` entry, or via Setup > Plugins.

## Brand logo

The hero shows the mouse maker's logo instead of a battery glyph when the brand is
known: `logos/<brand>.svg` (simple-icons, CC0) for Razer, SteelSeries and Corsair,
tinted to the theme foreground (urgent colour when the battery is low, dimmed while
the mouse is asleep). The brand comes from the status script's `vendor` field
(Razer via HID, otherwise UPower's `vendor:` line) or the first word of the device
name; unknown brands keep the battery glyph. Logitech has no logo in simple-icons —
drop a `logos/logitech.svg` (24×24 viewBox, single path, no fill) and add
`logitech: "Logitech"` to `BRAND_LOGOS` in `Model.js` to enable it.
