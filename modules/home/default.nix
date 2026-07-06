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
    ./services/ssh-agent.nix
    ./services/wallpaper.nix
    ./desktop/hyprland.nix
    ./desktop/waybar.nix
    ./desktop/theme.nix
    ./desktop/quickshell.nix
  ];

  home.username = "jftx";
  home.homeDirectory = "/home/jftx";
  home.stateVersion = "26.05";
  home.sessionVariables.NIXOS_OZONE_WL = "1";
}
