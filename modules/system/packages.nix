{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    vim
    gh
    wget
    cava
    unzip
    curl
    btop
    kitty
    lutris
    wine-wayland
    winetricks
    wineWow64Packages.staging
    vulkan-tools
    vulkan-loader
    mangohud
    gamescope
    python3
    nautilus
    fastfetch
    proton-cli
    proton-vpn
    proton-pass
    protonmail-desktop
    proton-vpn-cli
    proton-pass-cli
    hyprpolkitagent
    cmatrix
    pipes-rs
    tty-clock
    figlet
    asciiquarium
    claude-code
    # TEMPORARY (#48): codex 0.167.0 fails to build since cargoSetupHook
    # forces system aws-lc/oniguruma/sqlite/zstd (NixOS/nixpkgs#585124).
    # Fixed upstream by NixOS/nixpkgs#584667 (merged 2026-11-08), not yet in
    # nixos-unstable. Once a flake update brings it in, drop this back to
    # plain `codex` -- the extra buildInputs are then duplicates.
    (codex.overrideAttrs (old: {
      buildInputs = old.buildInputs ++ [aws-lc oniguruma sqlite zstd];
    }))
    celluloid
    stylua
    alejandra
    networkmanagerapplet
    wl-clipboard
    tree
  ];
}
