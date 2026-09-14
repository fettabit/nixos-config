-------------------
---- AUTOSTART ----
-------------------

-- caelestia itself is NOT started here: caelestia.service starts it from
-- graphical-session.target and owns the single instance.
hl.on("hyprland.start", function()
	-- Clipboard history for `caelestia clipboard` (ALT+C). cliphist is on the
	-- user PATH via modules/home/desktop/caelestia.nix.
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
