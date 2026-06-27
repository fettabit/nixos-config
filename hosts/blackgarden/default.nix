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
        initialPassword = "1234";
        packages = [];
    };

    system.stateVersion = "26.05";
}