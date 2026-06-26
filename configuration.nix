{ config, lib, pkgs, ... }:

{
  imports =
    [ 
      ./hardware-configuration.nix
    ];

  # boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  # auto update
  system.autoUpgrade.enable = true;
  system.autoUpgrade.dates = "weekly";

  # auto cleanup
  nix.gc.automatic = true;
  nix.gc.dates = "daily";
  nix.gc.options = "--delete-older-than 10d";
  nix.settings.auto-optimise-store = true;  

  # networking
  networking.hostName = "blackgarden"; 
  networking.networkmanager.enable = true;

  # time
  time.timeZone = "America/New_York";

  # nix
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # graphics
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # audio
  services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
  };
  security.rtkit.enable = true;

  # desktop & hyprland
  services.getty.autologinUser = "jftx";
  programs.hyprland = {
	enable = true;
	xwayland.enable = true;
	withUWSM = true;	
  };

  # user
  users.users.jftx = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "1234";
    packages = with pkgs; [
      tree
    ];
  };

  # fonts
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    (pkgs.stdenvNoCC.mkDerivation {
      name = "anthropic-fonts";
      src = ./fonts/anthropic;
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/share/fonts/truetype $out/share/fonts/opentype
        cp $src/*.ttf $out/share/fonts/truetype/ 2>/dev/null || true
        cp $src/*.otf $out/share/fonts/opentype/ 2>/dev/null || true
      '';
    })
  ];

  # system packages
  environment.systemPackages = with pkgs; [
    vim 
    wget
    unzip
    curl
    btop
    kitty
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
  ];

  system.stateVersion = "26.05"; # Did you read the comment?

}

