# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NixOS flake-based system configuration for the single host `blackgarden` (x86_64-linux, AMD CPU, NVMe + ext4 root, vfat EFI System Partition at `/boot`, swap partition). Runs Hyprland on Wayland via UWSM, with autologin to user `jftx`. Home Manager is wired in as a NixOS module (not standalone).

Pinned inputs: `nixpkgs/nixos-26.05`, `home-manager/release-26.05`, and `spicetify-nix` (Gerg-L). `useGlobalPkgs = true`, so the system-level `nixpkgs.config.allowUnfree = true` also applies to Home Manager packages.

## Key Commands

```bash
# Rebuild & switch (alias: rb). Evaluates as user, activates via sudo.
nixos-rebuild switch --flake ~/nixos#blackgarden --sudo

# Validate evaluation without building — run this after edits before suggesting a rebuild.
nix flake check

# Update pinned inputs (nixpkgs/home-manager/spicetify), then rebuild.
nix flake update
```

There is no test suite; `nix flake check` (plus an optional `nixos-rebuild build --flake ~/nixos#blackgarden`) is the validation step.

Other shell aliases (defined in `modules/home/programs/bash.nix`): `nixcfg` → open the config repo in VS Code, `hyprcfg` → open the Hyprland Lua config at `~/nixos/modules/home/desktop/hypr` in VS Code.

## Layout & Entry Point

`flake.nix` builds `nixosConfigurations.blackgarden` from two import roots, passing `inputs` down via `specialArgs`/`extraSpecialArgs`:

- **System:** `./hosts/blackgarden/default.nix` → imports `../../hardware-configuration.nix` and `../../modules/system`. `modules/system/default.nix` aggregates the per-concern files: `boot.nix`, `audio.nix`, `graphics.nix`, `hyprland.nix`, `fonts.nix`, `network.nix`, `nix.nix`, `packages.nix`. Host-specific identity (hostname, the `jftx` user, `stateVersion`) lives in `hosts/blackgarden/default.nix`.
- **Home:** `./modules/home` (via `users.jftx = import ./modules/home`). `modules/home/default.nix` sets username/homeDirectory/stateVersion/session vars and imports `packages.nix`, `programs/{git,kitty,spicetify,bash}.nix`, `services/{ssh-agent,wallpaper}.nix`, and `desktop/hyprland.nix`.

Where to make a change:
- **System package** → `modules/system/packages.nix`. **User/CLI app** → `modules/home/packages.nix` (preferred for user-facing tools).
- A configured **program** (kitty, git, spicetify, bash) → its file under `modules/home/programs/`.
- A **system concern** (boot, audio, graphics, Hyprland session enablement, network, nix/gc, fonts) → the matching file in `modules/system/`.
- The **Hyprland config itself** (hand-written Lua) → `modules/home/desktop/hypr/` (`hyprland.lua` + `modules/*.lua`); its wiring is `modules/home/desktop/hyprland.nix`. This is distinct from enabling the compositor/session in `modules/system/hyprland.nix`.

`hardware-configuration.nix` (repo root) is generated and still actively imported — **do not edit**. `flake.lock` — **do not edit by hand**; use `nix flake update`. Custom Anthropic fonts in `fonts/anthropic/` are installed as an inline `stdenvNoCC.mkDerivation` in `modules/system/fonts.nix`.

> **Stale files:** `configuration.nix` and `home.nix` at the repo root are leftovers from the pre-modularization layout (commit `4978974`) and are **no longer imported by the flake** — the live config is entirely under `hosts/` and `modules/`. Do not edit the root `configuration.nix`/`home.nix` expecting it to take effect; they can be safely deleted.

## Architecture Notes

- **Home Manager as a NixOS module:** `useGlobalPkgs` + `useUserPackages` are on, `backupFileExtension = "backup"`. Because pkgs is shared with the system, unfree apps (vscode) need no separate allowUnfree in home.
- **Spicetify** comes from its own flake input. `modules/home/programs/spicetify.nix` imports `inputs.spicetify-nix.homeManagerModules.default` and reads packages from `inputs.spicetify-nix.legacyPackages.${system}` (enabled: marketplace app, adblockify + shuffle extensions, `text` theme).
- **Hyprland** is enabled system-wide (`programs.hyprland`, xwayland + UWSM) in `modules/system/hyprland.nix`. Autostart is handled in `modules/home/programs/bash.nix` `profileExtra`: on TTY1 it `exec uwsm start hyprland-uwsm.desktop`. The **compositor config is hand-written Lua** — Hyprland 0.55+ reads `~/.config/hypr/hyprland.lua` natively via its embedded interpreter and `hl.*` API (loops, locals, event handlers, captured rule handles), so it is *not* flattened into a Nix attrset. The Lua source lives in-repo at `modules/home/desktop/hypr/` (`hyprland.lua` + `modules/*.lua`); `modules/home/desktop/hyprland.nix` materializes it to `~/.config/hypr` via `xdg.configFile."hypr"` with `recursive = true` — a real writable dir of per-file store symlinks, keeping the `modules/` subtree so `require("modules.…")` resolves. The Home Manager `wayland.windowManager.hyprland` module is deliberately **not** used (it would generate a static `hyprland.conf` from Nix attrsets). Because `~/.config/hypr/*` are read-only store symlinks, edit the Lua in-repo then `rb` + `hyprctl reload` — editing under `~/.config/hypr` directly has no effect.
- **Boot/GC interplay:** `boot.loader.systemd-boot` with `configurationLimit = 10`; `nix.gc` runs daily deleting generations older than 10 days; `system.autoUpgrade` runs weekly. Changing the bootloader or generation count is done in `modules/system/boot.nix`.
