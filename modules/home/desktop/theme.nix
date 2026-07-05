{
  config,
  pkgs,
  ...
}: let
  # Runtime artifact written by matugen (see programs/matugen/config.toml);
  # GTK ignores the @import while the file doesn't exist yet.
  matugenGtkCss = ''@import url("file://${config.home.homeDirectory}/.cache/matugen/colors-gtk.css");'';
in {
  home.packages = with pkgs; [
    libsForQt5.qt5ct
    qt6Packages.qt6ct
  ];

  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };
    gtk3.extraCss = matugenGtkCss;
    gtk4.extraCss = matugenGtkCss;
    gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
  };

  # matugen-reload bounces these two keys to force live re-reads of the CSS.
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "adw-gtk3-dark";
  };

  # qt5ct/qt6ct read the matugen-generated color scheme + qss.
  qt = {
    enable = true;
    platformTheme.name = "qt6ct";
  };
}
