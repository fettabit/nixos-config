{ pkgs, ... }:
{
    environment.systemPackages = with pkgs; [
        vim
        wget
        unzip
        curl
        btop
        kitty
        python3
        nautilus
        git
        waybar
        fastfetch
        hyprpolkitagent
        grim
        slurp
        claude-code
        hyprpaper
        rofi
        playerctl
        swaynotificationcenter
        networkmanagerapplet
        wl-clipboard
        tree
    ];
}