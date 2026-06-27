{ ... }:
{
    services.getty.autologinUser = "jftx";
    programs.hyprland = {
        enable = true;
        xwayland.enable = true;
        withUWSM = true;
    };
}