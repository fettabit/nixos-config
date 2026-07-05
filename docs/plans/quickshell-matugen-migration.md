# Quickshell + Matugen Desktop Shell Migration

**Status:** awaiting approval (written 2026-07-04, Phase 3 of the migration brief)
**Reference:** https://github.com/ilyamiro/nixos-configuration @ `d66c4a5` (master, 2026-05/06 state — v2.0.0 announced but unreleased as of 2026-07-04; master is the correct base)
**Local clone used for recon:** re-clone when implementing; do not vendor his git history.

This document is self-contained: a future Claude Code session can execute it without re-deriving context. Decisions below were confirmed with jftx in the 2026-07-04 gap interview.

---

## Locked-in decisions (from gap interview)

| Topic | Decision |
|---|---|
| Bar | **Not** a port of his TopBar. Build an iOS-style **dynamic island**: floating centered pill showing only the clock, which expands/morphs when features open. Reuse his `Main.qml` morphing-window machinery as the engine. |
| Theming | Matugen is canonical. Wallpaper-driven, regenerates on **every** wallpaper change including the existing 10-min systemd timer. Dark mode always. Drives *everything it can touch* incl. Hyprland window decorations. |
| Wallpapers | `~/wallpapers`, backend is **awww** (swww successor, CLI-compatible). **No video wallpapers** — strip mpvpaper/QtMultimedia paths from the picker. Adopt his `WallpaperPicker.qml` (full aesthetic). |
| Keybinds | Keep jftx's ALT binds where they exist: `ALT+SPACE` = app launcher (replacing rofi drun), `ALT+Q` = close window, `ALT+W` / `ALT+SHIFT+W` = wallpaper random/picker. Everything else follows the reference (SUPER+… → `qs_manager.sh`). |
| Incumbents | Waybar, swaync, rofi-launcher get **removed from autostart/binds but files kept in repo** for now. |
| Scope now | **Core tier only**: island bar, notifications, app launcher, volume popup (+swayosd), wallpaper picker, full Matugen pipeline. Panels/Session/Extras are planned (see roadmap) for later sessions. |
| swayosd | Yes, use it (volume/capslock OSD; brightness keys are irrelevant on this desktop). |
| Bluetooth | Enable `hardware.bluetooth` (machine has BT; needed later by network popup). |
| Consumers | Quickshell, Hyprland decorations, kitty, GTK3/4 + Qt (qt6ct + adw-gtk3), vesktop, firefox userChrome, cava, swayosd CSS. Spicetify deferred (Nix-managed; runtime regen fights the declarative build). Rofi templates skipped (rofi is being retired as launcher). |
| Git workflow | Feature branches off `main`, GitHub issues per track, PRs. Claude may run `nix flake check` and `nixos-rebuild build` (`trb`) itself. **`rb` (switch) is run by jftx only** — stop, ask, and wait for pasted output. |

## Hardware/context facts (verified 2026-07-04)

- Host `blackgarden`: desktop, single monitor **DP-3 5120×1440@240, scale 1** (super-ultrawide; reference shell was tuned on 1920×1080 — all sizing must be re-audited).
- No battery, no backlight. Bluetooth hardware present but not yet enabled in NixOS config.
- Flake tracks **nixos-unstable** (CLAUDE.md stale — says 26.05). Available: quickshell 0.3.0, matugen 4.1.0, hyprland 0.55.4.
- Already installed: quickshell, qt6.qtdeclarative, awww, cava, playerctl, grim, slurp, swaynotificationcenter, waybar, rofi, wl-clipboard, networkmanagerapplet, nerd-fonts.jetbrains-mono. NetworkManager + PipeWire active.
- Missing for core: **matugen**, swayosd, `jetbrains-mono` (plain family — QML hardcodes `"JetBrains Mono"`), `nerd-fonts.iosevka` (QML hardcodes `"Iosevka Nerd Font"`), qt6ct/qt5ct, adw-gtk3, adwaita-icon-theme, `programs.dconf.enable`, `hardware.bluetooth.enable`.
- Missing for later tiers: hypridle, satty (screenshot annotation), cliphist (clipboard history).

---

## 3.1 Current architecture (jftx's repo)

`flake.nix` (nixos-unstable + home-manager + spicetify-nix) → `hosts/blackgarden` + `modules/system/*` (system) and `modules/home/*` via HM-as-NixOS-module (`useGlobalPkgs`, `backupFileExtension = "backup"`).

Session path: getty autologin on TTY1 → `bash.nix profileExtra` → `uwsm start hyprland-uwsm.desktop` → Hyprland reads **hand-written Lua** at `~/.config/hypr/hyprland.lua` (materialized from `modules/home/desktop/hypr/` via `xdg.configFile."hypr"` with `recursive = true`; per-file read-only store symlinks in a writable real dir) → `modules/autostart.lua` execs **waybar, swaync, awww-daemon**.

Dotfile strategy: `programs.*` HM modules where available (kitty, git, bash, spicetify), raw `xdg.configFile` for hand-written trees (hypr Lua, waybar). Custom scripts as `pkgs.writeShellApplication` (wallpaper-random/picker). Wallpaper: `wallpaper.service` (oneshot) + `wallpaper.timer` (5 s after login, every 10 min; `ALT+W` restarts service, resetting the countdown); picks random image from `~/wallpapers`, records to `~/.local/state/wallpaper-current`, applies via `awww img`.

**No theming pipeline exists.** Waybar CSS is hand-written; Hyprland borders are hardcoded cyan/green gradient in `decorations.lua`; kitty has no color scheme set.

## 3.2 Reference architecture (ilyamiro)

Channel-based NixOS (no flake), HM as NixOS module. Everything under `config/` wired with `mkOutOfStoreSymlink "/etc/nixos/config/..."` — this is what "Do NOT install it on NixOS" means: hardcoded machine-specific paths, not Arch-isms. The shell itself is portable.

**Shell**: `exec-once = quickshell -p ~/.config/hypr/scripts/quickshell/Shell.qml`. `Shell.qml` (15 lines) loads:
- `Main {}` (530 lines): IPC dispatcher (`IpcHandler` named `main`, method `handleCommand(action, target, arg)`), a single **morphing master window** hosting all popups (animated `animW/animH/animX/animY`, widget cache/preload, layouts from `WindowRegistry.js`), and the **notification daemon** (`Quickshell.Services.Notifications` → `notifications/NotificationPopups.qml`).
- `TopBar {}` (1567 lines): full-width bar, native `Quickshell.Services.SystemTray`. **We are not porting this** (island instead).
- `Floating {}` (desktop widgets — out of scope for now).

All keybinds route through `scripts/qs_manager.sh`: fast-path workspace switching (closes popups first), zombie-watchdog respawn of quickshell, cache prep (wallpaper thumbnails via imagemagick, network scans), then `quickshell ... ipc call main handleCommand …`. Support singletons: `Config.qml` (settings.json via jq, env), `Caching.qml` (XDG cache/state/run dirs per widget), `SysData.qml`, `Scaler.qml`.

**Theming flow (the architecture to replicate)**:
1. Trigger: `WallpaperPicker.qml` runs `matugen image <cached-thumbnail>` then `matugen_reload.sh`.
2. Matugen (`~/.config/matugen/config.toml`) renders templates → `/tmp/qs_colors.json` (Quickshell), `~/.config/hypr/colors.conf` (sourced by hyprland.conf), `/tmp/kitty-matugen-colors.conf`, `~/.cache/matugen/colors-gtk.css`, qt5ct/qt6ct scheme+qss, `~/.config/cava/colors`, `~/.config/swayosd/style.css`, vesktop theme css, firefox userChrome css.
3. `MatugenColors.qml`: component instantiated by every widget (`MatugenColors { id: _theme }`); polls `/tmp/qs_colors.json` every 1 s (`cat` Process + Timer); exposes typed `color` properties with **Catppuccin Mocha names mapped from Material-You tokens** (`base`←surface_container_lowest, `blue`←primary, `peach`←tertiary, …), Mocha hexes as fallback defaults. QML bindings repaint everything live.
4. `matugen_reload.sh`: kitty `SIGUSR1` (process name `.kitty-wrapped` on NixOS), cava config rebuild + `SIGUSR1`, swayosd service restart (known audio-pop side effect), GTK live-reload hack (gsettings theme toggle Adwaita→adw-gtk3-dark, color-scheme default→prefer-dark).

Templates are declarative; outputs are runtime state (`/tmp`, `~/.cache`) — coexists cleanly with Nix.

**Known reference-repo defects**: `autostart.conf` references `settings_watcher.sh` which doesn't exist anywhere; `templates/*.conf.template` under `sessions/hyprland/` is consumed by nothing. Skip both. Font families hardcoded in QML: `"JetBrains Mono"`, `"Iosevka Nerd Font"`. QtMultimedia is imported only by `UpdaterPopup.qml` (excluded) and `WallpaperPicker.qml` (only for video wallpaper — being stripped). `Qt.labs.folderlistmodel` (picker) ships with qtdeclarative. PAM only in `Lock.qml` (later tier).

## 3.3 Delta — what changes in jftx's repo

### New files
```
modules/home/programs/matugen.nix          # xdg.configFile."matugen" ← ./matugen (config.toml + templates/)
modules/home/programs/matugen/config.toml
modules/home/programs/matugen/templates/qs_colors.json.template      # from reference
modules/home/programs/matugen/templates/hypr-colors.lua.template     # NEW — Lua table (see 3.4)
modules/home/programs/matugen/templates/kitty-colors.conf.template   # from reference
modules/home/programs/matugen/templates/gtk.css.template             # from reference
modules/home/programs/matugen/templates/qtct.conf.template           # from reference
modules/home/programs/matugen/templates/qt-style.qss.template        # from reference
modules/home/programs/matugen/templates/swayosd.css.template         # from reference
modules/home/programs/matugen/templates/discord.css.template         # → vesktop
modules/home/programs/matugen/templates/firefox.css                  # profile path fixed at impl time
modules/home/programs/matugen/templates/cava-colors.ini.template     # from reference
modules/home/desktop/quickshell.nix        # materialize QML tree + launch deps
modules/home/desktop/quickshell/           # adapted QML tree (see below)
modules/home/desktop/theme.nix             # gtk (adw-gtk3-dark + matugen css import), qt (qt6ct), dconf, cursor
docs/plans/quickshell-matugen-migration.md # this file
```

QML tree (`modules/home/desktop/quickshell/`), adapted from reference `scripts/quickshell/`:
- Keep near-verbatim: `MatugenColors.qml`, `Caching.qml`, `Config.qml`, `SysData.qml`, `Scaler.qml`, `WindowRegistry.js`, `notifications/`, `applauncher/` (+`app_fetcher.py`, stdlib-only), `volume/` (audio_control.sh, get_audio_state.py, VolumePopup.qml), `watchers/` (only audio for core).
- Adapt heavily: `Main.qml` → island engine (collapsed state = visible clock pill instead of hidden), new `island/IslandBar.qml` (or collapsed-state content inside Main) — clock only, expands on feature open; `WallpaperPicker.qml` (swww→awww rename, strip mpvpaper/video branches and `import QtMultimedia`, wallpaper dir `~/wallpapers`, on-select: write `~/.local/state/wallpaper-current` to stay compatible with wallpaper-random's no-repeat logic); `Shell.qml` (no TopBar/Floating).
- Scripts: `qs_manager.sh` + `caching.sh` (path adaptations: QML tree at `~/.config/quickshell`, `WALLPAPER_DIR=$HOME/wallpapers`).
- Do NOT vendor: TopBar.qml, Floating.qml, stewart/, movies/, updater/, focustime/, guide previews (defer guide), calendar/, network/, music/, monitors/, settings/, clipboard/, quickactions/, Lock.qml (all later tiers — vendor when their tier starts).

### Modified files
```
modules/system/packages.nix    # + matugen (used by scripts too), jetbrains-mono handled in fonts.nix
modules/system/fonts.nix       # + jetbrains-mono, nerd-fonts.iosevka
modules/system/network.nix     # + hardware.bluetooth.enable = true; powerOnBoot (or new bluetooth.nix)
modules/system/default.nix     # if new module files added
modules/system/<new or packages> # programs.dconf.enable = true
modules/home/default.nix       # import matugen.nix, quickshell.nix, theme.nix
modules/home/packages.nix      # + libsForQt5.qt5ct, qt6Packages.qt6ct, adw-gtk3, adwaita-icon-theme
modules/home/services/wallpaper.nix         # matugen + matugen-reload writeShellApplication; runtimeInputs += matugen
modules/home/services/scripts/wallpaper-random.sh  # run `matugen image "$pick"` + matugen-reload BEFORE `exec awww img`
modules/home/services/scripts/wallpaper-picker.sh  # same hook (kept as fallback picker)
modules/home/programs/kitty.nix             # extraConfig: include /tmp/kitty-matugen-colors.conf
modules/home/desktop/hypr/modules/decorations.lua  # dofile ~/.cache/matugen/hypr-colors.lua with pcall + current colors as fallback
modules/home/desktop/hypr/modules/autostart.lua    # (step 6) quickshell + swayosd replace waybar + swaync
modules/home/desktop/hypr/modules/binds.lua        # ALT+SPACE → launcher IPC; SUPER popups → qs_manager; keep ALT set
modules/home/desktop/hypr/modules/windowrules.lua  # layerrules: noanim volume_osd; launcher rules sized for 5120×1440
CLAUDE.md                                          # fix staleness: unstable channel, waybar→island, wallpaper service, this plan
```

Home-manager module additions: `services.swayosd.enable = true` (HM ships this module; styleSheet → matugen output path).

### Explicitly NOT added
mpvpaper (no video), eww, blueman (bluetoothctl is enough for later network popup), swaync replacement config (quickshell is the daemon), his plymouth/rofi/zsh/neovim configs.

## 3.4 Integration strategy

**Branching**: `feat/matugen-pipeline` → PR → merge, then `feat/quickshell-core` → PR → merge (theming lands independently and is useful even without the shell). GitHub issues per track (theming pipeline / island shell / later tiers) via `gh`. Small commits per step below. Claude runs `nix flake check` + `nixos-rebuild build --flake ~/nixos#blackgarden` freely; **every activation (`rb`) is done by jftx** — stop and request it, wait for pasted output.

**QML source-of-truth & iteration speed**: repo dir `modules/home/desktop/quickshell/` materialized to `~/.config/quickshell` via `xdg.configFile."quickshell" = { source = …; recursive = true; }`. During the dev phase, use `mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/modules/home/desktop/quickshell"` instead, so QML edits are live (quickshell hot-reloads on file change) without a rebuild per tweak; **final step of the core PR switches it to the pure store source** (reproducibility restored, matching the hypr-Lua workflow: edit in repo → rb).

**Hyprland-Lua × Matugen (the one genuinely novel adaptation)**: the reference sources a generated `colors.conf`; jftx's config is Lua, so instead Matugen renders a **Lua table** to `~/.cache/matugen/hypr-colors.lua`:
```lua
return { primary = "{{colors.primary.default.hex}}", surface = "{{colors.surface.default.hex}}", … }
```
`decorations.lua` loads it defensively: `local ok, c = pcall(dofile, os.getenv("HOME") .. "/.cache/matugen/hypr-colors.lua")` and falls back to the current hardcoded palette when absent (first boot before any generation). `matugen-reload` runs `hyprctl reload` so border colors apply. Output goes to `~/.cache/matugen/` — never into `~/.config/hypr` (store-symlinked files; HM owns that tree).

**Matugen as source of truth vs Nix reproducibility**: templates + config.toml are declarative (repo, store). Outputs are runtime artifacts at `/tmp`, `~/.cache`, `~/.config/vesktop/themes`, etc. Every consumer must have a sane no-output fallback: QML defaults (Catppuccin, already built into MatugenColors.qml), Lua pcall fallback, kitty `include` of a possibly-missing file (kitty warns but works), GTK `@import` of missing css (ignored). The wallpaper timer fires 5 s after login, so a fresh boot self-heals within seconds.

**Incumbent coexistence**: waybar + swaync keep running untouched through steps 1–5. Quickshell is launched **manually** for all of steps 4–5 (`quickshell -p ~/.config/quickshell/Shell.qml` in a kitty). Only step 6 flips autostart — one commit, trivially revertible, and old files stay in the repo. The island and waybar can coexist visually (island is a floating centered pill; waybar is an edge bar). The **only hard conflict is notifications**: quickshell and swaync both claim `org.freedesktop.Notifications`, so swaync is stopped/removed from autostart *in the same change* that enables quickshell notifications (step 5c), not before, not after.

**Reference-repo adaptation rules** (apply everywhere): replace `mkOutOfStoreSymlink /etc/nixos/...` with repo-relative store sources; replace `~/.config/hypr/scripts/quickshell` paths with `~/.config/quickshell`; `swww`→`awww`, `swww-daemon`→`awww-daemon` (already autostarted); `$HOME/Pictures/Wallpapers`→`$HOME/wallpapers`; hardcoded `/home/ilyamiro`→`$HOME`/`Quickshell.env("HOME")`; drop his firefox profile hash, detect jftx's (`~/.mozilla/firefox/*.default*`) at impl time + set `toolkit.legacyUserProfileCustomizations.stylesheets`.

## 3.5 Step-by-step implementation order

**Track A — theming pipeline (branch `feat/matugen-pipeline`)**

0. **Branch + issues.** `git switch -c feat/matugen-pipeline`; commit this plan; `gh issue create` for the two tracks + later-tiers epic. Verify: branch pushed, issues visible.
1. **Matugen packaging.** Add `matugen` to `modules/system/packages.nix`; create `modules/home/programs/matugen.nix` + `matugen/` (config.toml + all templates from the delta list, with output paths as in 3.2 except hyprland→`~/.cache/matugen/hypr-colors.lua`); import in `modules/home/default.nix`. Verify: `nix flake check` + `trb` clean. **rb (ask jftx)** → `~/.config/matugen/` populated, `matugen --version` works.
2. **Manual generation + template-syntax gate.** Run `matugen image ~/wallpapers/<any>.jpg` by hand. Verify: every output file exists and contains plausible hex values. **This is where matugen 4.1 vs his 2.x-era templates is validated** — if `{{colors.*.default.hex}}` or config.toml keys changed, fix templates here before anything consumes them. No repo change if templates are fine.
3. **Wallpaper trigger.** Hook `matugen image "$pick"` + `matugen-reload` into `wallpaper-random.sh` (before the `exec awww img`; drop `exec` or reorder) and `wallpaper-picker.sh`; create `matugen-reload` writeShellApplication (kitty SIGUSR1 → `.kitty-wrapped`, GTK gsettings toggle hack, `systemctl --user try-restart swayosd`, cava rebuild+SIGUSR1, `hyprctl reload`); add matugen to `runtimeInputs`. Verify: `trb`, **rb (ask jftx)**, then `systemctl --user start wallpaper.service` → wallpaper changes AND all output files' mtimes update.
4. **Non-QML consumers.** `kitty.nix` include line; new `theme.nix` (gtk enable, adw-gtk3-dark, gtk3/4 extraCss `@import` of `~/.cache/matugen/colors-gtk.css`, dconf prefer-dark, `qt.platformTheme.name = "qt6ct"`); align `env.lua` `QT_QPA_PLATFORMTHEME` to `qt6ct`; qt5ct/qt6ct/adw-gtk3/adwaita-icon-theme packages; system `programs.dconf.enable`; `hardware.bluetooth.enable`; fonts `jetbrains-mono` + `nerd-fonts.iosevka`; `decorations.lua` dofile-with-fallback; vesktop theme enabled in its settings; firefox profile chrome dir + pref. Verify: **rb (ask jftx)** → change wallpaper: kitty recolors live, Hyprland borders recolor after reload, nautilus/GTK tint shifts, vesktop theme selectable, swayosd css file exists.
5. **PR.** `gh pr create` for Track A; merge after jftx review. Theming is now fully operational with zero shell changes — waybar still runs.

**Track B — island shell core (branch `feat/quickshell-core`)**

6. **Vendor support layer.** Create `modules/home/desktop/quickshell/` with MatugenColors/Caching/Config/SysData/Scaler/WindowRegistry + `qs_manager.sh`/`caching.sh` (adapted paths), `quickshell.nix` with the **dev-time out-of-store symlink**, `services.swayosd.enable` + style path. Verify: `trb`, **rb (ask jftx)**, `quickshell -p ~/.config/quickshell/Shell.qml` with a stub Shell.qml renders an empty window without QML errors; `swayosd-client --output-volume raise` shows themed OSD.
7. **Island engine.** Adapt `Main.qml`: collapsed state = visible pill (clock, `MatugenColors` themed) centered top; expansion = existing morph logic; keep `IpcHandler main`. New minimal `island/` QML for pill content. Size audit for 5120×1440. Verify (manual quickshell run): pill shows live clock in wallpaper colors; changing wallpaper recolors it within ~1 s.
8. **App launcher.** Vendor `applauncher/`; wire `ALT+SPACE` in `binds.lua` → `qs_manager.sh toggle applauncher` (replacing rofi drun bind); launcher expands from island. Verify: ALT+SPACE opens, fuzzy-finds, launches, ESC closes, rofi bind gone.
9. **Volume popup + watchers.** Vendor `volume/` + audio watchers; `SUPER+V` per reference. Verify: volume keys → swayosd OSD; SUPER+V → popup with device controls, themed.
10. **Notifications.** Vendor `notifications/`; enable notification server in Main.qml; **same commit**: remove `swaync` from `autostart.lua`. Verify: after **rb (ask jftx)** + `pkill swaync`, `notify-send test` renders a quickshell popup; no daemon conflict in `journalctl --user`.
11. **Wallpaper picker QML.** Vendor adapted `WallpaperPicker.qml` (awww, no video, `~/wallpapers`, writes state file, thumbnails via qs_manager prep); `ALT+SHIFT+W` → `qs_manager.sh toggle wallpaper` (replacing rofi picker bind; script kept). Verify: grid of thumbnails opens, selection sets wallpaper + retheme cascade fires, no-repeat logic of the 10-min timer still works.
12. **Autostart flip + retirement.** `autostart.lua`: `quickshell -p ~/.config/quickshell/Shell.qml` replaces `waybar`; remove waybar launch bind (`ALT+R` launch.sh); keep waybar/swaync files + packages. Solidify quickshell source to the pure store path (remove out-of-store dev symlink). Update CLAUDE.md (unstable channel; island shell; theming pipeline; this plan's location). Verify: **rb + full reboot (ask jftx)** → clean session: island up, timer rethemes everything at 10-min mark, ALT binds intact, `nix flake check` clean. PR + merge.

**Track C — later sessions (planned, not now)**
- **Panels** (one PR each, vendor-as-needed): network+bluetooth panel (bluez CLI already enabled), calendar (+weather script — personalize location; schedule/diary optional), music popup + cava equalizer, monitors popup, settings popup, guide popup.
- **Session**: `Lock.qml` + PAM + hypridle (decide: autologin machine — lock adds real security only after boot), screenshot overlay (grim/slurp + add satty).
- **Extras**: clipboard manager (+cliphist package), quickactions (timer/draw/sysusage), focustime daemon.
- **Deferred/excluded**: spicetify-matugen (fights Nix-managed spicetify; revisit), stewart voice assistant (separate upstream project), movies widget, updater popup (distro-specific).

## 3.6 Risks and mitigations

| Risk | Mitigation |
|---|---|
| **Matugen 4.1 template/config format drift** vs his ~2.x-era templates | Gated at step 2 before any consumer exists; fix templates against matugen 4 docs; nothing downstream depends on exact template internals, only output paths. |
| **Quickshell 0.3.0 API drift** vs QML written for early-2026 quickshell | Manual-launch phases (steps 6–11) surface QML errors immediately; fix per-file; quickshell IPC/PanelWindow APIs are the stable core. |
| **Qt module availability** (nixpkgs quickshell may not see extra QML modules) | Core scope needs none beyond qtdeclarative (QtMultimedia stripped with video support; folderlistmodel ships in qtdeclarative). If a later tier needs QtMultimedia, wrap quickshell with `QML2_IMPORT_PATH` or override — solve when that tier starts. |
| **Ultrawide mis-sizing** (reference tuned for 1920×1080) | Island is custom-built for this display anyway; audit every hardcoded px + `s()` scale call when vendoring each widget; test at 5120×1440 each step. |
| **Notification daemon conflict** (swaync vs quickshell) | Atomic swap in step 10 (same commit removes swaync autostart); rollback = revert one commit. |
| **Runtime outputs vs declarative HM** | Outputs only in `/tmp`, `~/.cache`, writable config dirs; never into store-symlinked trees (esp. `~/.config/hypr`); all consumers have no-output fallbacks; timer regenerates 5 s after login so state self-heals per boot. |
| **10-min retheme side effects** (GTK toggle flash, swayosd restart audio pop — documented by ilyamiro) | Accept initially; tune later (drop swayosd restart from the timer path, keep it for manual picks; or lengthen timer). |
| **Shell crash on autologin session** (no bar → feels bricked) | `qs_manager.sh` zombie-watchdog respawns quickshell on any keybind; `ALT+RETURN` kitty bind never routes through the shell; NixOS generation rollback as last resort. |
| **Dev-time out-of-store symlink impurity** | Time-boxed to Track B dev; step 12 solidifies to store source; flake evaluation never depends on it (`xdg.configFile` source switch only). |
| **Firefox profile path unknown/changes** | Detect at step 4; userChrome is cosmetic — failure mode is "no firefox theming," nothing breaks. |
| **`rb` requires sudo/user action** | Protocol locked: Claude stops and requests activation; jftx runs `rb` and pastes output. `trb`/`nix flake check` cover most verification without activation. |
