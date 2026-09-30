-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = "auto"

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Layout (positions are logical, i.e. post-scale, pixels):
--
--   DP-1 portrait     DP-2 landscape    HDMI-A-1 portrait
--   1440x2560         1920x1080         1080x1920
--   x: 0..1440        x: 1440..3360     x: 3360..4440
--
-- Vertically centred against the tallest display (DP-1, 2560 logical px).

-- Left: portrait, rotated 270deg (top of the panel faces right).
hl.monitor({ output = "DP-1", mode = "3840x2160@60", position = "0x0", scale = 1.5, transform = 3 })

-- Centre: primary, landscape.
hl.monitor({ output = "DP-2", mode = "1920x1080@239.76", position = "1440x740", scale = 1 })

-- Right: portrait, rotated 90deg (top of the panel faces left).
hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "3360x320", scale = 1, transform = 1 })

-- Per-monitor workspace sets ------------------------------------------------
--
-- Each monitor owns a block of ten workspace ids. The bar and the SUPER+<n>
-- keys address them as 1-10 via omarchy-monitor-workspace, so pressing 3 opens
-- a workspace on the monitor you are already on instead of pulling focus to
-- whichever display owns a global workspace 3.
--
-- Keep these bases in sync with ~/.config/omarchy/monitor-workspaces.json.
local workspace_blocks = {
  { output = "DP-1", base = 0 },      -- left:   workspaces 1-10
  { output = "DP-2", base = 10 },     -- centre: workspaces 11-20
  { output = "HDMI-A-1", base = 20 }, -- right:  workspaces 21-30
}

for _, block in ipairs(workspace_blocks) do
  for offset = 1, 10 do
    hl.workspace_rule({
      workspace = tostring(block.base + offset),
      monitor = block.output,
      -- Open each monitor on its own first workspace at login, rather than
      -- letting Hyprland hand out 1, 2, 3 across the three displays.
      default = offset == 1,
    })
  end
end
