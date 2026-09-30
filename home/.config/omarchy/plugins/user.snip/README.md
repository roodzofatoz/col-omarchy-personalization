# user.snip

Bar widget (bar centre, ✂) that drags a region of the screen straight onto the
clipboard, the way the Windows snipping tool does.

| Action | Result |
|---|---|
| Left click | Pick a region → clipboard |
| Right click | Pick a region → clipboard **and** a file in Pictures, with the editor notification |
| Click again while picking | Cancel |

While the picker is open Omarchy's own selection keys still work: `RETURN`
captures the window under the cursor, `CTRL+RETURN` the whole screen.

## Why it has its own capture script

`omarchy-capture-screenshot` runs `slurp` with no colour arguments, so slurp
uses its compiled-in defaults:

```c
#define BG_COLOR        0xFFFFFF40   /* white, 25% - everything OUTSIDE the selection */
#define BORDER_COLOR    0x000000FF
#define SELECTION_COLOR 0x00000000
```

That white wash is what made the screen go *lighter* while picking. Measured
on this machine, mean screen luminance went 0.071 → 0.304 with the stock
picker open.

`bin/omarchy-snip` passes colours instead, dimming the area outside the
selection with the theme's `darker_background` at 70% and outlining the
selection in the theme's `accent`. Same measurement: 0.070 → 0.038, i.e. the
screen darkens by about half instead of washing out. The selection itself
stays fully transparent so the region shows its true colours.

Colours are read from `~/.local/state/omarchy/current/theme/colors.toml` at
run time, so the overlay follows a theme switch with no changes here.

Everything else mirrors `omarchy-capture-region` on purpose: the screen is
frozen with `hyprpicker -r -z` first, hardware cursors are forced on while
`grim` runs so a software cursor is not baked into the image, and the
fullscreen/window marker files that Omarchy's slurp keybinds write are
honoured.

## Reverting

Delete this plugin directory, or point `snip()` in `Snip.qml` back at
`omarchy-capture-screenshot region copy`. The menu entry lives in
`~/.config/omarchy/extensions/omarchy-menu.jsonc` as `trigger.capture.snip`.
