{pkgs, ...}: {
  # Flatpak exists for one app: Brave (#47). nixpkgs removed `brave` on
  # 2026-11-03 ("no committers among its maintainers to unblock security
  # issues"); Flathub's com.brave.Browser is published by Brave Software.
  # System-wide install, so the root unit below needs no polkit agent (#33).
  # environment.profiles adds /var/lib/flatpak/exports to XDG_DATA_DIRS, which
  # the session only picks up at the next login.
  services.flatpak.enable = true;

  # Flathub remote + the app list, declared. Also the update path: a browser
  # must not go stale, so the timer runs this daily (system.autoUpgrade does
  # not touch Flatpak). First run after activation: start it by hand.
  systemd.services.flatpak-apps = {
    description = "Add Flathub, install and update Flatpak apps";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    path = [pkgs.flatpak];
    serviceConfig.Type = "oneshot";
    script = ''
      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak install --noninteractive --or-update flathub com.brave.Browser
      flatpak update --noninteractive
      flatpak uninstall --noninteractive --unused
    '';
  };

  systemd.timers.flatpak-apps = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
