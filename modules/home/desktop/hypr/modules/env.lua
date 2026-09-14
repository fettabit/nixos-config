-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- Cursor theme/size come from home.pointerCursor (desktop/theme.nix) via the
-- session environment (XCURSOR_THEME / XCURSOR_SIZE).

-- toolkit backend
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")

-- xdg specifications
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- qt variables
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
-- qtengine reads ~/.config/qtengine/* written by caelestia-cli (desktop/theme.nix)
hl.env("QT_QPA_PLATFORMTHEME", "qtengine")
