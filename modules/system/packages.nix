{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    vim
    wget
    unzip
    curl
    btop
    kitty
    python3
    nautilus
    waybar
    fastfetch
    hyprpolkitagent
    grim
    slurp
    claude-code
    awww
    rofi
    playerctl
    stylua
    alejandra
    swaynotificationcenter
    networkmanagerapplet
    wl-clipboard
    tree
  ];
}
