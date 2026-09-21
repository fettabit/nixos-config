{pkgs, ...}: {
  # Launch the Proton VPN app at login. The app only knows "connect when I
  # start" (connect_at_app_startup) and "start minimized" (start_app_minimized,
  # both in ~/.config/Proton/VPN/app-config.json, GUI-owned); launching is left
  # to the desktop. UWSM activates xdg-desktop-autostart.target, so systemd's
  # xdg-autostart generator runs this entry as app-proton.vpn.app.gtk@autostart.
  # The package itself is a system package (modules/system/packages.nix). (#36)
  xdg.autostart = {
    enable = true;
    entries = ["${pkgs.proton-vpn}/share/applications/proton.vpn.app.gtk.desktop"];
  };
}
