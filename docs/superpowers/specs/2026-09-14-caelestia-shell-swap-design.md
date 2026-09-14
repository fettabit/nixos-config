# Caelestia Shell Swap — Design

**Date:** 2026-09-14 · **Status:** approved by jftx (design walkthrough); Codex second opinion received and folded in (see §5) · **Issue:** #24 · **Branch:** `feat/caelestia-shell` · **Supersedes:** `docs/plans/quickshell-matugen-migration.md`, epic #7 (Track C), #17 (calendar/weather section)

Replace the hand-written Quickshell **island** shell and the **matugen** theming
cascade on `blackgarden` with **caelestia shell** (caelestia-dots/shell) and its
CLI, packaged from nixpkgs and configured declaratively through the upstream
flake's Home Manager module. One PR, clean cut; the island survives only as git
history under the tag `island-final`.

This document is self-contained on purpose: it carries the current state, every
decision with its alternatives, the full design, the activation runbook, the
rollback path and the open risks, so that it can be reviewed by someone with no
access to the conversation that produced it.

---

## 1. Context

### 1.1 What exists today (`main` @ `db1e067`)

Single host `blackgarden`: x86_64, AMD CPU+GPU, one monitor `DP-3` at
5120×1440@240, NixOS unstable, Home Manager as a NixOS module
(`useGlobalPkgs`, `useUserPackages`, `backupFileExtension = "backup"`),
Hyprland via UWSM with getty autologin, Secure Boot via lanzaboote (systemd-boot;
GRUB is gone since #21 — CLAUDE.md still says GRUB and is fixed by this PR).
Hyprland is configured in hand-written Lua under `modules/home/desktop/hypr/`
(`hyprland.lua` + `modules/*.lua`), deployed with `xdg.configFile."hypr"`
`recursive = true`, so `~/.config/hypr` is a real directory of per-file store
symlinks.

The desktop shell is the **island**: `modules/home/desktop/quickshell/`
(`shell.qml`, `island/*.qml` ×19, `fuzzy.js` + test, `theme/Theme.qml`) run by
nixpkgs quickshell 0.3.x through `programs.quickshell` (`quickshell.nix`) as the
`quickshell.service` user unit (`WantedBy graphical-session.target`,
`Restart=on-failure`). It is the bar (top-centre pill), launcher, volume OSD,
notification daemon (`org.freedesktop.Notifications`), control center
(SUPER+V: Wi-Fi/BT/DND tiles, sound, connectivity view) and wallpaper picker.
Hyprland binds reach it through the `global` dispatcher
(`quickshell:launcher|control|wallpapers|volumeUp|volumeDown|volumeMute`).

Theming is a one-way cascade owned by **matugen**: `wallpaper.service`
(`services/wallpaper.nix`) runs `wallpaper-random.sh` — the repo's only apply
block: state write → `awww img` → `matugen image --mode dark --prefer
saturation` → `matugen-reload.sh` (SIGUSR1 kitty, cava merge, gsettings bounce,
`hyprctl reload`). `programs/matugen/config.toml` + 9 templates render kitty,
hypr (`~/.cache/matugen/hypr-colors.lua`, read by `decorations.lua` via
`pcall(dofile)`), GTK CSS (`@import`ed from HM `gtk3/gtk4.extraCss`), qt5ct/qt6ct
colours + qss, vesktop CSS, cava colours and `/tmp/qs_colors.json` for the
island. `wallpaper.timer` rotates every 10 min and fires 5 s after login to
regenerate the tmpfs outputs; `wallpaper-set <path>` is the manual front door;
`wallpaper-picker` is a rofi fallback. `theme.nix` pins adw-gtk3-dark, Adwaita
icons, `dconf.settings` for gtk-theme/color-scheme, and `qt.platformTheme =
qt6ct`. `fonts.nix` pins `jetbrains-mono` and `nerd-fonts.iosevka` because the
island QML hardcodes them.

Other facts that matter here: `system.autoUpgrade` (weekly) does **not** work
on this machine — nixpkgs bumps are manual `nix flake update` commits; there is
no idle/lock management at all; `~/wallpapers` holds 56 images, all ≥5120×1440;
Spotify is spicetify-nix-built (`text` theme); Discord client is vesktop;
browser is Brave; `hyprpolkitagent`, `wl-clipboard`, `cava`, `btop`,
`nautilus`, `kitty`, `celluloid` are installed.

### 1.2 Caelestia facts (verified 2026-09-14)

Verified against the **v2.3.0 tarball that nixpkgs ships** (`caelestia-shell`
2.3.0, `caelestia-cli` 1.1.2, `qtengine` 0.2.1, `darkly` 0.5.39, all
binary-cached) and cross-checked with upstream `main` (v2.4.0 released
2026-08-29; `main` is 89 commits past 2.3.0). Where 2.3.0 and `main` differ it is
called out.

- **Packaging.** nixpkgs `caelestia-shell` wraps upstream's quickshell build with
  `--prefix PATH` (fish, ddcutil, brightnessctl, networkmanager, lm_sensors,
  swappy, wl-clipboard, libqalculate, bash, hyprland, and `caelestia-cli`
  because `withCli` defaults to `true`), sets its own `FONTCONFIG_FILE`
  (Material Symbols, Rubik, CaskaydiaCove NF — no system font changes needed),
  and installs `bin/caelestia-shell` = `qs -p <store>/share/caelestia-shell`.
  nixpkgs `caelestia-cli` is a Python app (pillow, materialyoucolor) wrapped
  with grim, slurp, swappy, wl-clipboard, cliphist, dart-sass, fuzzel on PATH.
  Home Manager upstream has **no** `programs.caelestia`; the upstream flake
  (`github:caelestia-dots/shell`) exports `homeManagerModules.default` with
  options `enable`, `package`, `systemd.{enable,target,environment}`,
  `settings`, `extraConfig`, `cli.{enable,package,settings,extraConfig}`; it
  writes `~/.config/caelestia/shell.json` and `cli.json` (JSON-merged) and a
  `caelestia.service` user unit (`WantedBy`/`PartOf`/`After` =
  `wayland.systemd.target` → `graphical-session.target`,
  `ExecStart=<package>/bin/caelestia-shell`, `Restart=on-failure`,
  `RestartSec=5`, `Environment=QT_QPA_PLATFORM=wayland` + `systemd.environment`).
  `package`/`cli.package` are plain options, so nixpkgs packages can be
  substituted for the flake's own builds (which would otherwise compile
  quickshell from git.outfoxxed.me locally, uncached).
- **Wallpaper.** The shell draws the wallpaper itself
  (`modules/background/Wallpaper.qml`, layer-shell background). State:
  `~/.local/state/caelestia/wallpaper/path.txt` (+ `current` link, thumbnail),
  restored on start; the shell's `Wallpapers.qml` `FileView` watches it. Setting:
  `caelestia wallpaper -f <path>` (manual), `caelestia wallpaper -r [DIR]`
  (random; filters images smaller than 80 % of the largest monitor unless
  `-n`; skips the current one), `-N/--no-smart`. Default dir
  `$CAELESTIA_WALLPAPERS_DIR` or `~/Pictures/Wallpapers` (CLI) and
  `paths.wallpaperDir` (shell, `~` expanded). No rotation timer exists.
- **Colour scheme.** `caelestia wallpaper -f` generates a Material You scheme
  (materialyoucolor, not matugen) → `~/.local/state/caelestia/scheme.json`;
  the shell reads that. With `services.smartScheme = true` (default) each
  wallpaper also decides light/dark from its tone and the M3 variant from its
  colourfulness; `--no-smart` keeps the current mode/variant. `caelestia scheme
  set -m dark|light`, `>light`/`>dark`/`>scheme`/`>variant` in the launcher
  override manually.
- **App theming (caelestia-cli `apply_colours`, gated by `cli.json`
  `theme.enable*`, all default `true`).** Terminals: writes OSC colour
  sequences into every writable `/dev/pts/N` and saves them to
  `~/.local/state/caelestia/sequences.txt`. Hyprland: detects a Lua config via
  `hyprctl` and writes `~/.config/hypr/scheme/current.lua` (`return { primary =
  "c2c1ff", … }`, hex **without** `#`, keys = M3 role names + `term0..15` +
  catppuccin aliases); does not reload Hyprland. Discord: sass → 
  `~/.config/{Vencord,vesktop,equibop,…}/themes/caelestia.theme.css`. GTK:
  atomically writes `~/.config/gtk-3.0/gtk.css`, `gtk-4.0/gtk.css`,
  `thunar.css`, then `dconf write` `gtk-theme='adw-gtk3-dark'` (always),
  `color-scheme='prefer-<mode>'`, `icon-theme='Papirus-<Mode>'` (or
  `theme.iconTheme`). Papirus folder recolouring runs `sudo -n papirus-folders`
  against `/usr/share/icons/Papirus*` or `~/.local/share/icons/Papirus` —
  **inert on NixOS** (neither path exists; the store copy is read-only). Qt:
  writes `~/.config/qtengine/caelestia.colors` + `config.json` (style
  `Darkly`, icons Papirus) for the **qtengine** platform theme
  (`QT_QPA_PLATFORMTHEME=qtengine`; nixpkgs `qtengine` provides
  `lib/qt-6/plugins/platformthemes/libqt6engine-plugin.so`). Cava: writes the
  whole `~/.config/cava/config` + SIGUSR2. Spicetify: writes
  `~/.config/spicetify/Themes/caelestia/color.ini` (useless with
  spicetify-nix, which bakes the theme at build time). Chromium/Brave: `sudo -n
  tee` into `/etc/brave/policies/managed/caelestia.json` (fails silently on
  NixOS). btop/htop/nvtop/fuzzel/warp/zed/pandora: theme files in their config
  dirs. User templates: `~/.config/caelestia/templates/*` →
  `~/.local/state/caelestia/theme/`. `theme.postHook` (string) runs via
  `sh -c` after every apply with `SCHEME_NAME/FLAVOUR/MODE/VARIANT/COLOURS` in
  the environment. A file lock prevents concurrent applies.
- **Global shortcuts** (appid `caelestia`, all present in 2.3.0): `launcher`,
  `launcherInterrupt`, `session`, `sidebar`, `dashboard`, `utilities`,
  `showall`, `lock`, `unlock`, `clearNotifs`, `screenshot`, `screenshotFreeze`,
  `screenshotClip`, `screenshotFreezeClip`, `brightnessUp`, `brightnessDown`,
  `mediaToggle`, `mediaNext`, `mediaPrev`, `mediaStop`, `nexus`. Volume is
  **not** a shortcut: upstream binds run `wpctl` and the OSD reacts to
  PipeWire. IPC: `caelestia shell <target> <fn>` (`drawers toggle <name>`,
  `wallpaper set|get|list`, `notifs …`, `mpris …`, `audio cycleOutput`,
  `brightness …`, `lock …`, `picker …`, `toaster …`, `idleInhibitor …`,
  `gameMode …`, `hypr …`); `caelestia shell -s` lists them.
- **Drawers.** Launcher (fuzzy desktop-entry search; `>` prefix → the 13
  stock actions in 2.3.0: Calculator, Scheme, Wallpaper (grid), Variant,
  Random (`caelestia wallpaper -r`), Light, Dark, Shutdown (`poweroff`),
  Reboot, Logout, Lock (`loginctl lock-session`), **Sleep
  (`suspendThenHibernate`, NOT flagged dangerous)**, Settings (nexus).
  Shutdown/Reboot/Logout carry `dangerous = true` and are hidden while
  `launcher.enableDangerousActions` is `false` (default); `launcher.actions`
  is a plain JSON list that **replaces** the defaults wholesale when set). Sidebar = notification centre. Dashboard = date/time, calendar,
  weather (ip-api geolocation when `services.weatherLocation` is empty),
  media/lyrics, performance. Utilities = quick toggles (Wi-Fi, Bluetooth, mic,
  game mode, DND, VPN), idle inhibitor, recording. Session = logout / shutdown
  / hibernate / reboot buttons (`session.commands.*`; tokens `logout`,
  `suspend`, `suspendThenHibernate`, `hibernate`, `poweroff`, `reboot` go over
  DBus; other lists are exec'd). OSD = volume/brightness. Lock screen = PAM via
  the shell's bundled `assets/pam.d/passwd` passed as a PAM config directory
  (nixpkgs patches the fprint/howdy variants — no `/etc/pam.d` entry needed).
  Idle (`general.idle.timeouts`, default: lock @180 s, dpms off @300 s,
  suspend-then-hibernate @600 s) uses the ext-idle-notify protocol — no
  hypridle. The bar is a **vertical left bar**; there is no position option.
  Area picker (screenshots): non-clip variants pipe the region to `swappy -f`
  (default save dir `~/Desktop`); clip variants `wl-copy` + notify.
- **Nexus** (`>settings`, `caelestia shell nexus open`) is a GUI editor that
  writes `shell.json` — incompatible with an HM-managed (read-only symlink)
  config; not used.
- **Session environment on blackgarden (checked live 2026-09-14).**
  `systemctl --user show-environment` contains `HYPRLAND_INSTANCE_SIGNATURE`,
  `WAYLAND_DISPLAY=wayland-1` and `XDG_CURRENT_DESKTOP=Hyprland` — UWSM
  exports them into the user manager — so `caelestia.service` and every
  `caelestia` CLI process it spawns can reach the Hyprland socket. That matters
  twice: the shell's `Hypr.qml` needs it for workspaces, and caelestia-cli's
  `is_lua_config()` queries `hyprctl` to decide whether to write
  `scheme/current.lua` or `current.conf`. The user PATH
  (`/etc/profiles/per-user/jftx/bin`, `/run/current-system/sw/bin`, …) does
  **not** include tools that only live inside the caelestia wrappers
  (cliphist, ddcutil, fuzzel, …); anything Hyprland or jftx runs directly must
  be installed separately.

---

## 2. Decisions

| # | Question | Decision | Alternatives rejected & why |
|---|---|---|---|
| D1 | Who owns theming? | **Caelestia end-to-end.** matugen, `matugen-reload`, all templates deleted; caelestia-cli themes every app. Gains spicetify-shaped coverage of GTK/Qt/kitty/Discord/cava/hypr with one engine. | (B) matugen stays source, feed caelestia a scheme file — two engines, launcher `>scheme` fights it. (C) split by consumer — worst of both. |
| D2 | Package source | **A: nixpkgs `caelestia-shell` 2.3.0 + `caelestia-cli` 1.1.2, configured through the upstream flake's HM module** (flake input used only for `homeManagerModules.default`). Binary-cached, no local quickshell build. One release behind upstream; since autoUpgrade is dead, catching up is a manual `nix flake update`, or an `src` override to the v2.4.0 tarball if 2.3.0 ever lacks something needed. | (B) track upstream `main` via the flake — compiles quickshell + the C++ plugin locally on every bump, bleeding-edge breakage. (C) nixpkgs + hand-written unit/config glue, no flake input — cleanest lock but re-implements the module. |
| D3 | 10-minute wallpaper rotation | **Dropped. Manual only:** ALT+W random, `>wallpaper` grid, `caelestia wallpaper -f`. `services/wallpaper.nix` and all four scripts deleted; no timer bootstrap needed (caelestia persists state in `~/.local/state`). | (A) slim timer → `caelestia wallpaper -r`. (C) keep a `wallpaper-set` shim — YAGNI. |
| D4 | Idle & lock | **Screen off after 10 min, nothing else.** No auto-lock, no suspend/hibernate. Lock on demand (ALT+L, `>lock`). | Caelestia defaults (lock 3 min / suspend-then-hibernate 10 min) — rude on a desktop that dual-boots Windows. Nothing at all — monitor never sleeps. |
| D5 | Scheme mode | **Full smart scheme** (default): light/dark and M3 variant follow each wallpaper; `>light`/`>dark`/`>variant` are manual overrides. | Force dark (`smartScheme=false` + `scheme set -m dark`) — closest to today's `--mode dark`, rejected by jftx. |
| D6 | Extras | **In:** caelestia screenshots (replace grim/slurp bind), clipboard history + emoji picker (cliphist + fuzzel), Papirus icons. **Out:** screen recording (OBS exists). | — |
| D7 | Migration shape | **Clean cut, one PR.** Tag `island-final` before the delete. Rollback = previous NixOS generation + `git revert`. | Two PRs (flip, then delete) — no extra safety over git history, leaves a half-state with stale docs/aliases. A `desktop.shell` toggle — over-engineering for one host. |
| D8 | Session "hibernate" button | **Remapped to `suspend`** (`session.commands.hibernate = ["suspend"]`, icon `bedtime`). No `boot.resumeDevice` is configured and the Secure Boot kernel lockdown refuses hibernation; a button that fails silently is worse than one that suspends. | Leave hibernate — untested/likely broken. |
| D9 | Brightness hardware | **Enable DDC** (`hardware.i2c.enable`, `jftx` in `i2c`) so F1/F2 and the OSD drive DP-3 over ddcutil. | Skip — then brightness keys do nothing on a desktop. |
| D10 | Papirus folder recolouring | **Not attempted** (`papirus-folders` not installed): caelestia's implementation needs `sudo -n` + a writable Papirus copy outside the store. Papirus-Dark/Light per mode still flips via dconf. | Copy Papirus to `~/.local/share/icons` outside Nix — impure. |
| D11 | Wallpaper directory | **Keep `~/wallpapers`**: `paths.wallpaperDir = "~/wallpapers"` (shell), `CAELESTIA_WALLPAPERS_DIR=/home/jftx/wallpapers` in `programs.caelestia.systemd.environment` (shell-spawned CLI) and `home.sessionVariables` (interactive shells); ALT+W passes the dir explicitly. | `mv ~/wallpapers ~/Pictures/Wallpapers` — one-time, undocumented mutation outside the repo. |

---

## 3. Design

### 3.1 Packaging & flake

**`flake.nix`** — one new input:

```nix
caelestia-shell = {
  url = "github:caelestia-dots/shell";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Only `inputs.caelestia-shell.homeManagerModules.default` is consumed. Its own
inputs (`quickshell`, `caelestia-cli`, `m3shapes`) are locked but never
evaluated into a build because both package options point at nixpkgs.

**New `modules/home/desktop/caelestia.nix`** (replaces `quickshell.nix` in
`modules/home/default.nix` imports):

```nix
{ config, pkgs, inputs, ... }:
let
  # Runs after caelestia-cli applies a scheme (cli.json theme.postHook).
  # Hyprland must re-evaluate decorations.lua to read ~/.config/hypr/scheme/current.lua.
  # Systemd user services may lack the instance signature; discover it from
  # the runtime dir (lifted from the retired matugen-reload.sh).
  caelestia-theme-hook = pkgs.writeShellApplication {
    name = "caelestia-theme-hook";
    runtimeInputs = [ pkgs.coreutils pkgs.findutils pkgs.hyprland ];
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
  imports = [ inputs.caelestia-shell.homeManagerModules.default ];

  programs.caelestia = {
    enable = true;
    package = pkgs.caelestia-shell;          # 2.3.0; withCli = true → CLI on the shell's PATH
    systemd = {
      enable = true;                         # caelestia.service, graphical-session.target, Restart=on-failure
      environment = [ "CAELESTIA_WALLPAPERS_DIR=${wallpaperDir}" ];
    };
    settings = { … see 3.2 … };
    cli = {
      enable = true;                         # caelestia-cli on jftx's PATH
      package = pkgs.caelestia-cli;
      settings = { … see 3.2 … };
    };
  };

  home.sessionVariables.CAELESTIA_WALLPAPERS_DIR = wallpaperDir;
  home.packages = [
    pkgs.pwvucontrol   # general.apps.audio; the bar's audio popout hands off to it
    pkgs.cliphist      # autostart.lua's `wl-paste --watch cliphist store` runs from Hyprland's PATH, not the CLI wrapper's
    pkgs.ddcutil       # `ddcutil detect` for the brightness runbook check (the shell wrapper has its own copy)
  ];

  # swappy (ALT+SHIFT+S annotate) defaults to ~/Desktop
  xdg.configFile."swappy/config".text = ''
    [Default]
    save_dir=$HOME/Pictures/Screenshots
    save_filename_format=%F_%H-%M-%S.png
  '';
}
```

**systemd ownership rule carries over unchanged:** `caelestia.service` is the
single instance; never start a second with `caelestia shell -d` or `qs -c`;
restart with `systemctl --user restart caelestia` (also what the `rb` alias
does and what ALT+SHIFT+R does).

**Packages in:** `pkgs.qtengine` (via `qt.platformTheme.package`, 3.3),
`pkgs.darkly` (Qt6 style caelestia's qtengine config names; Fusion fallback
without it), `pkgs.pwvucontrol`, `pkgs.cliphist`, `pkgs.ddcutil`,
`pkgs.papirus-icon-theme` (3.3). The caelestia packages carry every external
tool *they* call; `cliphist`/`ddcutil` are needed because Hyprland's autostart
and the runbook call them from outside the wrappers.

**Packages out (`modules/system/packages.nix`):** `awww`, `matugen`, `rofi`,
`grim`, `slurp`, `playerctl` (media keys move to caelestia's MPRIS globals).
`programs.quickshell` leaves with `quickshell.nix`. `wl-clipboard`, `cava`,
`hyprpolkitagent`, `libnotify`, `networkmanagerapplet` stay.

**System side:**

- `modules/system/hyprland.nix` (it already holds the desktop-session
  concerns: autologin, dconf): `services.power-profiles-daemon.enable = true` (caelestia's
  performance/power-profile toggle over DBus; amd-pstate on this CPU) and
  `hardware.i2c.enable = true`; `hosts/blackgarden/default.nix`: `jftx` gains
  the `i2c` group (D9). `programs.dconf.enable` stays (caelestia writes dconf);
  its comment is updated.
- `modules/system/fonts.nix`: remove `jetbrains-mono` and `nerd-fonts.iosevka`
  (island-only); keep `nerd-fonts.jetbrains-mono` (kitty) and the Anthropic
  fonts; fix the comment.
- No PAM configuration (see 1.2, lock).

### 3.2 Caelestia configuration (declarative)

Both JSON files are generated by the HM module → read-only store symlinks.
**Config changes go through the repo + `rb`, never through nexus.**

`programs.caelestia.settings` (→ `~/.config/caelestia/shell.json`), deviations
from defaults only:

```nix
settings = {
  paths.wallpaperDir = "~/wallpapers";                       # D11
  general.apps = {
    terminal = [ "kitty" ];                                  # default foot
    explorer = [ "nautilus" ];                               # default thunar
    playback = [ "celluloid" ];                              # default mpv
    audio    = [ "pwvucontrol" ];                            # 2.3.0 default is pavucontrol (main: pwvucontrol)
  };
  general.idle.timeouts = [                                  # D4
    { timeout = 600; idleAction = "dpms off"; returnAction = "dpms on"; }
  ];
  session = {                                                # D8
    commands.hibernate = [ "suspend" ];
    icons.hibernate = "bedtime";
  };
  bar.statusIcons = [                                        # desktop: audio on, battery off (full list — EntryList replaces)
    { id = "lockStatus"; enabled = true; }
    { id = "audio";      enabled = true; }
    { id = "network";    enabled = true; }
    { id = "bluetooth";  enabled = true; }
    { id = "battery";    enabled = false; }
  ];
  # Stock 2.3.0 list verbatim except Sleep: suspendThenHibernate → suspend (D8 —
  # hibernate is unavailable). The list replaces the defaults wholesale, so
  # every entry must be restated; `enableDangerousActions = false` still hides
  # Shutdown/Reboot/Logout.
  launcher.actions = [
    { name = "Calculator"; icon = "calculate";          description = "Do simple math equations (powered by Qalc)"; command = [ "autocomplete" "calc" ]; }
    { name = "Scheme";     icon = "palette";            description = "Change the current colour scheme";          command = [ "autocomplete" "scheme" ]; }
    { name = "Wallpaper";  icon = "image";              description = "Change the current wallpaper";              command = [ "autocomplete" "wallpaper" ]; }
    { name = "Variant";    icon = "colors";             description = "Change the current scheme variant";         command = [ "autocomplete" "variant" ]; }
    { name = "Random";     icon = "casino";             description = "Switch to a random wallpaper";              command = [ "caelestia" "wallpaper" "-r" ]; }
    { name = "Light";      icon = "light_mode";         description = "Change the scheme to light mode";           command = [ "setMode" "light" ]; }
    { name = "Dark";       icon = "dark_mode";          description = "Change the scheme to dark mode";            command = [ "setMode" "dark" ]; }
    { name = "Shutdown";   icon = "power_settings_new"; description = "Shutdown the system";                       command = [ "poweroff" ]; dangerous = true; }
    { name = "Reboot";     icon = "cached";             description = "Reboot the system";                         command = [ "reboot" ];   dangerous = true; }
    { name = "Logout";     icon = "exit_to_app";        description = "Log out of the current session";            command = [ "logout" ];   dangerous = true; }
    { name = "Lock";       icon = "lock";               description = "Lock the current session";                  command = [ "loginctl" "lock-session" ]; }
    { name = "Sleep";      icon = "bedtime";            description = "Suspend";                                   command = [ "suspend" ]; }
    { name = "Settings";   icon = "settings";           description = "Configure the shell";                       command = [ "caelestia" "shell" "nexus" "open" ]; }
  ];
};
```

Considered and **left at defaults** (recorded so nobody re-asks):
`services.smartScheme = true` (D5), `services.defaultPlayer = "Spotify"`,
`services.weatherLocation = ""` (auto; pin to `"lat,lon"`/city later if
wanted), `launcher.enableDangerousActions = false`,
`lock.enabled = true`, `general.idle.lockBeforeSleep = true` (suspend is manual
only, so this is just correct), `border.*` (rounded screen frame, 10 px),
`bar.entries`, `background.visualiser`/`desktopClock` off, `notifs.*`, `osd.*`,
`appearance.*`. Single monitor → no `monitors/<name>/shell.json` overrides.

`programs.caelestia.cli.settings` (→ `~/.config/caelestia/cli.json`):

```nix
cli.settings.theme = {
  enableSpicetify = false;   # spicetify-nix bakes the theme into the store Spotify; runtime color.ini is a no-op
  enableChromium  = false;   # `sudo -n tee` into /etc/brave/policies — fails silently on NixOS
  enableWarp = false; enableZed = false; enablePandora = false;   # not installed
  # enableTerm/Hypr/Discord/Gtk/Qt/Cava/Fuzzel/Btop/Htop/Nvtop: default true (consumers in 3.3)
  postHook = "${caelestia-theme-hook}/bin/caelestia-theme-hook";
};
```

`wallpaper.postHook` unused. `toggles.*` (special-workspace apps for
`caelestia toggle`) unused — no binds reference them.

### 3.3 Theming rewire, per consumer

Cascade after the swap: **wallpaper → `caelestia wallpaper -f|-r` →
`scheme.json` → caelestia-cli templates → apps → `theme.postHook`**. Every
consumer must tolerate "no scheme yet" (first login before any wallpaper is
set): the shell falls back to its bundled wallpaper + default scheme; the
others just show their static defaults.

| Consumer | Today | After | Repo change |
|---|---|---|---|
| Shell | `/tmp/qs_colors.json` → `Theme.qml` | reads `~/.local/state/caelestia/scheme.json` itself | — |
| Hyprland borders | `decorations.lua` `pcall(dofile "~/.cache/matugen/hypr-colors.lua")`, keys `primary`, `primary_container`, `inactive_border` (hex with `#`) | CLI writes `~/.config/hypr/scheme/current.lua` — a real file inside the HM-managed dir; fine because `recursive = true` only owns listed files. `decorations.lua` → `pcall(dofile, HOME .. "/.config/hypr/scheme/current.lua")`; keys `primary`, `primaryContainer`, `onSurfaceVariant` (hex **without** `#` → `"rgba(" .. hex .. alpha .. ")"`); static fallback kept. Active border `primary`ee → `primaryContainer`ee @45°; inactive `onSurfaceVariant`aa (matugen used `on_primary_fixed_variant`aa; upstream dots use `onSurfaceVariant`11 — keep our alpha). `theme.postHook` reloads Hyprland. | `decorations.lua` |
| kitty | `include /tmp/kitty-matugen-colors.conf` + SIGUSR1 | CLI writes OSC sequences into live `/dev/pts` and saves `sequences.txt`; new shells replay it (below). `extraConfig` removed. | `kitty.nix`, `bash.nix` |
| GTK 3/4 | HM `gtk3/gtk4.extraCss` `@import` + `dconf.settings` + gsettings bounce | CLI atomically writes `gtk-3.0/gtk.css`, `gtk-4.0/gtk.css` and sets dconf `gtk-theme`/`color-scheme`/`icon-theme` per apply. HM stops owning those: drop `extraCss` (else HM symlink vs CLI file fight every `rb`), drop `dconf.settings` (HM would reset keys on activation), drop `gtk-application-prefer-dark-theme` (light mode must be allowed). Keep `gtk.enable` and `gtk.theme = adw-gtk3-dark`: HM derives a dconf `gtk-theme` write from it, but caelestia writes the identical constant in both modes (it recolours via gtk.css), so the two never disagree. | `theme.nix` |
| Icons | Adwaita | **Not** via `gtk.iconTheme` — HM would derive a dconf `icon-theme = Papirus-Dark` write from it and reset caelestia's `Papirus-Light` on every activation. Instead: `papirus-icon-theme` in `home.packages` and `gtk.gtk3.extraConfig` / `gtk4.extraConfig` `gtk-icon-theme-name = "Papirus-Dark"` (settings.ini only, no dconf). The CLI then owns the dconf key and flips Dark/Light with mode. No folder recolouring (D10). | `theme.nix` |
| Qt | qt5ct/qt6ct + matugen `.conf`/`.qss`, `QT_QPA_PLATFORMTHEME=qt6ct` | CLI writes `~/.config/qtengine/caelestia.colors` + `config.json` (style `Darkly`). HM: `qt = { enable = true; platformTheme = { name = "qtengine"; package = pkgs.qtengine; }; }` (`name` is a free string → `QT_QPA_PLATFORMTHEME=qtengine`; `qt.enable` exports `QT_PLUGIN_PATH` to the profile so the plugin is found) + `pkgs.darkly`. `env.lua` `QT_QPA_PLATFORMTHEME` → `qtengine`. `qt5ct`/`qt6ct` packages removed. | `theme.nix`, `env.lua` |
| Discord (vesktop) | `matugen.theme.css` | `~/.config/vesktop/themes/caelestia.theme.css`; enable once in Vesktop → Themes (runbook). | — |
| cava | `~/.config/cava/colors` + `config_base` merge in `matugen-reload` | CLI writes the full `~/.config/cava/config` + SIGUSR2. | — |
| Spicetify | untouched | `enableSpicetify = false`; keep `text`. | — |
| btop/htop | untouched | CLI writes `~/.config/btop/themes/caelestia.theme`; selecting it is a one-time btop UI toggle, not repo work. Left enabled. | — |
| Brave | untouched | off (3.2). | — |
| Fonts | `fonts.nix` pins for island | shell brings its own fontconfig (1.2). | `fonts.nix` |

`bash.nix` `initExtra` addition:

```bash
# caelestia-cli themes live terminals by writing OSC colour sequences into
# every /dev/pts; new shells replay the saved copy so fresh kitty windows match.
_cs="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/sequences.txt"
if [ -t 1 ] && [ -f "$_cs" ]; then cat "$_cs"; fi
unset _cs
```

`theme.nix` after the change (whole file, for clarity):

```nix
{ pkgs, ... }: {
  gtk = {
    enable = true;
    theme = { name = "adw-gtk3-dark"; package = pkgs.adw-gtk3; };   # caelestia writes the same name in both modes
    # No gtk.iconTheme: HM would also write dconf icon-theme and undo caelestia's
    # Papirus-Light in light mode on every activation. settings.ini only:
    gtk3.extraConfig.gtk-icon-theme-name = "Papirus-Dark";
    gtk4.extraConfig.gtk-icon-theme-name = "Papirus-Dark";
    # gtk.css and the remaining dconf keys are written by caelestia-cli on every scheme apply.
  };
  qt = {
    enable = true;
    platformTheme = { name = "qtengine"; package = pkgs.qtengine; };
  };
  home.packages = [
    pkgs.papirus-icon-theme
    pkgs.darkly   # Qt6 style named in caelestia's qtengine config
  ];
}
```

### 3.4 Hyprland Lua

**`binds.lua`** — `mainMod = "ALT"` unchanged; window/workspace/mouse binds
unchanged. jftx's keyboard emits plain F-keys (F1/F2 brightness, F7–F9 media,
F10–F12 volume); XF86 names stay as aliases for other keyboards.

| Key | Today | After |
|---|---|---|
| ALT+SPACE | `global quickshell:launcher` | `global caelestia:launcher` |
| SUPER+V | `global quickshell:control` | `global caelestia:utilities` (quick toggles — closest to the old control center) |
| ALT+N | — | `global caelestia:sidebar` (notification centre) |
| ALT+SHIFT+N | — | `global caelestia:clearNotifs`, `{ locked = true }` |
| ALT+D | — | `global caelestia:dashboard` |
| ALT+M | `hyprshutdown`/`hl.dsp.exit()` | `global caelestia:session` |
| ALT+L | — | `global caelestia:lock` |
| ALT+W | `systemctl --user start wallpaper.service` | `exec caelestia wallpaper -r /home/jftx/wallpapers` |
| ALT+SHIFT+W | `global quickshell:wallpapers` | **removed** (`>wallpaper` in the launcher) |
| ALT+S | grim/slurp → file + clipboard + notify | `global caelestia:screenshotClip` (region → clipboard + notification) |
| ALT+SHIFT+S | — | `global caelestia:screenshot` (region → swappy → save to `~/Pictures/Screenshots`) |
| ALT+C / ALT+SHIFT+C | — | `exec pkill fuzzel \|\| caelestia clipboard` / `… clipboard -d` |
| ALT+PERIOD | — | `exec pkill fuzzel \|\| caelestia emoji -p` |
| ALT+SHIFT+R | — | `exec systemctl --user restart caelestia` |
| F1 / F2, XF86MonBrightness{Down,Up} | `brightnessctl` | `global caelestia:brightnessDown` / `brightnessUp`, `{ locked = true, repeating = true }` |
| F7 / F8 / F9, XF86Audio{Prev,Play,Pause,Next} | `playerctl` | `global caelestia:mediaPrev` / `mediaToggle` / `mediaNext`, `{ locked = true }` |
| F12 / F11, XF86Audio{Raise,Lower}Volume | `global quickshell:volume{Up,Down}` | `exec wpctl set-mute @DEFAULT_AUDIO_SINK@ 0; wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+` / `… 5%-`, `{ locked = true, repeating = true }` |
| F10, XF86AudioMute | `global quickshell:volumeMute` | `exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle`, `{ locked = true }` |
| XF86AudioMicMute | `wpctl … @DEFAULT_AUDIO_SOURCE@ toggle` | unchanged |

Known trade-off: ALT+D / ALT+L / ALT+C shadow Alt-accelerators in some apps
(Brave address bar etc.), like ALT+W already does. Move to ALT+SHIFT if it
bites — one-line change each.

**`autostart.lua`:** remove `awww-daemon`; add `wl-paste --type text --watch
cliphist store` and `wl-paste --type image --watch cliphist store`. Caelestia
itself is **not** exec'd here (systemd starts it from
`graphical-session.target`).

**`env.lua`:** `QT_QPA_PLATFORMTHEME` `qt6ct` → `qtengine`; drop the duplicated
`QT_QPA_PLATFORM` line.

**`decorations.lua`:** per 3.3.

**`misc.lua`:** add `allow_session_lock_restore = true`. If the shell dies
while the screen is locked, Hyprland keeps the session locked; this lets a
restarted caelestia re-attach as the lock client (upstream's "restore lock"
bind relies on the same option) instead of leaving a dead lock.

**`windowrules.lua`:** add float rules for classes `swappy` and
`com.saivert.pwvucontrol`. No layer rules (caelestia surfaces are layer-shell
and animate themselves).

### 3.5 Deletions & cleanup

Repo (in the PR):

| Path | Action |
|---|---|
| `modules/home/desktop/quickshell/` (whole tree) | delete |
| `modules/home/desktop/quickshell.nix` | delete (→ `desktop/caelestia.nix`) |
| `modules/home/programs/matugen.nix`, `modules/home/programs/matugen/` | delete |
| `modules/home/services/wallpaper.nix`, `modules/home/services/scripts/` | delete |
| `modules/home/default.nix` | imports −matugen −wallpaper −quickshell +`desktop/caelestia.nix` |
| `modules/system/packages.nix` | −awww −matugen −rofi −grim −slurp −playerctl |
| `modules/system/fonts.nix` | −jetbrains-mono −nerd-fonts.iosevka; comment |
| `modules/system/hyprland.nix` | +power-profiles-daemon +i2c; comment |
| `hosts/blackgarden/default.nix` | +`i2c` group |
| `modules/home/desktop/theme.nix` | rewrite (3.3) |
| `modules/home/programs/kitty.nix` | −`extraConfig` |
| `modules/home/programs/bash.nix` | `rb` alias → `… && systemctl --user restart caelestia`; +sequences replay |
| `modules/home/desktop/hypr/modules/{binds,autostart,env,decorations,misc,windowrules}.lua` | per 3.4 |
| `flake.nix` | +input |
| `docs/plans/quickshell-matugen-migration.md` | keep; prepend "SUPERSEDED by this spec" banner. The eight island specs/plans stay untouched as history. |
| `CLAUDE.md` | per 3.6 |
| git tag `island-final` | on the last pre-swap `main` commit, pushed |

On disk (runbook, by hand; not repo-owned):

- HM removes its own symlinks on activation: `~/.config/quickshell/island`,
  `~/.config/matugen`, `~/.config/gtk-{3,4}.0/gtk.css`, and the
  `wallpaper.service`/`wallpaper.timer`/`quickshell.service` units (sd-switch
  stops them).
- Matugen runtime outputs linger and are removed manually:
  `~/.cache/matugen/`, `~/.config/qt5ct/`, `~/.config/qt6ct/`,
  `~/.config/vesktop/themes/matugen.theme.css`, `~/.config/cava/colors`,
  `~/.config/cava/config_base`, `~/.local/state/wallpaper-current`,
  `~/.local/state/wallpaper-next`. `/tmp/qs_colors.json` and
  `/tmp/kitty-matugen-colors.conf` die with the tmpfs.
- `awww-daemon` from the old session keeps drawing under caelestia's background
  layer, and the new session variables (`QT_QPA_PLATFORMTHEME`,
  `QT_PLUGIN_PATH`, `CAELESTIA_WALLPAPERS_DIR`) only apply on a fresh login:
  **first activation is `rb` → reboot**.
- The old `rb` alias in already-open terminals ends with `systemctl --user
  restart quickshell`, which errors once ("unit not found") *after* the switch
  succeeded. Expected.

### 3.6 Docs & process

- **Issue/branch/PR:** #24, `feat/caelestia-shell`, one PR. Commits grouped:
  (1) tag + delete island/matugen/wallpaper, (2) flake input +
  `caelestia.nix`, (3) theme/kitty/bash/packages/system rewire, (4) Hyprland
  Lua, (5) docs. Standard attribution trailer.
- **Trackers:** close #7 and #17 with a comment pointing at the PR
  (caelestia's dashboard supersedes the calendar/weather section);
  `feat/cc-calendar-weather` left for jftx to delete.
- **CLAUDE.md** — rewritten only where it's now wrong: Overview (island →
  caelestia, matugen → caelestia-cli, GRUB → lanzaboote/systemd-boot);
  Key Commands (`rb` tail); Layout (`desktop/{hyprland,theme,caelestia}.nix`,
  no QML in-repo; "shell config → `caelestia.nix` settings/cli.settings");
  Architecture Notes: the "Island shell" and "Theming pipeline" paragraphs
  become one "Caelestia shell + theming" paragraph carrying the rules that
  survive — systemd owns the single instance (never `caelestia shell -d`), it
  *is* the notification daemon (never add another), the cascade and where its
  outputs live, `wallpaper-set`/`wallpaper.timer` are gone (front door
  `caelestia wallpaper -f`), shell.json is read-only so nexus can't save,
  `caelestia shell -s` lists IPC; Boot/GC bullet: lanzaboote, and a one-liner
  that `system.autoUpgrade` does not work on this machine.
- **Claude memory:** `quickshell-matugen-migration.md` replaced by a
  `caelestia-shell.md` note; index updated.
- **This spec** committed on the branch before implementation; the
  implementation plan (`docs/superpowers/plans/2026-09-14-caelestia-shell-swap.md`)
  follows from it after the Codex review.

### 3.7 Verification, runbook, rollback, risks

**Pre-activation (Claude, on the branch):**

1. `git add` all new files (flake purity), `nix flake check`.
2. `trb` (`nixos-rebuild build --flake ~/nixos#blackgarden --sudo`) — full
   build; shellcheck runs on `caelestia-theme-hook`.
3. Read the generated files out of the build result: `shell.json`, `cli.json`,
   `swappy/config`, the deployed `hypr/` tree, `caelestia.service` unit text
   (`ExecStart`, `Environment=`, `WantedBy`).
4. `stylua --check` on the Lua; `grep -rn 'quickshell\|matugen\|awww\|rofi\|playerctl' --include=*.nix --include=*.lua` → no hits.
5. `nix eval` of `home.sessionVariables` (`QT_QPA_PLATFORMTHEME`,
   `QT_PLUGIN_PATH`, `CAELESTIA_WALLPAPERS_DIR`).

**Activation runbook (jftx; paste output back — Claude never runs `rb`):**

1. Tag: `git tag island-final <last pre-swap main sha> && git push origin island-final` (done at PR time).
2. Merge the PR; `git pull` on `main`.
3. `rb`. Expect the old alias's trailing `restart quickshell` error; HM may
   print `gtk.css` backup notices. **Reboot.**
4. `systemctl --user status caelestia` → active; left bar visible;
   `caelestia shell -s` lists IPC; `systemctl --user show-environment | grep
   HYPRLAND_INSTANCE_SIGNATURE` prints the current instance.
5. **Bootstrap the scheme:** `caelestia wallpaper -f ~/wallpapers/moon.jpg`.
   Check in order: wallpaper fades in; bar recolours; open kitty windows
   recolour; `ls ~/.local/state/caelestia/` shows `scheme.json` +
   `sequences.txt`; `~/.config/hypr/scheme/current.lua` exists (**`.lua`, not
   `.conf`** — `.conf` means the CLI could not reach Hyprland) and window
   borders recolour (hook fired); `~/.config/gtk-3.0/gtk.css` is a regular
   file; `~/.config/qtengine/config.json` exists.
6. Smart scheme: a bright wallpaper → desktop (kitty/GTK too) goes light; a
   dark one → back.
7. Binds: ALT+SPACE; type `>w` → grid, pick one. SUPER+V, ALT+N, ALT+D. ALT+M
   opens the session drawer — Esc, don't click. F10/F11/F12 OSD. F7/F8/F9 with
   Spotify open. `ddcutil detect`, then F1/F2. ALT+S (check clipboard),
   ALT+SHIFT+S (swappy → save → `~/Pictures/Screenshots`). Copy two things →
   ALT+C. ALT+PERIOD.
8. **Lock, with an escape hatch:** `Ctrl+Alt+F2`, log in on TTY2, back to
   TTY1, then ALT+L. If PAM refuses the password, from TTY2 — in this order:
   (a) `caelestia shell lock unlock` (IPC on the *live* shell; never kill it
   first — a lock client that exits leaves the compositor locked);
   (b) only if (a) fails: `systemctl --user restart caelestia && caelestia
   shell lock lock` — with `allow_session_lock_restore` the new instance
   re-attaches as the lock client, then unlock from TTY1 (or `lock unlock`
   again from TTY2);
   (c) last resort: `systemctl reboot` from TTY2.
9. `notify-send test hello` → caelestia toast. Vesktop → Themes → enable
   `caelestia.theme.css`.
10. Cleanup: `rm -rf ~/.cache/matugen ~/.config/qt5ct ~/.config/qt6ct
    ~/.config/vesktop/themes/matugen.theme.css ~/.config/cava/colors
    ~/.config/cava/config_base ~/.local/state/wallpaper-current
    ~/.local/state/wallpaper-next`; `find ~/.config -name '*.backup'` and
    delete stale ones.
11. Open a new terminal: new `rb` alias, kitty colours from the sequences replay.

**Rollback:** `sudo nixos-rebuild switch --rollback` (or the previous
generation in systemd-boot) → reboot → island returns; matugen outputs
regenerate 5 s after login via the old timer bootstrap. Repo: `git revert` the
merge, or `git checkout island-final`. Caelestia leftovers
(`~/.local/state/caelestia`, `~/.config/{caelestia,qtengine,hypr/scheme}`, the
real `gtk.css` files — HM's `backupFileExtension` handles that collision) are
inert.

**Open risks (unverifiable without running it):**

1. **Lock/PAM on NixOS** — nixpkgs patches caelestia's bundled pam.d,
   implying it works; unverified here → runbook step 8 with the TTY2 hatch.
2. **Hyprland socket from the service environment** — verified present on
   the live system (1.2), which is what makes caelestia-cli write
   `current.lua` rather than `current.conf`. The hook's runtime-dir discovery
   only guards `hyprctl reload` if that ever regresses; it cannot fix a wrong
   output format, so runbook step 5 checks the extension explicitly. If
   Hyprland already auto-reloads on `dofile`d file changes, the hook is a
   harmless double reload.
3. **Icon theme name in light mode** — HM's `settings.ini` says
   `Papirus-Dark`, caelestia's dconf says `Papirus-Light`; cosmetic.
4. **Weight** — caelestia is heavier than the island (blur, dashboard, media
   hooks); `background.visualiser` stays off. Watch idle GPU/CPU the first day.
5. **First-`rb` HM collisions** — `gtk.css` handoff is understood; anything
   else shows in the activation output, which is why it's pasted back.
6. **2.3.0 vs `main` drift** — every key, shortcut name, default and the full
   launcher action list used here was read from the 2.3.0 tarball (an earlier
   draft wrongly claimed Random/Shutdown/Sleep were `main`-only; they are not,
   hence the `launcher.actions` override). Known 2.3.0/`main` differences that
   touched this design: `general.apps.audio` default (pavucontrol vs
   pwvucontrol).
7. **Nexus can't save** (read-only shell.json) — by design; documented in
   CLAUDE.md.
8. **Session lock survivability** — a crashed/killed lock client leaves the
   compositor locked. Mitigated by `misc.allow_session_lock_restore` (3.4),
   the `caelestia shell lock unlock` IPC, and the ordered escape hatch in
   runbook step 8.

---

## 4. Out of scope / follow-ups (not in this PR)

- Screen recording (`caelestia record`, gpu-screen-recorder).
- Spicetify theming from caelestia (needs a runtime-colour theme for
  spicetify-nix — none today).
- Brave theming (caelestia's policy write needs `/etc` access; a static NixOS
  policy could set a fixed colour but not follow the wallpaper).
- Papirus folder recolouring (D10).
- Bar layout tuning (`bar.entries`, workspace count/labels, `border.*`,
  transparency), weather location pin, btop theme selection — all one-line
  `settings` changes once the shell is in.
- Bumping to caelestia 2.4.0: wait for nixpkgs (`nix flake update`). A bare
  `src` override is not enough — nixpkgs builds the QML plugin, `extras` and
  `m3shapes` as separate derivations with their own source pins, so all of
  them move together.
- Fixing or removing the dead `system.autoUpgrade` block in `boot.nix`.
- Deleting `feat/cc-calendar-weather`.

---

## 5. Review log — Codex second opinion (2026-09-14)

jftx pasted this spec into Codex; it read the pinned nixpkgs/HM sources,
extracted the 2.3.0 tarball and ran isolated `nix eval`s. Each finding was
re-verified here before being applied.

| # | Codex finding | Verdict | Disposition |
|---|---|---|---|
| 1 | 2.3.0's launcher already ships Random/Shutdown/Sleep; Sleep runs `suspendThenHibernate` and is not `dangerous`, so gating doesn't hide it | **Confirmed** (`launcherconfig.hpp` 2.3.0) — my earlier grep was case-sensitive and missed them | `launcher.actions` overridden with the stock list, Sleep → `suspend` (3.2); 1.2 and risk 6 corrected |
| 2 | Restarting the shell while locked can leave the compositor locked; use `caelestia shell lock unlock` first | **Confirmed** (`Lock.qml` IPC `lock`/`unlock`/`isLocked` in 2.3.0; Quickshell/Hyprland lock semantics) | Runbook step 8 rewritten as an ordered hatch; `misc.allow_session_lock_restore = true` added (3.4); risk 8 |
| 3 | `cliphist` is only on the CLI wrapper's PATH, not Hyprland's; `ddcutil detect` likewise | **Confirmed** (user PATH checked live; wrappers use `--prefix PATH`) | `pkgs.cliphist`, `pkgs.ddcutil` added to `home.packages` (3.1) |
| 4 | HM still writes dconf `gtk-theme`/`icon-theme` from `gtk.theme`/`gtk.iconTheme`, resetting caelestia's `Papirus-Light` on activation | **Confirmed** (`modules/misc/gtk/gtk3.nix` derives `dconf.settings."org/gnome/desktop/interface"` from those options) | `gtk.iconTheme` dropped; Papirus via `home.packages` + `gtk{3,4}.extraConfig.gtk-icon-theme-name` (settings.ini only). `gtk.theme` kept: its dconf value equals caelestia's constant (3.3) |
| 5 | The post-hook's signature discovery runs too late — the CLI needs `HYPRLAND_INSTANCE_SIGNATURE` earlier to detect Lua, else it writes `current.conf` | **Refuted on this host**: `systemctl --user show-environment` carries the signature (UWSM exports it), so the service and its CLI children have it from the start. The mechanism Codex describes is real, so it is now stated in 1.2 and checked in runbook steps 4–5 | Hook unchanged (still useful as `hyprctl` insurance); risk 2 rewritten |
| 6a | 2.3.0's `general.apps.audio` default is `pavucontrol`, not `pwvucontrol` | **Confirmed** (`generalconfig.hpp` 2.3.0) | `audio = [ "pwvucontrol" ]` set explicitly (3.2) |
| 6b | A shell-only `src` override is not a valid 2.4.0 upgrade path (plugin/extras/m3shapes are separate derivations) | **Accepted** | Follow-up reworded (§4) |
