# Propagate freshly generated Matugen colors to running apps.
# Every section is guarded: this must be safe to run before a consumer
# exists (first boot, or a consumer added in a later track).

# Kitty live-reloads its config (and the /tmp color include) on SIGUSR1.
# Process is "kitty" or ".kitty-wrapped" depending on wrapping.
killall -USR1 kitty .kitty-wrapped 2>/dev/null || true

# Cava: activates once a managed config_base exists (music widget, Track C).
if [ -f "$HOME/.config/cava/config_base" ]; then
  cat "$HOME/.config/cava/config_base" "$HOME/.config/cava/colors" >"$HOME/.config/cava/config" 2>/dev/null || true
  killall -USR1 cava 2>/dev/null || true
fi

# GTK live-reload hack: bounce theme + color-scheme so running GTK3/4
# apps flush caches and re-read the imported Matugen CSS.
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita' 2>/dev/null || true
  sleep 0.05
  gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true
  gsettings set org.gnome.desktop.interface color-scheme 'default' 2>/dev/null || true
  sleep 0.05
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
fi

# Hyprland: re-evaluate the Lua config so decorations.lua picks up
# ~/.cache/matugen/hypr-colors.lua. Systemd user services don't inherit
# the instance signature; discover it from the runtime dir when missing.
hypr_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -d "$hypr_dir" ]; then
  HYPRLAND_INSTANCE_SIGNATURE="$(find "$hypr_dir" -mindepth 1 -maxdepth 1 -printf '%T@ %f\n' | sort -rn | head -n1 | cut -d' ' -f2-)"
  export HYPRLAND_INSTANCE_SIGNATURE
fi
hyprctl reload >/dev/null 2>&1 || true
