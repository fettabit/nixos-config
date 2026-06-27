{ pkgs, inputs, ... }:
{
    imports = [
        ./packages.nix
        ./programs/kitty.nix
        ./programs/spicetify.nix
        ./programs/bash.nix
    ];

    home.username = "jftx";
    home.homeDirectory = "/home/jftx";
    home.stateVersion = "26.05";
    home.sessionVariables.NIXOS_OZONE_WL = "1";
}