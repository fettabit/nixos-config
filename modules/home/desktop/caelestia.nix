{
  config,
  pkgs,
  inputs,
  ...
}: let
  # Runs after caelestia-cli applies a scheme (cli.json theme.postHook).
  # Hyprland must re-evaluate decorations.lua to pick up
  # ~/.config/hypr/scheme/current.lua. The systemd user env carries
  # HYPRLAND_INSTANCE_SIGNATURE under UWSM (verified 2026-09-14); the runtime-dir
  # discovery below is insurance for a session where it is missing.
  caelestia-theme-hook = pkgs.writeShellApplication {
    name = "caelestia-theme-hook";
    runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.hyprland];
    text = ''
      hypr_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
      if [ -z "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -d "$hypr_dir" ]; then
        HYPRLAND_INSTANCE_SIGNATURE="$(find "$hypr_dir" -mindepth 1 -maxdepth 1 -printf '%T@ %f\n' | sort -rn | head -n1 | cut -d' ' -f2-)"
        export HYPRLAND_INSTANCE_SIGNATURE
      fi
      hyprctl reload >/dev/null 2>&1 || true
    '';
  };

  wallpaperDir = "${config.home.homeDirectory}/wallpapers";
in {
  imports = [inputs.caelestia-shell.homeManagerModules.default];

  # caelestia.service (graphical-session.target, Restart=on-failure) owns the
  # single shell instance — never start a second one by hand (`caelestia
  # shell -d`, `qs -c`). Restart with `systemctl --user restart caelestia`.
  # The shell IS the notification daemon (org.freedesktop.Notifications):
  # never install another one.
  #
  # shell.json / cli.json are generated from `settings` below and land as
  # read-only store symlinks: config changes go through this file + rb, never
  # through caelestia's nexus GUI (`>settings`), which cannot save.
  programs.caelestia = {
    enable = true;
    # nixpkgs 2.3.0; withCli = true so the CLI is on the shell's own PATH.
    package = pkgs.caelestia-shell;
    systemd = {
      enable = true;
      environment = ["CAELESTIA_WALLPAPERS_DIR=${wallpaperDir}"];
    };

    settings = {
      paths.wallpaperDir = "~/wallpapers";
      general.apps = {
        terminal = ["kitty"]; # default foot
        explorer = ["nautilus"]; # default thunar
        playback = ["celluloid"]; # default mpv
        audio = ["pwvucontrol"]; # 2.3.0 default is pavucontrol
      };
      # Screen off after 10 min; no auto-lock, no suspend (lock is ALT+L / >lock).
      general.idle.timeouts = [
        {
          timeout = 600;
          idleAction = "dpms off";
          returnAction = "dpms on";
        }
      ];
      # No boot.resumeDevice and Secure Boot lockdown refuses hibernation, so
      # the 4th session button suspends instead of silently failing.
      session = {
        commands.hibernate = ["suspend"];
        icons.hibernate = "bedtime";
      };
      # Default is derived from the locale (en_US -> 12h); drives the bar,
      # dashboard and lock-screen clocks together.
      services.useTwelveHourClock = false;
      # Desktop: audio on, battery off. Whole list — EntryList replaces.
      bar.statusIcons = [
        {
          id = "lockStatus";
          enabled = true;
        }
        {
          id = "audio";
          enabled = true;
        }
        {
          id = "network";
          enabled = true;
        }
        {
          id = "bluetooth";
          enabled = true;
        }
        {
          id = "battery";
          enabled = false;
        }
      ];
      # Stock 2.3.0 list verbatim except Sleep: suspendThenHibernate -> suspend
      # (same reason as the session button). The list replaces the defaults
      # wholesale; enableDangerousActions (default false) still hides
      # Shutdown/Reboot/Logout.
      launcher.actions = [
        {
          name = "Calculator";
          icon = "calculate";
          description = "Do simple math equations (powered by Qalc)";
          command = ["autocomplete" "calc"];
        }
        {
          name = "Scheme";
          icon = "palette";
          description = "Change the current colour scheme";
          command = ["autocomplete" "scheme"];
        }
        {
          name = "Wallpaper";
          icon = "image";
          description = "Change the current wallpaper";
          command = ["autocomplete" "wallpaper"];
        }
        {
          name = "Variant";
          icon = "colors";
          description = "Change the current scheme variant";
          command = ["autocomplete" "variant"];
        }
        {
          name = "Random";
          icon = "casino";
          description = "Switch to a random wallpaper";
          command = ["caelestia" "wallpaper" "-r"];
        }
        {
          name = "Light";
          icon = "light_mode";
          description = "Change the scheme to light mode";
          command = ["setMode" "light"];
        }
        {
          name = "Dark";
          icon = "dark_mode";
          description = "Change the scheme to dark mode";
          command = ["setMode" "dark"];
        }
        {
          name = "Shutdown";
          icon = "power_settings_new";
          description = "Shutdown the system";
          command = ["poweroff"];
          dangerous = true;
        }
        {
          name = "Reboot";
          icon = "cached";
          description = "Reboot the system";
          command = ["reboot"];
          dangerous = true;
        }
        {
          name = "Logout";
          icon = "exit_to_app";
          description = "Log out of the current session";
          command = ["logout"];
          dangerous = true;
        }
        {
          name = "Lock";
          icon = "lock";
          description = "Lock the current session";
          command = ["loginctl" "lock-session"];
        }
        {
          name = "Sleep";
          icon = "bedtime";
          description = "Suspend";
          command = ["suspend"];
        }
        {
          name = "Settings";
          icon = "settings";
          description = "Configure the shell";
          command = ["caelestia" "shell" "nexus" "open"];
        }
      ];
    };

    cli = {
      enable = true; # caelestia-cli on jftx's PATH too
      package = pkgs.caelestia-cli;
      settings.theme = {
        # spicetify-nix bakes the theme into the store Spotify; a runtime
        # color.ini is a no-op.
        enableSpicetify = false;
        # `sudo -n tee` into /etc/brave/policies — fails silently on NixOS.
        enableChromium = false;
        # Not installed.
        enableWarp = false;
        enableZed = false;
        enablePandora = false;
        # Term/Hypr/Discord/Gtk/Qt/Cava/Fuzzel/Btop/Htop/Nvtop stay on (default).
        postHook = "${caelestia-theme-hook}/bin/caelestia-theme-hook";
      };
    };
  };

  # For `caelestia wallpaper -r` typed in a terminal; the service gets it via
  # systemd.environment above and ALT+W passes the dir explicitly.
  home.sessionVariables.CAELESTIA_WALLPAPERS_DIR = wallpaperDir;

  home.packages = [
    pkgs.pwvucontrol # general.apps.audio; the bar's audio popout hands off to it
    pkgs.cliphist # autostart.lua's `wl-paste --watch cliphist store` runs from Hyprland's PATH, not the CLI wrapper's
    pkgs.ddcutil # `ddcutil detect` in the brightness runbook check (the shell wrapper has its own copy)
  ];

  # Clipboard history is fed by autostart.lua (cliphist -max-items 50) and
  # would otherwise persist every copy — passwords included — across logins
  # in ~/.cache/cliphist/db. Wipe it when the session ends (PartOf stops this
  # unit with graphical-session.target) and again at start, for the
  # hard-power-off case where ExecStop never ran.
  systemd.user.services.cliphist-wipe = {
    Unit = {
      Description = "wipe clipboard history at session start and end";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.cliphist}/bin/cliphist wipe";
      ExecStop = "${pkgs.cliphist}/bin/cliphist wipe";
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  # swappy (ALT+SHIFT+S annotate) saves to ~/Desktop by default.
  xdg.configFile."swappy/config".text = ''
    [Default]
    save_dir=$HOME/Pictures/Screenshots
    save_filename_format=%F_%H-%M-%S.png
  '';
}
