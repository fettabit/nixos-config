{...}: {
  programs.bash = {
    enable = true;
    shellAliases = {
      gs = "git status";
      gp = "git push -u origin main";
      trb = "nixos-rebuild build --flake ~/nixos#blackgarden --sudo";
      rb = "nixos-rebuild switch --flake ~/nixos#blackgarden --sudo && hyprctl reload && systemctl --user restart caelestia";
      nixcfg = "cd ~/nixos && code .";
      hyprcfg = "cd ~/nixos/modules/home/desktop/hypr && code .";
    };
    initExtra = ''
      export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent"
      # uwsm launches terminals into systemd scopes that inherit no TZDIR, so
      # glibc can't resolve IANA zone names in the shell (timedatectl shows
      # "(America, +0000)"). bashrc runs for every interactive shell — set it
      # unconditionally here. /etc/zoneinfo is a stable symlink into tzdata.
      export TZDIR="/etc/zoneinfo"
      # caelestia-cli themes live terminals by writing OSC colour sequences into
      # every /dev/pts; new shells replay the saved copy so fresh kitty windows
      # match the current scheme.
      _cs="''${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/sequences.txt"
      if [ -t 1 ] && [ -f "$_cs" ]; then cat "$_cs"; fi
      unset _cs
    '';
    profileExtra = ''
      if uwsm check may-start && [ "$XDG_VTNR" = 1 ]; then
          exec uwsm start hyprland-uwsm.desktop
      fi
    '';
  };
}
