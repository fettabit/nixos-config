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
  ];

  # system packages
  environment.systemPackages = with pkgs; [
    vim 
    wget
    unzip
    curl
    btop
    ghostty
    kitty
    nautilus
    git
    waybar
    yazi
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

