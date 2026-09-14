{...}: {
  imports = [
    ../../hardware-configuration.nix
    ../../modules/system
  ];

  networking.hostName = "blackgarden";

  users.users.jftx = {
    isNormalUser = true;
    # i2c: DDC monitor brightness for caelestia (modules/system/hyprland.nix)
    extraGroups = ["wheel" "gamemode" "i2c"];
    packages = [];
  };

  system.stateVersion = "26.05";
}
