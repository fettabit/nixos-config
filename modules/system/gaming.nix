{pkgs, ...}: {
  programs.steam = {
    enable = true;
    gamescopeSession = {
      enable = true;
    };
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };
  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        defaultgov = "performance";
        desiredgov = "performance";
        softrealtime = "auto";
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsability";
        amd_performance_level = "high";
      };
      custom = {
        start = "${pkgs.libnotify}/bin/notify-send -a 'GameMode' 'GameMode Started'";
        end = "${pkgs.libnotify}/bin/notify-send -a 'GameMode' 'GameMode ended'";
      };
    };
  };
}
