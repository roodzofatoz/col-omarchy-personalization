-- Keep only your personal keybinding overrides here. Add new bindings or
-- unbind defaults before replacing them.

-- See current bindings and descriptions:
--   omarchy menu keybindings --print

-- To disable every Omarchy default binding, set this in
-- ~/.config/hypr/hyprland.lua before require("default.hypr.omarchy"), then add
-- only the bindings you want below:
--   omarchy_default_bindings = false

-- To disable all preinstalled app/webapp bindings, set:
--   omarchy_preinstalled_bindings = false

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Change an existing binding by unbinding it first, then binding the key again.
-- This example changes SUPER+SPACE from the launcher to the Omarchy root menu.
-- hl.unbind("SUPER + SPACE")
-- o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle root")

-- Disable a default binding without replacing it.
-- hl.unbind("SUPER + SHIFT + B")

-- --------------------------------------------------------------- snip tool
--
-- SUPER+SHIFT+S is bound to the Google Maps webapp by default
-- (default/hypr/bindings/applications.lua). Rebind it to a region-select
-- snip using the user.snip plugin script (dark overlay, straight to clipboard).
hl.unbind("SUPER + SHIFT + S")
o.bind("SUPER + SHIFT + S", "Snip to clipboard (dark overlay)", os.getenv("HOME") .. "/.config/omarchy/plugins/user.snip/bin/omarchy-snip")

-- Logitech MX Keys examples:
-- o.bind("SUPER + H", nil, "voxtype record toggle")
-- o.bind("SUPER + PERIOD", nil, "omarchy-shell shell toggle omarchy.emojis")

-- ---------------------------------------------------------------------- music
--
-- Spotify was replaced by TIDAL. Omarchy's default binding for this key lives
-- in default/hypr/bindings/applications.lua and still points at spotify, so
-- the key has to be unbound before it can be bound again here.
hl.unbind("SUPER + SHIFT + M")
o.bind("SUPER + SHIFT + M", "Music", { launch = "tidal-hifi", focus = "^tidal-hifi$" })

-- ---------------------------------------------------------------- grid zones
--
-- omarchy-grid carves the left (DP-1) and right (HDMI-A-1) monitors into fixed
-- zones and snaps windows into them. Zones are numbered row-major from 1:
--   DP-1      rows of 2, 2, 1 columns -> zones 1-5
--   HDMI-A-1  three full-width rows   -> zones 1-3
-- The middle monitor (DP-2) has no grid and keeps normal dwindle tiling.
-- Zone shapes live in ~/.config/omarchy/grid.json.
for zone = 1, 5 do
  o.bind("SUPER + SHIFT + CTRL + " .. zone, "Snap window to grid zone " .. zone, "omarchy-grid snap " .. zone)
end

o.bind("SUPER + SHIFT + CTRL + 0", "Arrange monitor into grid", "omarchy-grid arrange")
o.bind("SUPER + SHIFT + CTRL + T", "Release window back to tiling", "omarchy-grid unsnap")

-- ------------------------------------------------------ per-monitor workspaces
--
-- Each monitor owns a block of ten workspace ids (the rules live in
-- hypr/monitors.lua), but the keys address them as 1-10 relative to whichever
-- monitor has focus. SUPER+3 therefore opens a workspace on the display you
-- are already looking at instead of pulling focus to another monitor.
--
-- Keep these bases in sync with ~/.config/omarchy/monitor-workspaces.json,
-- which is what the bar widget reads.
local workspace_bases = { ["DP-1"] = 0, ["DP-2"] = 10, ["HDMI-A-1"] = 20 }

-- An unmapped monitor (just plugged in, say) falls back to plain 1-10.
local function monitor_workspace(index)
  local monitor = hl.get_active_monitor()
  local base = monitor and workspace_bases[monitor.name] or 0
  return tostring(base + index)
end

for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)

  hl.unbind("SUPER + " .. key)
  hl.unbind("SUPER + SHIFT + " .. key)
  hl.unbind("SUPER + SHIFT + ALT + " .. key)

  o.bind("SUPER + " .. key, "Switch to workspace " .. workspace, function()
    hl.dispatch(hl.dsp.focus({ workspace = monitor_workspace(workspace) }))
  end)

  o.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, function()
    hl.dispatch(hl.dsp.window.move({ workspace = monitor_workspace(workspace) }))
  end)

  o.bind("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. workspace, function()
    hl.dispatch(hl.dsp.window.move({ workspace = monitor_workspace(workspace), follow = false }))
  end)
end

-- Dropping a dragged window snaps it to the zone it landed nearest. Whatever
-- was already in that zone moves to the next free zone, or to the next
-- workspace page of that monitor when the grid is full. Monitors without a
-- grid (the centre display) keep plain free-form dragging.
o.bind("SUPER + mouse:272", "Snap dragged window to grid", "omarchy-grid snap-nearest",
  { mouse = true, release = true })

-- FLAC player (user.flac shell plugin): toggle the panel in the bar.
o.bind("SUPER + M", "FLAC player", "omarchy-shell shell toggle user.flac")

-- Torrents (user.torrent shell plugin): toggle the panel in the bar.
o.bind("SUPER + ALT + T", "Torrents", "omarchy-shell shell toggle user.torrent")

-- Dismiss all notifications (same command as the stock SUPER+SHIFT+comma).
o.bind("SUPER + ALT + BACKSPACE", "Dismiss all notifications", "omarchy-shell notifications dismissAll")

-- Disable the stock SUPER+ALT+comma (was: Invoke last notification).
hl.unbind("SUPER + ALT + comma")
