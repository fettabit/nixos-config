# Caelestia Shell Swap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the custom Quickshell island shell and the matugen theming cascade on `blackgarden` with caelestia shell (nixpkgs packages + the upstream flake's Home Manager module), in one PR, leaving the island only as git history under the tag `island-final`.

**Architecture:** Delete the island QML, the matugen templates and the wallpaper service/scripts; add a single `modules/home/desktop/caelestia.nix` that imports `inputs.caelestia-shell.homeManagerModules.default`, points it at `pkgs.caelestia-shell`/`pkgs.caelestia-cli`, and holds all shell/CLI settings declaratively; rewire the theming consumers (GTK, Qt→qtengine, kitty, Hyprland borders) to the files caelestia-cli writes; retarget the Hyprland Lua binds from `quickshell:*` to `caelestia:*` globals. The theming cascade becomes wallpaper → `caelestia wallpaper` → `scheme.json` → caelestia-cli templates → apps → `theme.postHook` (`hyprctl reload`).

**Tech Stack:** NixOS unstable flake, Home Manager as a NixOS module, caelestia-shell 2.3.0 + caelestia-cli 1.1.2 (nixpkgs), qtengine 0.2.1, darkly, Papirus, Hyprland Lua config (`hl.*` API), systemd user units, stylua, alejandra.

**Spec:** `docs/superpowers/specs/2026-09-14-caelestia-shell-swap-design.md` — read it first; every task below cites the spec section it implements. Issue #24, branch `feat/caelestia-shell`.

## Global Constraints

- **Never run `rb` / `nixos-rebuild switch`.** Validation is `nix flake check` and `trb` (`nixos-rebuild build --flake ~/nixos#blackgarden --sudo`). Activation is jftx's; the runbook is spec §3.7.
- **`git add` new files before `nix flake check`** — untracked files are invisible to flake evaluation.
- Work on branch `feat/caelestia-shell`; never commit to `main`. Commit messages end with the attribution trailer shown in each commit step.
- Packages come from **nixpkgs** (`pkgs.caelestia-shell` 2.3.0, `pkgs.caelestia-cli` 1.1.2, `pkgs.qtengine`, `pkgs.darkly`, `pkgs.papirus-icon-theme`, `pkgs.pwvucontrol`, `pkgs.cliphist`, `pkgs.ddcutil`). The `caelestia-shell` flake input is used **only** for `homeManagerModules.default`.
- Every caelestia global-shortcut name used in Lua must be one of: `launcher`, `session`, `sidebar`, `dashboard`, `utilities`, `lock`, `clearNotifs`, `screenshot`, `screenshotClip`, `brightnessUp`, `brightnessDown`, `mediaToggle`, `mediaNext`, `mediaPrev` (spec §1.2, verified in the 2.3.0 tarball).
- `launcher.actions` and `bar.statusIcons` are whole-list replacements: restate every entry (spec §3.2).
- Nothing in HM may own `~/.config/gtk-{3,4}.0/gtk.css` or the dconf `icon-theme` key — caelestia-cli writes them (spec §3.3, review item 4).
- Lua files: `stylua` (default config, no `.stylua.toml`) normalises formatting; only the six files this plan rewrites must pass `stylua --check` (the untouched ones already fail on formatting — out of scope).
- Format Nix with `alejandra` before committing.

---

### Task 1: Tag the island and delete the island, matugen and wallpaper machinery

Implements spec §3.5 (repo deletions) and the `island-final` tag. After this task the config must still evaluate — it simply has no shell.

**Files:**
- Delete: `modules/home/desktop/quickshell/` (whole tree), `modules/home/desktop/quickshell.nix`, `modules/home/programs/matugen.nix`, `modules/home/programs/matugen/` (whole tree), `modules/home/services/wallpaper.nix`, `modules/home/services/scripts/` (whole tree)
- Modify: `modules/home/default.nix` (imports), `modules/system/packages.nix`, `modules/system/fonts.nix`

**Interfaces:**
- Produces: a config with no `programs.quickshell`, no matugen, no wallpaper units; `modules/home/default.nix` imports list without the three removed modules (Task 2 adds `./desktop/caelestia.nix`).

- [ ] **Step 1: Confirm branch and starting commit**

Run:
```bash
cd ~/nixos && git status --short && git branch --show-current && git log --oneline -3
```
Expected: clean tree, branch `feat/caelestia-shell`, top commits `e636233` (spec review fold-in) and `d885348` (spec) above `db1e067`.

- [ ] **Step 2: Tag the last pre-swap main commit**

Run:
```bash
cd ~/nixos && git tag island-final db1e067 && git tag
```
Expected: `island-final` listed. (Pushing the tag happens in Task 5 with the PR.)

- [ ] **Step 3: Delete the island, matugen and wallpaper trees**

Run:
```bash
cd ~/nixos && git rm -r -q \
  modules/home/desktop/quickshell \
  modules/home/desktop/quickshell.nix \
  modules/home/programs/matugen.nix \
  modules/home/programs/matugen \
  modules/home/services/wallpaper.nix \
  modules/home/services/scripts \
&& git status --short | grep -c '^D'
```
Expected: `38` (21 QML/JS files under `quickshell/`, `quickshell.nix`, `matugen.nix`, `matugen/config.toml` + 9 templates, `wallpaper.nix`, 4 scripts). `ls modules/home/desktop modules/home/programs modules/home/services` must show none of the six deleted paths.

- [ ] **Step 4: Drop the three imports from `modules/home/default.nix`**

Replace the whole file with:

```nix
{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ./packages.nix
    ./programs/git.nix
    ./programs/kitty.nix
    ./programs/spicetify.nix
    ./programs/bash.nix
    ./programs/obs-studio.nix
    ./services/ssh-agent.nix
    ./desktop/hyprland.nix
    ./desktop/theme.nix
  ];

  home.username = "jftx";
  home.homeDirectory = "/home/jftx";
  home.stateVersion = "26.05";
  home.sessionVariables.NIXOS_OZONE_WL = "1";
  # environment.d, not shell init: uwsm session units and their children
  # (Hyprland -> kitty -> shells) never source /etc/set-environment, so glibc
  # needs TZDIR here to resolve IANA zone names (timedatectl et al.).
  systemd.user.sessionVariables.TZDIR = "/etc/zoneinfo";
}
```

- [ ] **Step 5: Remove the island-era system packages**

Replace `modules/system/packages.nix` with (removed: `awww`, `matugen`, `rofi`, `grim`, `slurp`, `playerctl` — spec §3.1 "Packages out"):

```nix
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    vim
    gh
    wget
    cava
    unzip
    curl
    btop
    kitty
    lutris
    wine-wayland
    winetricks
    wineWow64Packages.staging
    vulkan-tools
    vulkan-loader
    mangohud
    gamescope
    python3
    nautilus
    fastfetch
    hyprpolkitagent
    cmatrix
    pipes-rs
    tty-clock
    figlet
    asciiquarium
    claude-code
    codex
    celluloid
    stylua
    alejandra
    networkmanagerapplet
    wl-clipboard
    tree
  ];
}
```

- [ ] **Step 6: Remove the island font pins**

Replace `modules/system/fonts.nix` with:

```nix
{pkgs, ...}: {
  fonts.packages = with pkgs; [
    # kitty's font (programs/kitty.nix). caelestia-shell ships its own
    # fontconfig (Material Symbols, Rubik, CaskaydiaCove NF) — nothing here feeds it.
    nerd-fonts.jetbrains-mono
    (pkgs.stdenvNoCC.mkDerivation {
      name = "anthropic-fonts";
      src = ../../fonts/anthropic;
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/share/fonts/truetype $out/share/fonts/opentype
        cp $src/*.ttf $out/share/fonts/truetype/ 2>/dev/null || true
        cp $src/*.otf $out/share/fonts/opentype/ 2>/dev/null || true
      '';
    })
  ];
}
```

- [ ] **Step 7: Format and evaluate**

Run:
```bash
cd ~/nixos && alejandra -q modules/home/default.nix modules/system/packages.nix modules/system/fonts.nix && git add -A && nix flake check 2>&1 | tail -5
```
Expected: no errors (warnings about unused inputs are fine). If evaluation fails with "attribute ... missing" it means a deleted module is still imported somewhere — grep for it.

- [ ] **Step 8: Verify the remaining references are exactly the ones later tasks own**

Run:
```bash
cd ~/nixos && grep -rnE 'quickshell|matugen|awww|rofi|playerctl|grim|slurp' --include=*.nix --include=*.lua modules hosts flake.nix
```
Expected hits, and nothing else:
- `modules/home/desktop/theme.nix` (matugen comments/CSS import) → Task 3
- `modules/home/programs/kitty.nix` (matugen include) → Task 3
- `modules/home/programs/bash.nix` (`restart quickshell` in the `rb` alias) → Task 3
- `modules/system/hyprland.nix` (dconf comment mentions matugen-reload) → Task 2
- `modules/home/desktop/hypr/modules/binds.lua` (`quickshell:*` globals, `grim`/`slurp`, `playerctl`) → Task 4
- `modules/home/desktop/hypr/modules/autostart.lua` (`awww-daemon`) → Task 4
- `modules/home/desktop/hypr/modules/decorations.lua` (matugen path) → Task 4

- [ ] **Step 9: Commit**

```bash
cd ~/nixos && git add -A && git commit -m "$(cat <<'EOF'
refactor: remove the island shell, matugen pipeline and wallpaper machinery (#24)

Deletes modules/home/desktop/quickshell (QML), quickshell.nix,
programs/matugen{.nix,/}, services/wallpaper.nix and services/scripts;
drops awww/matugen/rofi/grim/slurp/playerctl and the island-only font pins.
The last island commit is tagged island-final. caelestia lands next.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Add the caelestia flake input, `caelestia.nix`, and the system-side switches

Implements spec §3.1 (packaging), §3.2 (configuration), D8, D9, D11, review items 1, 3, 6a.

**Files:**
- Modify: `flake.nix`, `flake.lock` (via `nix flake lock`)
- Create: `modules/home/desktop/caelestia.nix`
- Modify: `modules/home/default.nix` (add import), `modules/system/hyprland.nix`, `hosts/blackgarden/default.nix`

**Interfaces:**
- Consumes: `inputs` (passed through `extraSpecialArgs`), `config.home.homeDirectory`.
- Produces: `caelestia.service` user unit; `~/.config/caelestia/shell.json` and `cli.json`; the `caelestia-theme-hook` binary path referenced from `cli.json`; `CAELESTIA_WALLPAPERS_DIR`; `~/.config/swappy/config`. Tasks 3–4 rely on the service name `caelestia` and on caelestia-cli writing `~/.config/hypr/scheme/current.lua`.

- [ ] **Step 1: Add the flake input**

Replace `flake.nix` with:

```nix
{
  description = "NixOS with Hyprland";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Used only for homeManagerModules.default (programs.caelestia). The
    # packages come from nixpkgs (modules/home/desktop/caelestia.nix), so
    # this input's own quickshell/cli/m3shapes inputs are locked but never built.
    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    home-manager,
    ...
  } @ inputs: {
    nixosConfigurations.blackgarden = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {inherit inputs;};
      modules = [
        ./hosts/blackgarden
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {inherit inputs;};
            users.jftx = import ./modules/home;
            backupFileExtension = "backup";
          };
        }
      ];
    };
  };
}
```

- [ ] **Step 2: Lock the new input (network)**

Run:
```bash
cd ~/nixos && nix flake lock 2>&1 | tail -8 && git diff --stat flake.lock
```
Expected: `flake.lock` gains nodes `caelestia-shell`, `caelestia-cli`, `quickshell`, `m3shapes` (+ their transitive inputs) and **no existing node changes** — `nix flake lock` only adds missing inputs. This clones quickshell's git metadata from git.outfoxxed.me, so it can take a minute. If the diff shows an existing node (nixpkgs, home-manager, …) moving, something else touched the lock: `git checkout flake.lock` and run `nix flake lock` again.

- [ ] **Step 3: Create `modules/home/desktop/caelestia.nix`**

```nix
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

  # swappy (ALT+SHIFT+S annotate) saves to ~/Desktop by default.
  xdg.configFile."swappy/config".text = ''
    [Default]
    save_dir=$HOME/Pictures/Screenshots
    save_filename_format=%F_%H-%M-%S.png
  '';
}
```

- [ ] **Step 4: Import it**

In `modules/home/default.nix`, add `./desktop/caelestia.nix` as the last entry of `imports`:

```nix
  imports = [
    ./packages.nix
    ./programs/git.nix
    ./programs/kitty.nix
    ./programs/spicetify.nix
    ./programs/bash.nix
    ./programs/obs-studio.nix
    ./services/ssh-agent.nix
    ./desktop/hyprland.nix
    ./desktop/theme.nix
    ./desktop/caelestia.nix
  ];
```

- [ ] **Step 5: System side — power-profiles-daemon, i2c**

Replace `modules/system/hyprland.nix` with:

```nix
{...}: {
  services.getty.autologinUser = "jftx";
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };

  # caelestia-cli writes the GTK theme/colour-scheme/icon-theme dconf keys on
  # every scheme apply; home-manager's gtk module writes gtk-theme too.
  programs.dconf.enable = true;

  # caelestia's power-profile toggle (bar/dashboard) talks to PPD over DBus;
  # amd-pstate exposes balanced/performance on this CPU.
  services.power-profiles-daemon.enable = true;

  # caelestia's brightness OSD / F1-F2 drive the DP-3 monitor over DDC
  # (ddcutil), which needs /dev/i2c-* access — the i2c group is granted in
  # hosts/blackgarden/default.nix.
  hardware.i2c.enable = true;
}
```

Replace `hosts/blackgarden/default.nix` with:

```nix
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
```

- [ ] **Step 6: Format and evaluate**

Run:
```bash
cd ~/nixos && alejandra -q flake.nix modules/home/desktop/caelestia.nix modules/home/default.nix modules/system/hyprland.nix hosts/blackgarden/default.nix && git add -A && nix flake check 2>&1 | tail -5
```
Expected: no errors.

- [ ] **Step 7: Verify the rendered shell.json**

Run:
```bash
cd ~/nixos && nix eval --raw '.#nixosConfigurations.blackgarden.config.home-manager.users.jftx.xdg.configFile."caelestia/shell.json".text' | python3 -m json.tool
```
Expected JSON with exactly these top-level keys: `bar`, `general`, `launcher`, `paths`, `session`; `general.apps.audio == ["pwvucontrol"]`; `general.idle.timeouts` has one entry with `timeout: 600`; `launcher.actions` has 13 entries and the `Sleep` entry's `command` is `["suspend"]`; `session.commands.hibernate == ["suspend"]`; `bar.statusIcons` has 5 entries with `battery.enabled == false`; `paths.wallpaperDir == "~/wallpapers"`.

- [ ] **Step 8: Verify the rendered cli.json and the hook**

Run:
```bash
cd ~/nixos && nix eval --raw '.#nixosConfigurations.blackgarden.config.home-manager.users.jftx.xdg.configFile."caelestia/cli.json".text' | python3 -m json.tool
```
Expected: `theme.enableSpicetify`, `enableChromium`, `enableWarp`, `enableZed`, `enablePandora` all `false`; `theme.postHook` is `/nix/store/<hash>-caelestia-theme-hook/bin/caelestia-theme-hook`; no other keys.

- [ ] **Step 9: Verify the unit, env and group**

Run:
```bash
cd ~/nixos && nix eval --json '.#nixosConfigurations.blackgarden.config.home-manager.users.jftx.systemd.user.services.caelestia' | python3 -m json.tool | grep -E 'ExecStart|WantedBy|Restart"|CAELESTIA|QT_QPA_PLATFORM|PartOf'
nix eval --raw '.#nixosConfigurations.blackgarden.config.home-manager.users.jftx.home.sessionVariables.CAELESTIA_WALLPAPERS_DIR'; echo
nix eval --json '.#nixosConfigurations.blackgarden.config.users.users.jftx.extraGroups'
nix eval --json '.#nixosConfigurations.blackgarden.config.services.power-profiles-daemon.enable'
nix eval --json '.#nixosConfigurations.blackgarden.config.hardware.i2c.enable'
```
Expected: `ExecStart` ends with `/bin/caelestia-shell` and contains `caelestia-shell-2.3.0`; `WantedBy`/`PartOf` = `graphical-session.target`; `Restart = on-failure`; Environment contains `QT_QPA_PLATFORM=wayland` and `CAELESTIA_WALLPAPERS_DIR=/home/jftx/wallpapers`; session variable prints `/home/jftx/wallpapers`; groups `["wheel","gamemode","i2c"]`; both booleans `true`.

- [ ] **Step 10: Full build (shellcheck on the hook runs here)**

Run:
```bash
cd ~/nixos && nixos-rebuild build --flake ~/nixos#blackgarden --sudo 2>&1 | tail -5 && ls -ld result
```
Expected: build succeeds, `result` symlink exists. This downloads caelestia-shell/cli, qtengine deps etc. from cache.nixos.org (minutes, no compilation). If shellcheck fails on `caelestia-theme-hook`, fix the script text — do not disable shellcheck.

- [ ] **Step 11: Commit**

```bash
cd ~/nixos && git add -A && git commit -m "$(cat <<'EOF'
feat: caelestia shell via nixpkgs packages + upstream HM module (#24)

Adds the caelestia-shell flake input (HM module only), desktop/caelestia.nix
with the full shell/cli settings (idle screen-off @10min, session hibernate
-> suspend, launcher Sleep -> suspend, desktop status icons, pwvucontrol,
~/wallpapers), the caelestia-theme-hook postHook that reloads Hyprland after
each scheme apply, swappy save dir, and the system-side switches
(power-profiles-daemon, i2c for DDC brightness).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Rewire the theming consumers — GTK/Qt (`theme.nix`), kitty, bash

Implements spec §3.3 and review item 4.

**Files:**
- Modify: `modules/home/desktop/theme.nix` (rewrite), `modules/home/programs/kitty.nix`, `modules/home/programs/bash.nix`

**Interfaces:**
- Consumes: caelestia-cli's outputs (`~/.config/gtk-{3,4}.0/gtk.css`, dconf keys, `~/.config/qtengine/*`, `~/.local/state/caelestia/sequences.txt`) and the `caelestia` unit name from Task 2.
- Produces: `QT_QPA_PLATFORMTHEME=qtengine` session variable; `rb` alias restarting `caelestia`; bash replaying terminal colour sequences.

- [ ] **Step 1: Rewrite `modules/home/desktop/theme.nix`**

```nix
{pkgs, ...}: {
  # caelestia-cli owns the runtime theming: on every scheme apply it writes
  # ~/.config/gtk-{3,4}.0/gtk.css, the dconf gtk-theme/color-scheme/icon-theme
  # keys, and ~/.config/qtengine/{caelestia.colors,config.json}. Nothing here
  # may own those paths or keys (an HM symlink or dconf write would fight it
  # on every activation).
  gtk = {
    enable = true;
    # caelestia writes the same theme name in both light and dark mode and
    # recolours through gtk.css, so HM's derived dconf gtk-theme never disagrees.
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    # No gtk.iconTheme: HM would also write dconf icon-theme=Papirus-Dark and
    # undo caelestia's Papirus-Light in light mode. settings.ini only:
    gtk3.extraConfig.gtk-icon-theme-name = "Papirus-Dark";
    gtk4.extraConfig.gtk-icon-theme-name = "Papirus-Dark";
  };

  # qtengine reads caelestia's colour scheme; `name` is a free string here and
  # qt.enable exports QT_PLUGIN_PATH for the profile so the plugin is found.
  qt = {
    enable = true;
    platformTheme = {
      name = "qtengine";
      package = pkgs.qtengine;
    };
  };

  home.packages = [
    pkgs.papirus-icon-theme
    pkgs.darkly # Qt6 style named in caelestia's qtengine config
  ];
}
```

- [ ] **Step 2: Drop the matugen include from kitty**

Replace `modules/home/programs/kitty.nix` with:

```nix
{...}: {
  programs.kitty = {
    enable = true;
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 16;
    };
    settings = {
      cursor_shape = "block";
      window_padding_width = 10;
      confirm_os_window_close = 0;
      scrollback_lines = 10000;
      enable_audio_bell = "no";
      tab_bar_style = "powerline";
    };
    # Colours come from caelestia-cli as OSC sequences written straight into
    # every /dev/pts (live windows) and replayed by bash for new ones
    # (programs/bash.nix) — no colour file to include.
  };
}
```

- [ ] **Step 3: Retarget the `rb` alias and replay colour sequences in bash**

Replace `modules/home/programs/bash.nix` with:

```nix
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
```

- [ ] **Step 4: Format and evaluate**

Run:
```bash
cd ~/nixos && alejandra -q modules/home/desktop/theme.nix modules/home/programs/kitty.nix modules/home/programs/bash.nix && git add -A && nix flake check 2>&1 | tail -5
```
Expected: no errors.

- [ ] **Step 5: Verify ownership handoff and env**

Run:
```bash
cd ~/nixos && H='.#nixosConfigurations.blackgarden.config.home-manager.users.jftx'
nix eval --json "$H.dconf.settings.\"org/gnome/desktop/interface\""
nix eval --json "$H.xdg.configFile" --apply 'x: { gtk3css = builtins.hasAttr "gtk-3.0/gtk.css" x; gtk4css = builtins.hasAttr "gtk-4.0/gtk.css" x; }'
nix eval --raw "$H.xdg.configFile.\"gtk-3.0/settings.ini\".text"; echo
nix eval --raw "$H.home.sessionVariables.QT_QPA_PLATFORMTHEME"; echo
nix eval --raw "$H.programs.kitty.extraConfig" | wc -c
nix eval --raw "$H.programs.bash.shellAliases.rb"; echo
nix eval --raw "$H.programs.bash.initExtra" | grep -c sequences.txt
```
Expected, line by line: `{"gtk-theme":"adw-gtk3-dark"}` (no `icon-theme`, no `color-scheme`); `{"gtk3css":false,"gtk4css":false}`; settings.ini contains `gtk-icon-theme-name=Papirus-Dark` and `gtk-theme-name=adw-gtk3-dark` and **no** `gtk-application-prefer-dark-theme`; `qtengine`; `0`; the alias ends with `systemctl --user restart caelestia`; `1`.

- [ ] **Step 6: Commit**

```bash
cd ~/nixos && git add -A && git commit -m "$(cat <<'EOF'
feat: hand GTK/Qt/kitty theming to caelestia-cli (#24)

theme.nix: drop the matugen gtk.css import, the HM dconf block and
gtk.iconTheme (HM would reset caelestia's Papirus-Light on activation);
Papirus via settings.ini only; Qt platform theme qt6ct -> qtengine + darkly.
kitty: no colour include (OSC sequences from caelestia-cli). bash: rb alias
restarts caelestia; new shells replay ~/.local/state/caelestia/sequences.txt.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Hyprland Lua — binds, autostart, env, decorations, misc, window rules

Implements spec §3.4 (+ the F-key rows), §3.3 Hyprland row, review item 2 (`allow_session_lock_restore`).

**Files:**
- Modify: `modules/home/desktop/hypr/modules/binds.lua`, `autostart.lua`, `env.lua`, `decorations.lua`, `misc.lua`, `windowrules.lua`

**Interfaces:**
- Consumes: caelestia global-shortcut names (Global Constraints), `caelestia` CLI on PATH (Task 2 `cli.enable`), `cliphist` on PATH (Task 2), `~/.config/hypr/scheme/current.lua` written by caelestia-cli (keys `primary`, `primaryContainer`, `onSurfaceVariant`, hex without `#`), `caelestia` unit name.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Rewrite `binds.lua`**

```lua
---------------------
---- MY PROGRAMS ----
---------------------

local terminal = "kitty"
local fileManager = "nautilus"
local wallpaperDir = os.getenv("HOME") .. "/wallpapers"

---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "ALT"

-- Shell drawers route through Hyprland's `global` dispatcher to caelestia's
-- GlobalShortcut objects (appid `caelestia`). Names must exist in the packaged
-- caelestia-shell (modules/Shortcuts.qml, areapicker/AreaPicker.qml,
-- services/Brightness.qml, services/Players.qml) — see the swap spec §1.2.
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.global("caelestia:session")) -- power menu
hl.bind(mainMod .. " + HOME", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SPACE", hl.dsp.global("caelestia:launcher"))
hl.bind("SUPER + V", hl.dsp.global("caelestia:utilities")) -- quick toggles (wifi/bt/mic/dnd/game mode)
hl.bind(mainMod .. " + N", hl.dsp.global("caelestia:sidebar")) -- notification centre
hl.bind(mainMod .. " + SHIFT + N", hl.dsp.global("caelestia:clearNotifs"), { locked = true })
hl.bind(mainMod .. " + D", hl.dsp.global("caelestia:dashboard")) -- calendar/weather/media/perf
hl.bind(mainMod .. " + L", hl.dsp.global("caelestia:lock"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle only

-- caelestia.service owns the single shell instance; this is the sanctioned
-- "shell wedged" escape. Never `caelestia shell -d` (that starts a second one).
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("systemctl --user restart caelestia"))

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

---------------------
---- WALLPAPER ----
---------------------
-- Random pick + scheme regeneration. Manual picks: ALT+SPACE, then `>wallpaper`
-- (the grid lives inside the launcher; there is no dedicated global).
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("caelestia wallpaper -r " .. wallpaperDir))

---------------------------------
---- SCREENSHOT / CLIPBOARD ----
---------------------------------
-- Region -> clipboard + notification; SHIFT variant -> swappy (annotate, save
-- to ~/Pictures/Screenshots via ~/.config/swappy/config).
hl.bind(mainMod .. " + S", hl.dsp.global("caelestia:screenshotClip"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.global("caelestia:screenshot"))
-- cliphist history (fed by autostart.lua) and emoji picker, both via fuzzel.
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard"))
hl.bind(mainMod .. " + SHIFT + C", hl.dsp.exec_cmd("pkill fuzzel || caelestia clipboard -d"))
hl.bind(mainMod .. " + period", hl.dsp.exec_cmd("pkill fuzzel || caelestia emoji -p"))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

--------------------
---- MEDIA KEYS ----
--------------------
-- jftx's board emits plain F-keys: F1/F2 brightness, F7-F9 media, F10-F12
-- volume. The XF86 names stay as aliases for other keyboards.

-- Volume is NOT a caelestia shortcut: write PipeWire directly; the OSD
-- watches it and pops itself.
local sink = "@DEFAULT_AUDIO_SINK@"
local volumeUp = "wpctl set-mute " .. sink .. " 0; wpctl set-volume -l 1.0 " .. sink .. " 5%+"
local volumeDown = "wpctl set-mute " .. sink .. " 0; wpctl set-volume " .. sink .. " 5%-"
local volumeMute = "wpctl set-mute " .. sink .. " toggle"
for _, key in ipairs({ "F12", "XF86AudioRaiseVolume" }) do
    hl.bind(key, hl.dsp.exec_cmd(volumeUp), { locked = true, repeating = true })
end
for _, key in ipairs({ "F11", "XF86AudioLowerVolume" }) do
    hl.bind(key, hl.dsp.exec_cmd(volumeDown), { locked = true, repeating = true })
end
for _, key in ipairs({ "F10", "XF86AudioMute" }) do
    hl.bind(key, hl.dsp.exec_cmd(volumeMute), { locked = true })
end
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })

-- Brightness: caelestia drives the DP-3 monitor over DDC (ddcutil, i2c group).
for _, key in ipairs({ "F2", "XF86MonBrightnessUp" }) do
    hl.bind(key, hl.dsp.global("caelestia:brightnessUp"), { locked = true, repeating = true })
end
for _, key in ipairs({ "F1", "XF86MonBrightnessDown" }) do
    hl.bind(key, hl.dsp.global("caelestia:brightnessDown"), { locked = true, repeating = true })
end

-- Media: caelestia's MPRIS globals (Spotify is the default player).
for _, key in ipairs({ "F7", "XF86AudioPrev" }) do
    hl.bind(key, hl.dsp.global("caelestia:mediaPrev"), { locked = true })
end
for _, key in ipairs({ "F8", "XF86AudioPlay", "XF86AudioPause" }) do
    hl.bind(key, hl.dsp.global("caelestia:mediaToggle"), { locked = true })
end
for _, key in ipairs({ "F9", "XF86AudioNext" }) do
    hl.bind(key, hl.dsp.global("caelestia:mediaNext"), { locked = true })
end
```

- [ ] **Step 2: Rewrite `autostart.lua`**

```lua
-------------------
---- AUTOSTART ----
-------------------

-- caelestia itself is NOT started here: caelestia.service starts it from
-- graphical-session.target and owns the single instance.
hl.on("hyprland.start", function()
    -- Clipboard history for `caelestia clipboard` (ALT+C). cliphist is on the
    -- user PATH via modules/home/desktop/caelestia.nix.
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
end)
```

- [ ] **Step 3: Rewrite `env.lua`**

```lua
-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- toolkit backend
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("CLUTTER_BACKEND", "wayland")

-- xdg specifications
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- qt variables
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
-- qtengine reads ~/.config/qtengine/* written by caelestia-cli (desktop/theme.nix)
hl.env("QT_QPA_PLATFORMTHEME", "qtengine")
```

- [ ] **Step 4: Rewrite the palette block at the top of `decorations.lua`**

Replace lines 1–20 (everything before `hl.config({`) with:

```lua
-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Wallpaper-driven palette written by caelestia-cli on every scheme apply:
-- ~/.config/hypr/scheme/current.lua is `return { primary = "c2c1ff", … }`
-- (Material You role names, hex WITHOUT '#'). Hyprland must still come up
-- with the static fallback colours before the first `caelestia wallpaper -f`,
-- hence the pcall; cli.json's theme.postHook runs `hyprctl reload` so this is
-- re-read after each write.
local ok, scheme = pcall(dofile, os.getenv("HOME") .. "/.config/hypr/scheme/current.lua")
if not ok or type(scheme) ~= "table" or type(scheme.primary) ~= "string" then
    scheme = nil
end

local function rgba(hex, alpha)
    return "rgba(" .. hex .. alpha .. ")"
end

local active_border = scheme
        and { colors = { rgba(scheme.primary, "ee"), rgba(scheme.primaryContainer, "ee") }, angle = 45 }
    or { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }
local inactive_border = scheme and rgba(scheme.onSurfaceVariant, "aa") or "rgba(595959aa)"
```

Leave the `hl.config({ … })`, `hl.curve(...)` and `hl.animation(...)` blocks exactly as they are.

- [ ] **Step 5: Rewrite `misc.lua`**

```lua
----------------
----  MISC  ----
----------------

hl.config({
    misc = {
        force_default_wallpaper = 0, -- caelestia draws the wallpaper
        disable_hyprland_logo = true,
        -- If caelestia dies while the screen is locked, let a restarted
        -- instance re-attach as the lock client instead of leaving a dead lock
        -- (swap spec §3.7 runbook step 8).
        allow_session_lock_restore = true,
    },
})
```

- [ ] **Step 6: Add the float rules to `windowrules.lua`**

Append to the end of the file:

```lua

-- caelestia helpers that are pop-ups, not tiles (absurd tiled on 5120x1440)
hl.window_rule({
    name = "float-swappy",
    match = { class = "^swappy$" },
    float = true,
})
hl.window_rule({
    name = "float-pwvucontrol",
    match = { class = "^com.saivert.pwvucontrol$" },
    float = true,
})
```

- [ ] **Step 7: Normalise formatting and syntax-check the six files**

Run:
```bash
cd ~/nixos/modules/home/desktop/hypr/modules && stylua binds.lua autostart.lua env.lua decorations.lua misc.lua windowrules.lua && stylua --check binds.lua autostart.lua env.lua decorations.lua misc.lua windowrules.lua && echo STYLUA-OK
```
Expected: `STYLUA-OK`. A parse error here is a Lua syntax error — fix the file, don't touch stylua settings. (The other Lua files in the directory fail `--check` on formatting alone; leave them.)

- [ ] **Step 8: Verify the shortcut names and the absence of island references**

Run:
```bash
cd ~/nixos/modules/home/desktop/hypr && grep -rhoE 'caelestia:[A-Za-z]+' . | sort -u
grep -rnE 'quickshell|awww|matugen|playerctl|brightnessctl|grim|slurp|hyprshutdown' . || echo NO-STALE-REFS
```
Expected: exactly `caelestia:brightnessDown brightnessUp clearNotifs dashboard launcher lock mediaNext mediaPrev mediaToggle screenshot screenshotClip session sidebar utilities` (14 names, one per line), then `NO-STALE-REFS`.

- [ ] **Step 9: Evaluate (the Lua is copied verbatim; this catches path/typo issues in the Nix side only)**

Run:
```bash
cd ~/nixos && git add -A && nix flake check 2>&1 | tail -3
```
Expected: no errors.

- [ ] **Step 10: Commit**

```bash
cd ~/nixos && git add -A && git commit -m "$(cat <<'EOF'
feat(hypr): retarget binds and theming to caelestia (#24)

binds: quickshell:* -> caelestia:* globals (launcher, utilities, sidebar,
dashboard, session, lock, screenshots, brightness, media), wpctl volume for
F10-F12, cliphist/emoji via fuzzel, ALT+W random via caelestia wallpaper -r,
ALT+SHIFT+R restarts caelestia.service. autostart: awww out, cliphist
watchers in. env: qt6ct -> qtengine. decorations: borders from
~/.config/hypr/scheme/current.lua. misc: allow_session_lock_restore.
windowrules: float swappy/pwvucontrol.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Docs, final verification sweep, PR

Implements spec §3.6 and the pre-activation checks of §3.7. Ends with the PR open and the activation runbook handed to jftx.

**Files:**
- Modify: `CLAUDE.md`, `docs/plans/quickshell-matugen-migration.md` (banner only)

**Interfaces:**
- Consumes: everything above.
- Produces: the PR; `island-final` tag on the remote; comments closing #7 and #17.

- [ ] **Step 1: Rewrite `CLAUDE.md`**

Replace the whole file with:

````markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NixOS flake-based system configuration for the single host `blackgarden` (x86_64-linux, AMD CPU + GPU, NVMe + ext4 root, vfat EFI System Partition at `/boot`, swap partition; dual-boots Windows via the firmware boot menu / `boot-windows`). Secure Boot via lanzaboote (systemd-boot; GRUB is gone). Runs Hyprland on Wayland via UWSM, with getty autologin to user `jftx`. The desktop shell is **caelestia** (caelestia-dots/shell — vertical left bar, launcher, dashboard, notification daemon, OSD, lock screen, session menu), packaged from nixpkgs and configured declaratively; it also owns theming end-to-end via `caelestia-cli`, which regenerates a Material You scheme from the current wallpaper and re-themes GTK, Qt, kitty, Hyprland borders, Discord and cava. Home Manager is wired in as a NixOS module (not standalone).

Pinned inputs: `nixpkgs/nixos-unstable`, `home-manager` (master, follows nixpkgs), `spicetify-nix` (Gerg-L, follows nixpkgs), `lanzaboote` (v1.1.0), and `caelestia-shell` (used **only** for its Home Manager module; the packages come from nixpkgs). `useGlobalPkgs = true`, so the system-level `nixpkgs.config.allowUnfree = true` also applies to Home Manager packages.

Plans live in-repo: per-feature design specs and implementation plans are under `docs/superpowers/specs/` and `docs/superpowers/plans/`. The current shell is described by `docs/superpowers/specs/2026-09-14-caelestia-shell-swap-design.md` (which supersedes `docs/plans/quickshell-matugen-migration.md`, kept as history).

## Key Commands

```bash
# Rebuild & switch (alias: rb): system + Hyprland Lua reload + caelestia restart.
# Activation is jftx's call — Claude validates, then asks him to run rb and paste output.
nixos-rebuild switch --flake ~/nixos#blackgarden --sudo && hyprctl reload && systemctl --user restart caelestia

# Validate evaluation without building — run after edits before suggesting a rebuild.
# git add new files first: untracked files are invisible to flake eval (purity).
nix flake check

# Full build without activation (alias: trb). Catches what flake check cannot —
# writeShellApplication runs shellcheck at build time.
nixos-rebuild build --flake ~/nixos#blackgarden --sudo

# Update pinned inputs, then rebuild. (system.autoUpgrade is configured but does
# NOT actually work on this machine — input bumps are always manual.)
nix flake update
```

There is no test suite; `nix flake check` plus `trb` is the validation step.

Other shell aliases (`modules/home/programs/bash.nix`): `gs`/`gp` → git status / push to main, `nixcfg` → open this repo in VS Code, `hyprcfg` → open the Hyprland Lua config in VS Code.

## Layout & Entry Point

`flake.nix` builds `nixosConfigurations.blackgarden` from two import roots, passing `inputs` down via `specialArgs`/`extraSpecialArgs`:

- **System:** `./hosts/blackgarden/default.nix` (hostname, the `jftx` user + groups, `stateVersion`) → imports `../../hardware-configuration.nix` and `../../modules/system`, whose `default.nix` aggregates per-concern files: `boot.nix`, `audio.nix`, `graphics.nix`, `hyprland.nix`, `fonts.nix`, `network.nix`, `nix.nix`, `gaming.nix`, `packages.nix`.
- **Home:** `./modules/home` (via `users.jftx = import ./modules/home`). `modules/home/default.nix` sets username/homeDirectory/stateVersion/session vars and imports `packages.nix`, `programs/{git,kitty,spicetify,bash,obs-studio}.nix`, `services/ssh-agent.nix`, and `desktop/{hyprland,theme,caelestia}.nix`.

Where to make a change:
- **System package** → `modules/system/packages.nix`. **User/CLI app** → `modules/home/packages.nix` (preferred for user-facing tools).
- A configured **program** (kitty, git, spicetify, bash) → its file under `modules/home/programs/`.
- A **system concern** (boot, audio, graphics, Hyprland session enablement + power-profiles-daemon + i2c, network/bluetooth, nix/gc, fonts, gaming/Steam) → the matching file in `modules/system/`.
- The **Hyprland config itself** (hand-written Lua) → `modules/home/desktop/hypr/` (`hyprland.lua` + `modules/*.lua`).
- **Shell config** (caelestia `shell.json`/`cli.json`, the theme post-hook, swappy) → `modules/home/desktop/caelestia.nix` (`programs.caelestia.settings` / `cli.settings`). There is no shell QML in this repo.
- **GTK/Qt theming glue** (what HM still owns: theme package, icon name in settings.ini, qtengine platform theme) → `modules/home/desktop/theme.nix`.

`hardware-configuration.nix` (repo root) is generated and still actively imported — **do not edit**. `flake.lock` — **do not edit by hand**; use `nix flake update`. Custom Anthropic fonts in `fonts/anthropic/` are installed as an inline `stdenvNoCC.mkDerivation` in `modules/system/fonts.nix`.

## Architecture Notes

- **Home Manager as a NixOS module:** `useGlobalPkgs` + `useUserPackages` are on, `backupFileExtension = "backup"`. Because pkgs is shared with the system, unfree apps (vscode) need no separate allowUnfree in home.
- **Boot/GC interplay:** lanzaboote signs and installs systemd-boot + kernel stubs (`configurationLimit = 5`, `linuxPackages_latest`); `boot-windows` sets the firmware BootNext to Windows and reboots. `nix.gc` runs daily deleting generations older than 10 days. `system.autoUpgrade` is declared but does not work here — never rely on it. Bootloader or generation-count changes → `modules/system/boot.nix`.
- **Hyprland:** enabled system-wide with UWSM in `modules/system/hyprland.nix` (which also holds getty autologin, dconf, power-profiles-daemon and i2c). Autostart: `bash.nix` `profileExtra` execs `uwsm start hyprland-uwsm.desktop` on TTY1. The compositor config is **hand-written Lua** — Hyprland reads `~/.config/hypr/hyprland.lua` natively via its embedded interpreter and `hl.*` API. The Lua lives in-repo at `modules/home/desktop/hypr/`, materialized via `xdg.configFile."hypr"` with `recursive = true` (per-file store symlinks; `~/.config/hypr` itself is a real dir, which is why caelestia-cli can drop `scheme/current.lua` next to them). The Home Manager `wayland.windowManager.hyprland` module is deliberately **not** used. Edit in-repo, then `rb` (the alias chains `hyprctl reload`). `misc.allow_session_lock_restore` is on so a restarted shell can re-attach to a locked session.
- **Caelestia shell + theming:** `programs.caelestia` (from `inputs.caelestia-shell.homeManagerModules.default`) with `package = pkgs.caelestia-shell` (withCli) and `cli.package = pkgs.caelestia-cli`, running as the `caelestia.service` user unit (`WantedBy graphical-session.target`, `Restart=on-failure`). **systemd owns the single instance — never launch a second by hand** (`caelestia shell -d`, `qs -c`); restart with `systemctl --user restart caelestia` (also ALT+SHIFT+R). The shell **is** the notification daemon — never install another one. `shell.json`/`cli.json` are read-only store symlinks generated from Nix: caelestia's nexus GUI (`>settings`) cannot save; config changes go through `caelestia.nix` + `rb`. Keybinds route through Hyprland's `global` dispatcher to `caelestia:*` shortcuts (ALT+SPACE launcher, SUPER+V utilities, ALT+N sidebar, ALT+D dashboard, ALT+M session, ALT+L lock, ALT+S/ALT+SHIFT+S screenshots, F1/F2 brightness, F7–F9 media); volume keys write PipeWire via `wpctl` and the OSD reacts. `caelestia shell -s` lists the IPC surface for scripting/testing.
  **Theming cascade** (one-way): wallpaper → `caelestia wallpaper -f <path>` / `-r` (ALT+W, `>wallpaper`, `>random`) → `~/.local/state/caelestia/scheme.json` (smart scheme: light/dark + variant follow the wallpaper) → caelestia-cli templates → `~/.config/gtk-{3,4}.0/gtk.css` + dconf keys, `~/.config/qtengine/*`, `~/.config/hypr/scheme/current.lua`, `~/.config/vesktop/themes/caelestia.theme.css`, `~/.config/cava/config`, OSC sequences into live terminals + `~/.local/state/caelestia/sequences.txt` (replayed by bash) → `theme.postHook` = `caelestia-theme-hook` (`hyprctl reload`). Consequences: HM must never own `gtk.css`, the dconf `icon-theme` key, or a kitty colour include; every consumer must tolerate a missing scheme (first login). No wallpaper rotation timer exists — picks are manual. Spicetify and Brave are deliberately not themed by caelestia (spicetify-nix bakes its theme; Brave needs `/etc` writes).
- **Spicetify** comes from its own flake input. `modules/home/programs/spicetify.nix` imports `inputs.spicetify-nix.homeManagerModules.default` and reads packages from its `legacyPackages` (marketplace app, adblockify + shuffle extensions, `text` theme).
````

- [ ] **Step 2: Banner the superseded master plan**

Insert as the very first lines of `docs/plans/quickshell-matugen-migration.md` (before the `# Quickshell + Matugen …` heading):

```markdown
> **SUPERSEDED (2026-09-14).** The island shell and the matugen pipeline this plan describes were replaced by caelestia shell — see `docs/superpowers/specs/2026-09-14-caelestia-shell-swap-design.md` (issue #24). Kept for history; the last island commit is tagged `island-final`.

```

- [ ] **Step 3: Full verification sweep**

Run:
```bash
cd ~/nixos && git add -A && nix flake check 2>&1 | tail -3
grep -rnE 'quickshell|matugen|awww|rofi|playerctl|grim|slurp|wallpaper-set|wallpaper\.timer|qt6ct|qt5ct' --include=*.nix --include=*.lua --include=CLAUDE.md . | grep -v '^./docs/' | grep -v 'quickshell-matugen-migration.md' || echo NO-STALE-REFS
nixos-rebuild build --flake ~/nixos#blackgarden --sudo 2>&1 | tail -3
```
Expected: flake check clean; `NO-STALE-REFS` (the only allowed mention of the old names is CLAUDE.md's pointer to the superseded plan's filename, filtered above — any other line is a stale reference to fix); `trb` succeeds.

- [ ] **Step 4: Read the deployed Hyprland tree and the caelestia files out of the build**

Run:
```bash
cd ~/nixos && H='.#nixosConfigurations.blackgarden.config.home-manager.users.jftx'
nix eval --raw "$H.xdg.configFile.hypr.source" | xargs -I{} sh -c 'ls {}/modules; grep -c "caelestia:" {}/modules/binds.lua'
nix eval --raw "$H.xdg.configFile.\"swappy/config\".text"
```
Expected: the nine `modules/*.lua` listed; `binds.lua` has ≥ 14 `caelestia:` occurrences; swappy config shows `save_dir=$HOME/Pictures/Screenshots`.

- [ ] **Step 5: Commit docs**

```bash
cd ~/nixos && git add -A && git commit -m "$(cat <<'EOF'
docs: CLAUDE.md for the caelestia shell; supersede the island master plan (#24)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Push branch + tag, open the PR**

Run:
```bash
cd ~/nixos && git push -u origin feat/caelestia-shell && git push origin island-final && gh pr create --title "Swap the island Quickshell shell for caelestia" --body "$(cat <<'EOF'
Closes #24. Supersedes #7 and #17.

Replaces the custom Quickshell island (bar, launcher, OSD, notification daemon, wallpaper picker) and the matugen theming cascade with **caelestia shell** — nixpkgs `caelestia-shell` 2.3.0 + `caelestia-cli` 1.1.2, configured through the upstream flake's Home Manager module. Clean cut in one PR; the last island commit is tagged `island-final`.

**Spec:** `docs/superpowers/specs/2026-09-14-caelestia-shell-swap-design.md` (includes the Codex review log in §5). **Plan:** `docs/superpowers/plans/2026-09-14-caelestia-shell-swap.md`.

Highlights
- caelestia owns theming end-to-end (GTK, Qt via qtengine + darkly, kitty via OSC sequences, Hyprland borders via `~/.config/hypr/scheme/current.lua` + `hyprctl reload` post-hook, Discord, cava); matugen and all templates deleted
- no wallpaper rotation: ALT+W random, `>wallpaper` grid, `caelestia wallpaper -f`
- idle: screen off @10 min only; lock on demand (ALT+L); session/launcher "hibernate"/"sleep" remapped to suspend (no resumeDevice, Secure Boot lockdown)
- smart scheme on (light/dark + variant follow the wallpaper)
- extras: caelestia screenshots (ALT+S clip / ALT+SHIFT+S swappy), cliphist + emoji via fuzzel, Papirus icons, DDC brightness (F1/F2 via i2c), power-profiles-daemon
- Hyprland binds retargeted `quickshell:*` → `caelestia:*`; volume via `wpctl`; `misc.allow_session_lock_restore`

Validation: `nix flake check` + `nixos-rebuild build` green; rendered `shell.json`/`cli.json`/unit/env checked by `nix eval`. **Activation runbook** (rb → reboot → bootstrap scheme → binds → lock with TTY2 hatch → cleanup): spec §3.7.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: PR URL printed.

- [ ] **Step 7: Close the superseded trackers**

Run (substitute the PR number printed above for `<PR>`):
```bash
cd ~/nixos && gh issue close 17 --comment "Superseded by #<PR>: caelestia's dashboard ships calendar + weather; the island control center is gone. Branch feat/cc-calendar-weather is dead and can be deleted." && gh issue close 7 --comment "Superseded by #<PR>: the island shell (all Track C work) is replaced by caelestia shell. Last island commit: tag island-final."
```
Expected: both issues closed.

- [ ] **Step 8: Hand off**

Tell jftx: the PR is open; nothing has been activated. Point at spec §3.7 "Activation runbook" — merge, `rb` (expect the old alias's trailing `restart quickshell` error), **reboot**, `caelestia wallpaper -f ~/wallpapers/moon.jpg`, then the bind and lock checks in order, and paste the activation output + anything that misbehaves back for triage. Do not run `rb` yourself.

---

## Self-review (done while writing)

- **Spec coverage:** §3.1 → Task 1 (packages out, fonts), Task 2 (input, `caelestia.nix`, system side); §3.2 → Task 2; §3.3 → Task 3 (GTK/Qt/kitty/bash), Task 4 (`decorations.lua`); §3.4 → Task 4; §3.5 → Task 1 (deletions), Task 5 (banner, tag push); §3.6 → Task 5; §3.7 pre-activation checks → each task's verify steps + Task 5 Step 3–4; D8/D9/D10/D11 → Task 2 (session/launcher suspend, i2c, no papirus-folders, wallpaper dir); review items 1–6 → Tasks 2, 3, 4, 5. On-disk cleanup and the activation runbook are jftx's (spec §3.7), not plan tasks.
- **Placeholders:** none; every file that changes is shown in full or as an exact replacement block.
- **Name consistency:** unit `caelestia` (Task 2 module → Task 3 alias → Task 4 ALT+SHIFT+R → Task 5 CLAUDE.md); hook `caelestia-theme-hook` (Task 2 let-binding, `cli.settings.theme.postHook`); scheme file `~/.config/hypr/scheme/current.lua` with keys `primary`/`primaryContainer`/`onSurfaceVariant` (spec §1.2 → Task 4); `CAELESTIA_WALLPAPERS_DIR` (Task 2 env + session var); shortcut names (Global Constraints ↔ Task 4 Step 8 list).
