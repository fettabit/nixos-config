# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NixOS flake-based system configuration for the single host `blackgarden` (x86_64-linux, AMD CPU + GPU, NVMe + ext4 root, vfat EFI System Partition at `/boot`, swap partition; dual-boots Windows via os-prober). Runs Hyprland on Wayland via UWSM, with getty autologin to user `jftx`. The desktop shell is a custom Quickshell **island** (top-center morphing pill — bar, launcher, volume OSD, notification daemon, and wallpaper picker in one), themed end-to-end from the current wallpaper by matugen. Home Manager is wired in as a NixOS module (not standalone).

Pinned inputs: `nixpkgs/nixos-unstable`, `home-manager` (master, follows nixpkgs), and `spicetify-nix` (Gerg-L, follows nixpkgs). `useGlobalPkgs = true`, so the system-level `nixpkgs.config.allowUnfree = true` also applies to Home Manager packages.

Plans live in-repo: `docs/plans/quickshell-matugen-migration.md` is the master plan for the island/theming migration (Track C items still open); per-feature design specs and implementation plans are under `docs/superpowers/specs/` and `docs/superpowers/plans/`.

## Key Commands

```bash
# Rebuild & switch (alias: rb): system + Hyprland Lua reload + island QML restart.
# Activation is jftx's call — Claude validates, then asks him to run rb and paste output.
nixos-rebuild switch --flake ~/nixos#blackgarden --sudo && hyprctl reload && systemctl --user restart quickshell

# Validate evaluation without building — run after edits before suggesting a rebuild.
# git add new files first: untracked files are invisible to flake eval (purity).
nix flake check

# Full build without activation (alias: trb). Catches what flake check cannot —
# writeShellApplication runs shellcheck at build time.
nixos-rebuild build --flake ~/nixos#blackgarden --sudo

# Update pinned inputs, then rebuild.
nix flake update
```

There is no test suite; `nix flake check` plus `trb` is the validation step.

Other shell aliases (`modules/home/programs/bash.nix`): `gs`/`gp` → git status / push to main, `nixcfg` → open this repo in VS Code, `hyprcfg` → open the Hyprland Lua config in VS Code.

## Layout & Entry Point

`flake.nix` builds `nixosConfigurations.blackgarden` from two import roots, passing `inputs` down via `specialArgs`/`extraSpecialArgs`:

- **System:** `./hosts/blackgarden/default.nix` (hostname, the `jftx` user + groups, `stateVersion`) → imports `../../hardware-configuration.nix` and `../../modules/system`, whose `default.nix` aggregates per-concern files: `boot.nix`, `audio.nix`, `graphics.nix`, `hyprland.nix`, `fonts.nix`, `network.nix`, `nix.nix`, `gaming.nix`, `packages.nix`.
- **Home:** `./modules/home` (via `users.jftx = import ./modules/home`). `modules/home/default.nix` sets username/homeDirectory/stateVersion/session vars and imports `packages.nix`, `programs/{git,kitty,spicetify,bash,matugen}.nix`, `services/{ssh-agent,wallpaper}.nix`, and `desktop/{hyprland,theme,quickshell}.nix`.

Where to make a change:
- **System package** → `modules/system/packages.nix`. **User/CLI app** → `modules/home/packages.nix` (preferred for user-facing tools).
- A configured **program** (kitty, git, spicetify, bash) → its file under `modules/home/programs/`.
- A **system concern** (boot, audio, graphics, Hyprland session enablement, network/bluetooth, nix/gc, fonts, gaming/Steam) → the matching file in `modules/system/`.
- The **Hyprland config itself** (hand-written Lua) → `modules/home/desktop/hypr/` (`hyprland.lua` + `modules/*.lua`).
- The **island shell QML** → `modules/home/desktop/quickshell/` (`shell.qml` + `island/*.qml` + `theme/`).
- **Matugen templates** (per-app color outputs) → `modules/home/programs/matugen/templates/`; GTK/Qt theming glue → `modules/home/desktop/theme.nix`.
- **Wallpaper machinery** → `modules/home/services/wallpaper.nix` + `services/scripts/*.sh`.

`hardware-configuration.nix` (repo root) is generated and still actively imported — **do not edit**. `flake.lock` — **do not edit by hand**; use `nix flake update`. Custom Anthropic fonts in `fonts/anthropic/` are installed as an inline `stdenvNoCC.mkDerivation` in `modules/system/fonts.nix`, which also pins the JetBrains Mono / Iosevka families the island QML hardcodes.

## Architecture Notes

- **Home Manager as a NixOS module:** `useGlobalPkgs` + `useUserPackages` are on, `backupFileExtension = "backup"`. Because pkgs is shared with the system, unfree apps (vscode) need no separate allowUnfree in home.
- **Boot/GC interplay:** GRUB EFI (`device = "nodev"`, `useOSProber = true` for the Windows dual-boot) with `configurationLimit = 5` and `linuxPackages_latest`; `nix.gc` runs daily deleting generations older than 10 days; `system.autoUpgrade` runs weekly (`--update-input nixpkgs --no-write-lock-file`). Bootloader or generation-count changes → `modules/system/boot.nix`.
- **Hyprland:** enabled system-wide with UWSM in `modules/system/hyprland.nix` (which also holds getty autologin and dconf). Autostart: `bash.nix` `profileExtra` execs `uwsm start hyprland-uwsm.desktop` on TTY1. The compositor config is **hand-written Lua** — Hyprland 0.55+ reads `~/.config/hypr/hyprland.lua` natively via its embedded interpreter and `hl.*` API. The Lua lives in-repo at `modules/home/desktop/hypr/`, materialized via `xdg.configFile."hypr"` with `recursive = true` (per-file store symlinks; the `modules/` subtree keeps `require("modules.…")` resolving). The Home Manager `wayland.windowManager.hyprland` module is deliberately **not** used. `~/.config/hypr/*` are read-only store symlinks: edit in-repo, then `rb` (the alias chains `hyprctl reload`).
- **Island shell (Quickshell):** quickshell 0.3.0 via the HM `programs.quickshell` module — config `island`, source is the **pure store path** of `modules/home/desktop/quickshell/`, materialized at `~/.config/quickshell/island`; `systemd.enable = true` runs it as the `quickshell.service` user unit (`WantedBy=graphical-session.target`, `Restart=on-failure`). **systemd owns the single instance — never launch a second by hand** (duplicate GlobalShortcut registrations can crash). QML edits: in-repo → `rb` (the alias restarts the unit; there is no hot reload). The island **is** the notification daemon (`org.freedesktop.Notifications`) — never install another one (swaync was removed for exactly this). Keybinds route through Hyprland's `global` dispatcher to `GlobalShortcut` objects (appid `quickshell`): ALT+SPACE launcher, SUPER+V volume panel, F10–F12 volume keys, ALT+SHIFT+W wallpaper grid; `qs -c island ipc call` is the scripting/testing fallback.
- **Theming pipeline (matugen):** one-way cascade from the wallpaper. `wallpaper.service` runs `wallpaper-random.sh` — the repo's **only** apply block (state write → awww → matugen → matugen-reload) — rendering `modules/home/programs/matugen/templates/` (kitty, hypr, GTK/Qt, discord, cava, and `/tmp/qs_colors.json`, which `theme/Theme.qml` watches event-driven; the island recolors instantly). Manual picks go through the single front door **`wallpaper-set <path>`** (queues `~/.local/state/wallpaper-next`, starts `wallpaper.service` — which also resets the 10-min rotation countdown). ALT+W = random-now; ALT+SHIFT+W = island grid; `wallpaper-picker` = rofi terminal fallback. **NEVER restart `wallpaper.timer`**: its `OnActiveSec=5s` (the post-login bootstrap that regenerates the tmpfs outputs) fires a random pick 5 s after any timer restart, clobbering manual picks. Route everything through `wallpaper.service`.
- **Spicetify** comes from its own flake input. `modules/home/programs/spicetify.nix` imports `inputs.spicetify-nix.homeManagerModules.default` and reads packages from its `legacyPackages` (marketplace app, adblockify + shuffle extensions, `text` theme).
