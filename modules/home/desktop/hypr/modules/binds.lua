---------------------
---- MY PROGRAMS ----
---------------------

local terminal = "kitty"
local fileManager = "nautilus"
local wallpaperDir = os.getenv("HOME") .. "/wallpapers"

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "ALT"

-- Shell drawers route through Hyprland's `global` dispatcher to caelestia's
-- GlobalShortcut objects (appid `caelestia`). Names must exist in the packaged
-- caelestia-shell (modules/Shortcuts.qml, areapicker/AreaPicker.qml,
-- services/Brightness.qml, services/Players.qml) — see the swap spec §1.2.
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.global("caelestia:session")) -- power menu
hl.bind(mainMod .. " + HOME", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SPACE", hl.dsp.global("caelestia:launcher"))
hl.bind("SUPER + V", hl.dsp.global("caelestia:utilities")) -- quick toggles (wifi/bt/mic/dnd/game mode)
hl.bind(mainMod .. " + N", hl.dsp.global("caelestia:sidebar")) -- notification centre
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.global("caelestia:clearNotifs"), { locked = true })
hl.bind(mainMod .. " + D", hl.dsp.global("caelestia:dashboard")) -- calendar/weather/media/perf
hl.bind(mainMod .. " + L", hl.dsp.global("caelestia:lock"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle only

-- caelestia.service owns the single shell instance; this is the sanctioned
-- "shell wedged" escape. Never `caelestia shell -d` (that starts a second one).
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("systemctl --user restart caelestia"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

---------------------
---- WALLPAPER ----
---------------------
-- Random pick + scheme regeneration. Manual picks: ALT+SPACE, then `>wallpaper`
-- (the grid lives inside the launcher; there is no dedicated global).
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("caelestia wallpaper -r " .. wallpaperDir))

---------------------------------
---- SCREENSHOT / CLIPBOARD ----
---------------------------------
-- Region -> clipboard + notification; SHIFT variant -> swappy (annotate, save
-- to ~/Pictures/Screenshots via ~/.config/swappy/config).
hl.bind(mainMod .. " + S", hl.dsp.global("caelestia:screenshotClip"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.global("caelestia:screenshot"))
-- cliphist history (fed by autostart.lua) and emoji picker, both via fuzzel.
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard"))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard -d"))
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("pkill fuzzel || caelestia emoji -p"))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

--------------------
---- MEDIA KEYS ----
--------------------
-- jftx's board emits plain F-keys: F1/F2 brightness, F7-F9 media, F10-F12
-- volume. The XF86 names stay as aliases for other keyboards.

-- Volume is NOT a caelestia shortcut: write PipeWire directly; the OSD
-- watches it and pops itself.
local sink = "@DEFAULT_AUDIO_SINK@"
local volumeUp = "wpctl set-mute " .. sink .. " 0; wpctl set-volume -l 1.0 " .. sink .. " 5%+"
local volumeDown = "wpctl set-mute " .. sink .. " 0; wpctl set-volume " .. sink .. " 5%-"
local volumeMute = "wpctl set-mute " .. sink .. " toggle"
for _, key in ipairs({ "F12", "XF86AudioRaiseVolume" }) do
	hl.bind(key, hl.dsp.exec_cmd(volumeUp), { locked = true, repeating = true })
end
for _, key in ipairs({ "F11", "XF86AudioLowerVolume" }) do
	hl.bind(key, hl.dsp.exec_cmd(volumeDown), { locked = true, repeating = true })
end
for _, key in ipairs({ "F10", "XF86AudioMute" }) do
	hl.bind(key, hl.dsp.exec_cmd(volumeMute), { locked = true })
end
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })

-- Brightness: caelestia drives the DP-3 monitor over DDC (ddcutil, i2c group).
for _, key in ipairs({ "F2", "XF86MonBrightnessUp" }) do
	hl.bind(key, hl.dsp.global("caelestia:brightnessUp"), { locked = true, repeating = true })
end
for _, key in ipairs({ "F1", "XF86MonBrightnessDown" }) do
	hl.bind(key, hl.dsp.global("caelestia:brightnessDown"), { locked = true, repeating = true })
end

-- Media: caelestia's MPRIS globals (Spotify is the default player).
for _, key in ipairs({ "F7", "XF86AudioPrev" }) do
	hl.bind(key, hl.dsp.global("caelestia:mediaPrev"), { locked = true })
end
for _, key in ipairs({ "F8", "XF86AudioPlay", "XF86AudioPause" }) do
	hl.bind(key, hl.dsp.global("caelestia:mediaToggle"), { locked = true })
end
for _, key in ipairs({ "F9", "XF86AudioNext" }) do
	hl.bind(key, hl.dsp.global("caelestia:mediaNext"), { locked = true })
end
