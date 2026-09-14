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
  **Theming cascade** (one-way): wallpaper → `caelestia wallpaper -f <path>` / `-r` (ALT+W, `>wallpaper`, `>random`) → `~/.local/state/caelestia/scheme.json` (smart scheme: light/dark + variant follow the wallpaper) → caelestia-cli templates → `~/.config/gtk-{3,4}.0/gtk.css` + dconf keys, `~/.config/qtengine/*`, `~/.config/hypr/scheme/current.lua`, `~/.config/vesktop/themes/caelestia.theme.css`, `~/.config/cava/config`, OSC sequences into live terminals + `~/.local/state/caelestia/sequences.txt` (replayed by bash) → `theme.postHook` = `caelestia-theme-hook` (`hyprctl reload`). Consequences: HM must never own `gtk.css`, the dconf `icon-theme` key, or a kitty colour include; every consumer must tolerate a missing scheme (first login). **Fresh state dir:** run `caelestia scheme set -n dynamic` once, or wallpapers won't drive colours (the first-run scheme is static catppuccin). caelestia 2.3.0 toasts "Failed to save config … Read-only file system" once per shell start — a known upstream bug fixed in 2.4.0 (arrives with the next `nix flake update` once `nixos-unstable` carries it); harmless, don't work around it. No wallpaper rotation timer exists — picks are manual. Spicetify and Brave are deliberately not themed by caelestia (spicetify-nix bakes its theme; Brave needs `/etc` writes).
- **Spicetify** comes from its own flake input. `modules/home/programs/spicetify.nix` imports `inputs.spicetify-nix.homeManagerModules.default` and reads packages from its `legacyPackages` (marketplace app, adblockify + shuffle extensions, `text` theme).
