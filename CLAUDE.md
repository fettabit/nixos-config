# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a NixOS flake-based system configuration for host `blackgarden` (x86_64-linux), running Hyprland on Wayland via UWSM. It uses Home Manager as a NixOS module (not standalone).

Pinned channel: `nixpkgs/nixos-26.05` and `home-manager/release-26.05`.

## Key Commands

Rebuild and switch the system (requires sudo):

```bash
nixos-rebuild switch --flake ~/nixos#blackgarden --sudo
# or use the alias:
rb
```

Check flake for evaluation errors without building:

```bash
nix flake check
```

Update flake inputs (e.g., nixpkgs):

```bash
nix flake update
```

## File Structure

| File                         | Purpose                                                                                   |
| ---------------------------- | ----------------------------------------------------------------------------------------- |
| `flake.nix`                  | Entry point — declares inputs and the single NixOS config `blackgarden`                   |
| `configuration.nix`          | System-level config: boot, networking, audio (pipewire), Hyprland, system packages, fonts |
| `home.nix`                   | User-level config via Home Manager: user packages, kitty, spicetify, bash aliases/profile |
| `hardware-configuration.nix` | Auto-generated hardware config — **do not edit**                                          |
| `flake.lock`                 | Pinned input revisions — **do not edit manually**                                         |
| `fonts/anthropic/`           | Custom Anthropic font files (`.ttf`/`.otf`) installed as a system font derivation         |

## Architecture Notes

- **Home Manager** is wired in as a NixOS module in `flake.nix`, not as a standalone flake output. `inputs` is passed down via `specialArgs` / `extraSpecialArgs` so both `configuration.nix` and `home.nix` can reference flake inputs directly.
- **Spicetify** is pulled via its own flake input (`spicetify-nix`) and consumed in `home.nix` using `inputs.spicetify-nix.homeManagerModules.default` and `inputs.spicetify-nix.legacyPackages`.
- **Hyprland** is enabled system-wide (`programs.hyprland`) with UWSM; the bash profile in `home.nix` handles auto-starting it on TTY1.
- System packages live in `configuration.nix`; user packages live in `home.nix`. When adding a package, prefer `home.nix` for user-facing tools unless root/system access is needed.
