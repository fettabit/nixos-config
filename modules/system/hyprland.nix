{...}: {
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };

  # caelestia-cli writes the GTK theme/colour-scheme/icon-theme dconf keys on
  # every scheme apply; home-manager's gtk module writes gtk-theme too.
  programs.dconf.enable = true;

  # caelestia's power-profile toggle (bar/dashboard) talks to PPD over DBus;
  # amd-pstate exposes balanced/performance on this CPU.
  services.power-profiles-daemon.enable = true;

  # caelestia's brightness OSD / F1-F2 drive the DP-3 monitor over DDC
  # (ddcutil), which needs /dev/i2c-* access — the i2c group is granted in
  # hosts/blackgarden/default.nix.
  hardware.i2c.enable = true;
}
