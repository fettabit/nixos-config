# Systemd Flip + Solidify Implementation Plan (Track B step 12, FINAL)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline execution chosen by jftx) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the island a systemd user service on a pure store path, remove waybar/swaync entirely, and rewrite CLAUDE.md to match reality — closing Track B.

**Architecture:** Flip `programs.quickshell.systemd.enable` + solidify `configs.island` to a store path (the HM module generates `quickshell.service`, `Restart=on-failure`, `WantedBy=graphical-session.target` — verified against module source, no overrides). Delete every waybar/swaync artifact. CLAUDE.md content is fully drafted in Task 3 from facts verified against the repo on 2026-07-18.

**Tech Stack:** Nix flake (nixos-unstable), Home Manager quickshell module, Hyprland Lua config, systemd user units.

**Spec:** `docs/superpowers/specs/2026-07-18-systemd-flip-design.md`

## Global Constraints

- No test suite: validation = `nix flake check` + `trb` (`nixos-rebuild build --flake ~/nixos#blackgarden --sudo`).
- `git add` new/deleted files **before** `nix flake check` — untracked files are invisible to flake eval (purity).
- **Every activation (`rb`) and the reboot are jftx's** — stop, request, wait for pasted output. Claude never runs `rb`.
- Nix files: alejandra style (2-space). Lua: stylua (tabs).
- Commit messages: repo style (`feature:` / `docs:` prefixes), trailer `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Never restart `wallpaper.timer` during verification — `OnActiveSec=5s` fires a random pick 5 s later.

---

### Task 1: Systemd flip + store-path solidify + rb alias

**Files:**
- Modify: `modules/home/desktop/quickshell.nix` (full replacement)
- Modify: `modules/home/programs/bash.nix:8`

**Interfaces:**
- Produces: `quickshell.service` user unit (`ExecStart=quickshell --config island`, `Restart=on-failure`, `After`/`WantedBy=graphical-session.target`); `~/.config/quickshell/island` becomes a read-only store symlink; `rb` alias restarts the unit. Task 4's checklist depends on all three.

- [ ] **Step 1: Replace `modules/home/desktop/quickshell.nix`** with:

```nix
{...}: {
  # The island shell. QML source of truth is ./quickshell in this repo,
  # copied to the store at build time and materialized read-only at
  # ~/.config/quickshell/island — same edit->rb workflow as the hypr Lua
  # (no hot reload; the rb alias restarts quickshell.service).
  programs.quickshell = {
    enable = true;
    configs.island = ./quickshell;
    activeConfig = "island";
    # quickshell.service: WantedBy graphical-session.target (UWSM-managed),
    # Restart=on-failure (also revives inert `global` binds). systemd owns
    # the single instance — never launch a second by hand: duplicate
    # GlobalShortcut appid:name registrations can crash the shell.
    systemd.enable = true;
  };
}
```

(The `config` module arg drops out — it existed only for `mkOutOfStoreSymlink`.)

- [ ] **Step 2: Edit `modules/home/programs/bash.nix`** — old:

```nix
      rb = "nixos-rebuild switch --flake ~/nixos#blackgarden --sudo && hyprctl reload";
```

new:

```nix
      rb = "nixos-rebuild switch --flake ~/nixos#blackgarden --sudo && hyprctl reload && systemctl --user restart quickshell";
```

- [ ] **Step 3: Validate**

Run: `git add -A && nix flake check`
Expected: passes (eval warnings acceptable, no errors).

- [ ] **Step 4: Build**

Run: `nixos-rebuild build --flake ~/nixos#blackgarden --sudo`
Expected: completes; `./result` symlink appears. (Sandbox note: if the
harness sandbox blocks the daemon socket, rerun with escalated
permissions — build only, never switch.)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feature: quickshell systemd service + store-path solidify

The island is now quickshell.service (graphical-session.target,
Restart=on-failure) on a pure store path — dev hot-reload retired,
rb alias restarts the unit instead.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 2: Waybar + swaync full removal

**Files:**
- Modify: `modules/home/desktop/hypr/modules/autostart.lua` (full replacement)
- Modify: `modules/home/desktop/hypr/modules/binds.lua:28` (delete line)
- Modify: `modules/home/default.nix:16` (delete import)
- Modify: `modules/system/packages.nix:21,33` (delete two entries)
- Delete: `modules/home/desktop/waybar.nix`, `modules/home/desktop/waybar/` (config.jsonc, style.css, scripts/launch.sh)

**Interfaces:**
- Consumes: nothing from Task 1 (independent deletions; ordered second only for commit narrative).
- Produces: a session with no waybar and no swaync D-Bus activation file — Task 4's checklist items 2–3 depend on this.

- [ ] **Step 1: Replace `autostart.lua`** with:

```lua
-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
	hl.exec_cmd("awww-daemon")
end)
```

(waybar line gone; `awww-daemon` stays — wallpaper daemon, load-bearing.)

- [ ] **Step 2: Delete the ALT+R bind** — remove this line from `binds.lua`:

```lua
hl.bind(mainMod .. " + r", hl.dsp.exec_cmd("/home/jftx/nixos/modules/home/desktop/waybar/scripts/launch.sh"))
```

- [ ] **Step 3: Delete the waybar module wiring**

Remove from `modules/home/default.nix` imports:

```nix
    ./desktop/waybar.nix
```

Then: `git rm -r modules/home/desktop/waybar modules/home/desktop/waybar.nix`

- [ ] **Step 4: Delete the packages** — remove from `modules/system/packages.nix`:

```nix
    waybar
```

and

```nix
    swaynotificationcenter
```

- [ ] **Step 5: Validate + build**

Run: `git add -A && nix flake check && nixos-rebuild build --flake ~/nixos#blackgarden --sudo`
Expected: both pass — nothing else references waybar/swaync (verified in
exploration; a failure here means a missed reference — grep, fix, rerun).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feature: waybar + swaync retired

The island replaced both. Dropping swaynotificationcenter removes its
D-Bus activation file — nothing can race the island for
org.freedesktop.Notifications again; the post-reboot pkill ritual dies
here. ALT+R freed (unbound).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 3: CLAUDE.md rewrite (full accuracy audit)

**Files:**
- Modify: `CLAUDE.md` (full replacement; every claim below was verified against the repo 2026-07-18)

**Interfaces:**
- Consumes: the end state of Tasks 1–2 (describes rb alias with quickshell restart; no waybar/swaync).
- Produces: nothing downstream; documentation only.

Fact deltas driving the rewrite: channel is `nixos-unstable` (was: 26.05); home-manager tracks master (was: release-26.05); GRUB EFI + os-prober limit 5 + `linuxPackages_latest` (was: systemd-boot limit 10); root `configuration.nix`/`home.nix` already deleted (stale-files note must go); `modules/system` gained `gaming.nix`; home imports gained `programs/matugen.nix`, `desktop/{theme,quickshell}.nix`; aliases gained `gs`/`gp`/`trb`; autologin is `services.getty.autologinUser`; island + theming sections are new.

- [ ] **Step 1: Replace `CLAUDE.md`** with:

````markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: CLAUDE.md rewritten for the island era

Full accuracy audit: nixos-unstable (was 26.05), GRUB/os-prober (was
systemd-boot), gaming.nix, island shell + matugen pipeline sections,
plan locations, stale-files note dropped (files long deleted).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

### Task 4: Activation, live verification, done marker, PR

**Files:**
- Modify: `docs/plans/quickshell-matugen-migration.md` (step 12 line — done marker)

**Interfaces:**
- Consumes: Tasks 1–3 committed; `quickshell.service`, swaync-free session, new rb alias.
- Produces: verified Track B end state; PR closing issue #6.

- [ ] **Step 1: CHECKPOINT — request activation (jftx)**

No manual island instance is running (confirmed 2026-07-18), so the
sequence is: `rb` → paste output → **full reboot**. (Guard: if a manual
`qs` instance is somehow running at rb time, quit it first.)

- [ ] **Step 2: Post-reboot checklist** (batch probes tight — jftx's clicks land in focus-grabbed expansions)

```bash
systemctl --user status quickshell --no-pager | head -8   # active (running); loaded from graphical-session.target
pgrep -a swaync; echo "swaync exit: $?"                    # no output, exit 1
command -v waybar; echo "waybar exit: $?"                  # no output, exit 1
notify-send "step12" "island toast check"                  # island toast appears
systemctl --user list-timers wallpaper.timer --no-pager    # NEXT ≈ 10 min after last activation
journalctl --user -u quickshell --no-pager | tail -20      # no errors
```

jftx keyboard round (one batch): ALT+SPACE launcher · SUPER+V volume ·
F10–F12 flash · ALT+SHIFT+W grid + pick (cascade recolors island, NEXT
resets ≈ 10 min) · ALT+R does nothing.

- [ ] **Step 3: Done marker** — append to the master plan's step 12 line (before `PR + merge.` stays intact after it):

```
**✅ done 2026-07-18** (spec + plan in docs/superpowers/; waybar/swaync fully removed — files AND packages, superseding this line's earlier "stay in repo" wording; rb alias now chains systemctl --user restart quickshell)
```

- [ ] **Step 4: Commit + push**

```bash
git add docs/plans/quickshell-matugen-migration.md
git commit -m "docs: step 12 done marker — Track B complete

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

- [ ] **Step 5: PR** — finishing-a-development-branch flow: code review pass over the branch diff, then:

```bash
gh pr create --title "Track B: quickshell island shell core (steps 6-12)" --body "$(cat <<'EOF'
Closes #6.

The island is the shell now: launcher, volume OSD + panel, notification
daemon, wallpaper picker, hover peek — one Quickshell config, systemd-
managed, matugen-themed end to end. Waybar and swaync are gone.

Steps 6-12 each carry a design spec + implementation plan under
docs/superpowers/. Verified live on blackgarden through a clean reboot
(step 12 checklist in docs/superpowers/plans/2026-07-18-systemd-flip.md).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Merge is jftx's call (squash, matching Track A's PR #8).
