{...}: {
  programs.bash = {
    enable = true;
    shellAliases = {
      gs = "git status";
      gp = "git push -u origin main";
      trb = "nixos-rebuild build --flake ~/nixos#blackgarden --sudo";
      rb = "nixos-rebuild switch --flake ~/nixos#blackgarden --sudo";
      nixcfg = "cd ~/nixos && code .";
      hyprcfg = "cd ~/nixos/modules/home/desktop/hypr && code .";
    };
    initExtra = ''
      export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
    '';
    profileExtra = ''
      if uwsm check may-start && [ "$XDG_VTNR" = 1 ]; then
          exec uwsm start hyprland-uwsm.desktop
      fi
    '';
  };
}
