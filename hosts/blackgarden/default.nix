{...}: {
  imports = [
    ../../hardware-configuration.nix
    ../../modules/system
  ];

  networking.hostName = "blackgarden";

  users.users.jftx = {
    isNormalUser = true;
    # i2c: DDC monitor brightness for caelestia (modules/system/hyprland.nix)
    # networkmanager: polkit grants NM actions without a prompt; Proton VPN's
    # kill switch commits NM connections unattended (#34)
    extraGroups = ["wheel" "gamemode" "i2c" "networkmanager"];
    packages = [];
  };

  system.stateVersion = "26.05";
}
