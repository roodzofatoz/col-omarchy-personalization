-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Place newly opened windows into the first free grid zone on the monitors
-- configured in ~/.config/omarchy/grid.json. Stop it with
-- `pkill -f "omarchy-grid watch"`, or delete this line to disable it for good.
o.exec_on_start("omarchy-grid watch")

-- Launch Brave at login; the window rule in hyprland.lua places it on DP-2.
o.launch_on_start("brave")
