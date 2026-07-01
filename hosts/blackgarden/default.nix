{ ... }:
{
    imports = [
        ../../hardware-configuration.nix
        ../../modules/system
    ];

    networking.hostName = "blackgarden";

    users.users.jftx = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        packages = [];
    };

    system.stateVersion = "26.05";
}