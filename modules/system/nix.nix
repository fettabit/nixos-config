{lib, ...}: {
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.gc.automatic = true;
  nix.gc.dates = "daily";
  nix.gc.options = "--delete-older-than 10d";
  nix.settings.auto-optimise-store = true;
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowInsecurePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "pnpm"
    ];
  system.autoUpgrade.flake = "github:fettabit/nixos-config#blackgarden";
  system.autoUpgrade.dates = "weekly";
}
