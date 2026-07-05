{pkgs, ...}: let
  matugen-reload = pkgs.writeShellApplication {
    name = "matugen-reload";
    runtimeInputs = [pkgs.coreutils pkgs.psmisc pkgs.glib pkgs.systemd pkgs.hyprland];
    text = builtins.readFile ./scripts/matugen-reload.sh;
  };

  wallpaper-random = pkgs.writeShellApplication {
    name = "wallpaper-random";
    runtimeInputs = [pkgs.awww pkgs.coreutils pkgs.findutils pkgs.matugen matugen-reload];
    text = builtins.readFile ./scripts/wallpaper-random.sh;
  };

  wallpaper-picker = pkgs.writeShellApplication {
    name = "wallpaper-picker";
    runtimeInputs = [pkgs.awww pkgs.coreutils pkgs.findutils pkgs.rofi pkgs.matugen matugen-reload];
    text = builtins.readFile ./scripts/wallpaper-picker.sh;
  };
in {
  home.packages = [wallpaper-random wallpaper-picker matugen-reload];

  systemd.user.services.wallpaper = {
    Unit = {
      Description = "set a random wallpaper with awww";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${wallpaper-random}/bin/wallpaper-random";
    };
  };

  systemd.user.timers.wallpaper = {
    Unit = {
      Description = "set a random wallpaper every 10 minutes";
      PartOf = ["graphical-session.target"];
    };
    Timer = {
      # first run 5s after login, then 10 min after each activation of wallpaper.service.
      # a manual `systemctl --user start wallpaper.service` (the ALT + W bind) re-activates
      # the service, which resets the OnUnitActiveSec countdown to a fresh 10 min.
      OnActiveSec = "5s";
      OnUnitActiveSec = "10min";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
