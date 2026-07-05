{ ... }:
{
    networking.networkmanager.enable = true;
    time.timeZone = "America/New_York";

    hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
    };
}