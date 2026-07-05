{ ... }:
{
    services.getty.autologinUser = "jftx";
    programs.hyprland = {
        enable = true;
        xwayland.enable = true;
        withUWSM = true;
    };

    # home-manager's dconf.settings (GTK dark mode + matugen-reload's
    # live-reload gsettings bounce) needs the dconf service.
    programs.dconf.enable = true;
}