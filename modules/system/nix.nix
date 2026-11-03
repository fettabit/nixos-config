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
  # nixpkgs (2026-11) marks gtk2 broken as a deprecation flag ahead of its
  # removal before 27.05 (NixOS/nixpkgs#410814). lutris' FHS env still lists
  # gtk2, which blocks the whole system build. "warn" lets only gtk2 through;
  # drop this once nixpkgs' lutris stops pulling it in.
  nixpkgs.config.problems.handlers."gtk+".broken = "warn";
  # nixos-upgrade.service runs as root; libgit2 refuses to open the checkout in
  # /home/jftx ("repository path is not owned by current user"), which is why
  # this silently never worked when it pointed at ~/nixos. Building from the
  # pushed repo also means it upgrades what is merged, not a half-edited tree.
  # --override-input replaces the deprecated --update-input: evaluate with
  # the newest nixos-unstable (every follows-nixpkgs input rides along) without
  # touching a lock file. The local checkout's flake.lock is unaffected — the
  # next manual rb rebuilds from the pinned lock until `nix flake update`.
  system.autoUpgrade = {
    enable = true;
    flake = "github:fettabit/nixos-config#blackgarden";
    flags = [
      "--override-input"
      "nixpkgs"
      "github:NixOS/nixpkgs/nixos-unstable"
      "--no-write-lock-file"
      "-L"
    ];
    dates = "weekly";
    randomizedDelaySec = "45min";
  };
}
