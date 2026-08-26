# TZDIR Session Environment Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make glibc IANA-zone-name resolution work in the graphical session by exporting `TZDIR=/etc/zoneinfo` at the systemd user-manager level.

**Architecture:** One Home Manager option (`systemd.user.sessionVariables`) that renders `~/.config/environment.d/10-home-manager.conf`. environment.d is applied when the user manager starts, so `hyprland-uwsm.service` — and everything it spawns (kitty → bash → CLI tools) — inherits `TZDIR` from the session root. No Hyprland Lua change, no shell-init change.

**Tech Stack:** Home Manager (as NixOS module), systemd user manager environment.d.

**Spec:** No standalone spec. Diagnosis of record (2026-08-26 session):
- Symptom: `timedatectl` renders `Local time` as UTC with zone `(America, +0000)`; screenshot first seen in the claude.ai mobile chat ("Fixing NixOS time sync and enabling secure boot").
- Root cause: kitty (pid 4023) and its bash child had **no `TZDIR`** in `/proc/*/environ`, while `systemctl --user show-environment` had it. Without `TZDIR`, NixOS glibc cannot resolve `TZ=America/New_York` by name (glibc's builtin zoneinfo dir is empty on NixOS) and falls back to POSIX-parsing the string → abbreviation "America", offset +0000.
- Proof: `TZDIR=/etc/zoneinfo timedatectl` renders `(EDT, -0400)` correctly.
- NOT the cause: there is no stray `TZ` variable anywhere; `time.timeZone` (modules/system/network.nix:4) and `/etc/localtime` are correct; plain `date` was always right. The mobile chat's "stray TZ" hypothesis is superseded by this diagnosis.

## Global Constraints

- Claude never runs `rb`/`nixos-rebuild switch` — jftx activates and pastes output.
- Validation before any activation ask: `git add` new files, `nix flake check`, then `nixos-rebuild build --flake ~/nixos#blackgarden --sudo` (trb).
- Branch isolation: all work on `fix/session-tzdir`, branched from `origin/main` (2f3d555). PR to `main`. Never commit to `feat/cc-calendar-weather`.
- Conflict check result (2026-08-26): `origin/main...feat/cc-calendar-weather` touches only `docs/superpowers/{plans,specs}/*` and `flake.lock`. This branch touches `modules/home/default.nix` and this plan file only → no overlap, no conflict.

---

### Task 1: Branch, issue, and the one-line fix

**Files:**
- Create: `docs/superpowers/plans/2026-08-26-tzdir-session-env.md` (this file)
- Modify: `modules/home/default.nix:24` (after `home.sessionVariables.NIXOS_OZONE_WL`)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `~/.config/environment.d/10-home-manager.conf` containing `TZDIR=/etc/zoneinfo` (rendered by Home Manager at activation).

- [x] **Step 1: Create branch from origin/main**

```bash
git -C ~/nixos checkout -b fix/session-tzdir origin/main
```

- [x] **Step 2: Create the GitHub issue**

```bash
gh issue create --title "Session env missing TZDIR — timedatectl renders (America, +0000)" \
  --body "glibc zone-by-name resolution fails in the uwsm/Hyprland session because TZDIR is absent from the user-manager-spawned environment. /etc/set-environment exports it, but hyprland-uwsm.service children (kitty, bash) never see it. Fix: systemd.user.sessionVariables.TZDIR via HM environment.d. Plan: docs/superpowers/plans/2026-08-26-tzdir-session-env.md"
```

Record the issue number; use it in the commit message and PR.

- [x] **Step 3: Apply the fix**

In `modules/home/default.nix`, replace:

```nix
  home.sessionVariables.NIXOS_OZONE_WL = "1";
```

with:

```nix
  home.sessionVariables.NIXOS_OZONE_WL = "1";
  # environment.d, not shell init: uwsm session units and their children
  # (Hyprland -> kitty -> shells) never source /etc/set-environment, so glibc
  # needs TZDIR here to resolve IANA zone names (timedatectl et al.).
  systemd.user.sessionVariables.TZDIR = "/etc/zoneinfo";
```

- [x] **Step 4: Validate (eval + full build)**

```bash
git -C ~/nixos add -A
nix flake check ~/nixos
nixos-rebuild build --flake ~/nixos#blackgarden --sudo
```

Expected: both succeed. If `systemd.user.sessionVariables` is reported as an unknown option (it should not be — standard HM option), stop and re-diagnose; do not substitute `home.sessionVariables` (that only reaches login shells, not the user manager).

- [x] **Step 5: Commit and open PR**

```bash
git -C ~/nixos add docs/superpowers/plans/2026-08-26-tzdir-session-env.md modules/home/default.nix
git -C ~/nixos commit -m "fix: export TZDIR into systemd user session (#18)"
git -C ~/nixos push -u origin fix/session-tzdir
gh pr create --title "fix: export TZDIR into systemd user session" \
  --body "Fixes #18. See plan doc for diagnosis. Takes effect at next login/reboot (environment.d is read at user-manager start)."
```

### Task 2: Activation and verification (jftx-gated)

**Files:** none — runtime only.

**Interfaces:**
- Consumes: merged/checked-out branch state from Task 1.
- Produces: verified `(EDT, -0400)` rendering; closes the issue.

- [ ] **Step 1: jftx activates**

Ask jftx to run `rb` (safe for this change — it is not boot-risky) and paste output.

- [ ] **Step 2: Pre-reboot sanity check (Claude)**

```bash
grep TZDIR ~/.config/environment.d/10-home-manager.conf
```

Expected: `TZDIR=/etc/zoneinfo`.

- [ ] **Step 3: After next re-login or reboot (piggyback on the secure-boot reboot), verify**

```bash
timedatectl
tr '\0' '\n' < /proc/$(pgrep -x .kitty-wrapped | head -1)/environ | grep TZDIR
```

Expected: `Time zone: America/New_York (EDT, -0400)`, `Local time` in EDT, and `TZDIR=/etc/zoneinfo` present in kitty's environment. Note: verification must run from a terminal opened *after* the new session starts — a surviving pre-fix process still shows the old env.

- [ ] **Step 4: Merge PR, close issue.**
