{pkgs, ...}: {
  # caelestia-cli owns the runtime theming: on every scheme apply it writes
  # ~/.config/gtk-{3,4}.0/gtk.css, the dconf gtk-theme/color-scheme/icon-theme
  # keys, and ~/.config/qtengine/{caelestia.colors,config.json}. Nothing here
  # may own those paths or keys (an HM symlink or dconf write would fight it
  # on every activation).
  gtk = {
    enable = true;
    # caelestia writes the same theme name in both light and dark mode and
    # recolours through gtk.css, so HM's derived dconf gtk-theme never disagrees.
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    # No gtk.iconTheme: HM would also write dconf icon-theme=Papirus-Dark and
    # undo caelestia's Papirus-Light in light mode. settings.ini only:
    gtk3.extraConfig.gtk-icon-theme-name = "Papirus-Dark";
    gtk4.extraConfig.gtk-icon-theme-name = "Papirus-Dark";
  };

  # qtengine reads caelestia's colour scheme; `name` is a free string here and
  # qt.enable exports QT_PLUGIN_PATH for the profile so the plugin is found.
  qt = {
    enable = true;
    platformTheme = {
      name = "qtengine";
      package = pkgs.qtengine;
    };
  };

  # Cursor: HM exports XCURSOR_THEME/XCURSOR_SIZE, writes ~/.icons/default and
  # the GTK settings + dconf cursor-theme (caelestia never touches that key).
  # Hyprland reads XCURSOR_THEME itself; nixpkgs has no hyprcursor build of
  # Bibata, so hyprcursor stays off rather than logging a fallback.
  home.pointerCursor = {
    enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Ice";
    size = 24;
    gtk.enable = true;
  };

  home.packages = [
    pkgs.papirus-icon-theme
    pkgs.darkly # Qt6 style named in caelestia's qtengine config
  ];
}
