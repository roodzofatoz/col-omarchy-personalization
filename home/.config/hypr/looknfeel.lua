-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
-- hl.config({
--   decoration = {
--     -- Use round window corners.
--     rounding = 8,
--
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Thin borders with rounded corners.
-- border_size is an int in Hyprland, so 0.5 is not representable; 1 is the
-- thinnest visible border. It applies to active and inactive windows alike --
-- only the colour differs between them.
hl.config({
  general = {
    border_size = 1,
  },

  decoration = {
    rounding = 4,
  },
})

-- The gravity-field wallpaper overlay is a permanent layer surface; without
-- this it fades in on every shell restart.
hl.layer_rule({ match = { namespace = "gravity-field" }, no_anim = true, animation = "none" })

-- Keep the mouse cursor visible while typing. Omarchy's default hides it on
-- any key press (e.g. "s" or Space), which is distracting in games and editors.
hl.config({
  cursor = {
    hide_on_key_press = false,
  },
})
