----------------
----  MISC  ----
----------------

hl.config({
	misc = {
		force_default_wallpaper = 0, -- caelestia draws the wallpaper
		disable_hyprland_logo = true,
		-- If caelestia dies while the screen is locked, let a restarted
		-- instance re-attach as the lock client instead of leaving a dead lock
		-- (swap spec §3.7 runbook step 8).
		allow_session_lock_restore = true,
	},
})
