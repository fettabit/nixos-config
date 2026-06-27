{ ... }:
{
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nix.gc.automatic = true;
    nix.gc.dates = "daily";
    nix.gc.options = "--delete-older-than 10d";
    nix.settings.auto-optimise-store = true;
    nixpkgs.config.allowUnfree = true;
    system.autoUpgrade.enable = true;
    system.autoUpgrade.dates = "weekly";
}