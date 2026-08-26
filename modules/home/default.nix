{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./packages.nix
    ./programs/git.nix
    ./programs/kitty.nix
    ./programs/spicetify.nix
    ./programs/bash.nix
    ./programs/matugen.nix
    ./programs/obs-studio.nix
    ./services/ssh-agent.nix
    ./services/wallpaper.nix
    ./desktop/hyprland.nix
    ./desktop/theme.nix
    ./desktop/quickshell.nix
  ];

  home.username = "jftx";
  home.homeDirectory = "/home/jftx";
  home.stateVersion = "26.05";
  home.sessionVariables.NIXOS_OZONE_WL = "1";
  # environment.d, not shell init: uwsm session units and their children
  # (Hyprland -> kitty -> shells) never source /etc/set-environment, so glibc
  # needs TZDIR here to resolve IANA zone names (timedatectl et al.).
  systemd.user.sessionVariables.TZDIR = "/etc/zoneinfo";
}
