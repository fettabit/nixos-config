# Secure Boot via Lanzaboote Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable UEFI Secure Boot on blackgarden (Battlefield 6 requirement) by migrating the bootloader from GRUB+os-prober to lanzaboote-signed systemd-boot, while keeping Windows (separate disk, own ESP) bootable via a new `boot-windows` command.

**Architecture:** Lanzaboote hooks the NixOS bootloader-install phase: every generation's kernel/initrd is wrapped in a signed stub and systemd-boot itself is signed with local sbctl keys (`/var/lib/sbctl`), so rebuilds stay automatically signed forever. GRUB is removed outright (no Microsoft-signed shim exists for NixOS; hand-signing GRUB+every kernel is unmaintained fight-the-tooling). Windows entry loss from dropping os-prober is covered by `boot-windows` — a `writeShellApplication` that sets the firmware's BootNext to the Windows Boot Manager NVRAM entry and reboots immediately, one command total.

**Tech Stack:** lanzaboote v1.1.0 (current release, 2026-06-22), sbctl, efibootmgr, systemd-boot, `writeShellApplication` (shellcheck at build time).

**Spec:** GitHub issue created in Task 1 + decisions of record (2026-08-26 session, continuing the claude.ai mobile chat "Fixing NixOS time sync and enabling secure boot"):
- BF6 needs firmware Secure Boot ON; the NixOS work exists so NixOS survives that flip.
- Windows-side prerequisites already verified in the mobile chat: BitLocker fully decrypted (no key protectors), TPM 2.0 (AMD fTPM) ready, BIOS Mode UEFI.
- Firmware is **already in setup mode** (`bootctl`: `Secure Boot: disabled (setup)`) — the "clear keys in firmware" trip is already done; only the final "enable Secure Boot" firmware visit remains.
- Decision: keep BIOS 3.08 (no pre-flash); a future flash just means redoing `sbctl enroll-keys --microsoft`.
- Decision: Windows access = firmware boot menu + `boot-windows` helper (auto-reboot, no second command). No copying of Microsoft boot files onto the NixOS ESP.
- Windows disk: `nvme0n1` (own 100M ESP on p1); NixOS: `nvme1n1` (ESP at `/boot`).

## Global Constraints

- **NEVER run `sbctl enroll-keys` without `--microsoft`.** Without it the Microsoft-signed Windows bootloader and the GPU option ROM stop validating — recovery means another firmware trip. (jftx's explicit standing instruction from the mobile chat.)
- **NEVER commit, copy into the repo, or print the contents of `/var/lib/sbctl`.** Platform signing keys stay on disk, root-only.
- Claude never runs `rb`, `nixos-rebuild switch`, or `nixos-rebuild boot` — jftx activates and pastes output. For this plan the activation command is **`nixos-rebuild boot`** (NOT `switch`, NOT the `rb` alias): the change must only apply on the next deliberate reboot.
- Do NOT enable Secure Boot in firmware until `sbctl verify` passes AND `sbctl enroll-keys --microsoft` has completed.
- Validation before any activation ask: `git add` new files (flake purity), `nix flake check`, then `nixos-rebuild build --flake ~/nixos#blackgarden --sudo` (trb).
- Branch isolation: all work on `feat/secure-boot-lanzaboote`, branched from `origin/main` (2f3d555). PR to `main`.
- Known merge overlap (checked 2026-08-26): `feat/cc-calendar-weather` also modifies `flake.lock` (commit 4875472, routine `nix flake update`). This branch merges **first** (BF6 priority); the cc branch then rebases and resolves `flake.lock` mechanically by taking main's lock and re-running `nix flake update`. No other branch touches `flake.nix` or `modules/system/boot.nix`.
- `hardware-configuration.nix` and `flake.lock` are never edited by hand.

---

### Task 1: Branch, issue, plan doc

**Files:**
- Create: `docs/superpowers/plans/2026-08-26-secure-boot-lanzaboote.md` (this file)

**Interfaces:**
- Consumes: nothing.
- Produces: branch `feat/secure-boot-lanzaboote`; issue number `#20` used by all later commits/PR.

- [ ] **Step 1: Branch from origin/main**

```bash
git -C ~/nixos checkout -b feat/secure-boot-lanzaboote origin/main
```

- [ ] **Step 2: Create the GitHub issue**

```bash
gh issue create --title "Secure Boot via lanzaboote (BF6) — replace GRUB, add boot-windows helper" \
  --body "Migrate bootloader GRUB+os-prober -> lanzaboote-signed systemd-boot so firmware Secure Boot can be enabled (BF6 requires it). Windows keeps booting via firmware entry; new boot-windows command sets BootNext and reboots. Keys via sbctl (/var/lib/sbctl, never committed). Enrollment ALWAYS with --microsoft. Plan: docs/superpowers/plans/2026-08-26-secure-boot-lanzaboote.md"
```

- [ ] **Step 3: Commit the plan doc**

```bash
git -C ~/nixos add docs/superpowers/plans/2026-08-26-secure-boot-lanzaboote.md
git -C ~/nixos commit -m "docs: secure boot lanzaboote implementation plan (#20)"
```

### Task 2: Lanzaboote flake input

**Files:**
- Modify: `flake.nix:9-12` (append input after `spicetify-nix`)
- Modify: `flake.lock` (generated — via `nix flake lock`, never by hand)

**Interfaces:**
- Consumes: branch from Task 1.
- Produces: `inputs.lanzaboote` (with `nixosModules.lanzaboote`) reachable in every system module via `specialArgs` — Task 3 imports it as `inputs.lanzaboote.nixosModules.lanzaboote`.

- [ ] **Step 1: Add the input**

In `flake.nix`, after the `spicetify-nix` block (line 12), insert:

```nix
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

No `outputs` signature change needed — modules receive it through `specialArgs = {inherit inputs;}`.

- [ ] **Step 2: Lock and validate eval**

```bash
nix flake lock ~/nixos
nix flake check ~/nixos
```

Expected: `flake.lock` gains a `lanzaboote` node (plus its own inner inputs); check passes. Note: v1.1.0's flake pins extra dev inputs (crane/rust-overlay or similar) — additional lock nodes are normal.

- [ ] **Step 3: Commit**

```bash
git -C ~/nixos add flake.nix flake.lock
git -C ~/nixos commit -m "feat: add lanzaboote flake input (#20)"
```

### Task 3: boot.nix — GRUB out, lanzaboote in, boot-windows helper

**Files:**
- Modify: `modules/system/boot.nix` (full rewrite, currently 13 lines)

**Interfaces:**
- Consumes: `inputs.lanzaboote.nixosModules.lanzaboote` (Task 2).
- Produces: system with `boot.lanzaboote` enabled, `sbctl` + `efibootmgr`-backed `boot-windows` on PATH. Runbook (Task 5) relies on commands `sbctl`, `boot-windows` existing after activation.

- [ ] **Step 1: Rewrite `modules/system/boot.nix` to exactly:**

```nix
{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [inputs.lanzaboote.nixosModules.lanzaboote];

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.efi.canTouchEfiVariables = true;
  # lanzaboote signs and installs its own systemd-boot + kernel stubs (lzbt)
  # at activation time; the module requires stock sd-boot forced off. GRUB is
  # gone entirely: no Microsoft-signed shim exists for NixOS, so GRUB cannot
  # sit in a Secure Boot chain without hand-signing every generation.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 5;
  };

  environment.systemPackages = [
    pkgs.sbctl
    # One command to land in Windows: firmware BootNext -> Windows Boot
    # Manager (its own ESP on nvme0n1 — sd-boot cannot list it), then reboot.
    (pkgs.writeShellApplication {
      name = "boot-windows";
      runtimeInputs = [pkgs.efibootmgr];
      text = ''
        if [ "$(id -u)" -ne 0 ]; then
          exec sudo "$0" "$@"
        fi
        entry=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} *Windows Boot Manager.*/\1/p' | head -n1)
        if [ -z "$entry" ]; then
          echo "boot-windows: no 'Windows Boot Manager' entry in firmware NVRAM" >&2
          exit 1
        fi
        efibootmgr --bootnext "$entry" >/dev/null
        reboot
      '';
    })
  ];
}
```

Notes for the implementer:
- `configurationLimit = 5` preserves the old GRUB behavior. If `nix flake check` reports `boot.lanzaboote.configurationLimit` as an unknown option under v1.1.0, delete that one line (generation pruning then falls to `nix.gc`, which already runs daily) — change nothing else.
- The `sudo` re-exec runs the *wrapper* script, so `runtimeInputs`' PATH entry (efibootmgr) survives into the root invocation.
- `writeShellApplication` adds `set -euo pipefail` and runs shellcheck at build time — trb (Task 4) is what catches script errors, not flake check.

- [ ] **Step 2: Validate eval**

```bash
git -C ~/nixos add -A
nix flake check ~/nixos
```

Expected: pass (see configurationLimit contingency above).

- [ ] **Step 3: Commit**

```bash
git -C ~/nixos add modules/system/boot.nix
git -C ~/nixos commit -m "feat: replace GRUB with lanzaboote secure boot + boot-windows helper (#20)"
```

### Task 4: Full build validation + PR

**Files:** none new.

**Interfaces:**
- Consumes: Tasks 2–3 committed.
- Produces: PR containing the runbook; a locally proven buildable system closure.

- [ ] **Step 1: Full build (no activation)**

```bash
nixos-rebuild build --flake ~/nixos#blackgarden --sudo
```

Expected: builds to completion (first run compiles/fetches the lanzaboote toolchain — takes longer than usual). Shellcheck failures in `boot-windows` surface here; fix and re-commit if so.

- [ ] **Step 2: Push and open PR**

```bash
git -C ~/nixos push -u origin feat/secure-boot-lanzaboote
gh pr create --title "Secure Boot via lanzaboote + boot-windows helper" \
  --body "Closes #20. GRUB+os-prober -> lanzaboote-signed systemd-boot; sbctl + boot-windows added. Activation is gated on jftx and follows the runbook in docs/superpowers/plans/2026-08-26-secure-boot-lanzaboote.md Task 5 (nixos-rebuild boot, NOT switch). Merge AFTER the runbook proves the machine boots signed."
```

PR merges only after Task 5 verification — the branch checkout is what gets activated and proven first.

### Task 5: Activation runbook (jftx-gated, paired)

**Files:** none — runtime only. Claude prepares/verifies; jftx runs every state-changing command (suggest the `! <command>` prefix so output lands in the session).

**Interfaces:**
- Consumes: Task 4's proven build on the checked-out branch.
- Produces: machine booting lanzaboote-signed systemd-boot with Secure Boot ON; evidence pasted into the session; unblocks Task 6.

- [ ] **Step 1 (jftx): Create signing keys — BEFORE activation**

```bash
sudo nix run 'nixpkgs#sbctl' -- create-keys
```

Expected: keys created under `/var/lib/sbctl`. Lanzaboote signs at *install* time, so this must exist before Step 2. Claude may verify existence only via `sudo ls /var/lib/sbctl` (directory names only — never file contents).

- [ ] **Step 2 (jftx): Stage the new bootloader for next boot only**

```bash
nixos-rebuild boot --flake ~/nixos#blackgarden --sudo
```

NOT `switch`, NOT `rb`. The running generation stays untouched; the ESP gets signed systemd-boot + signed generation stubs. Safety net at this point: Secure Boot is still off, old GRUB EFI + NVRAM entry still exist, and every prior generation remains bootable through them.

- [ ] **Step 3 (jftx): Reboot; (both): verify signed chain**

After reboot into the systemd-boot menu → newest generation:

```bash
bootctl status
sudo sbctl verify
```

Expected: `Current Boot Loader: systemd-boot` (signed), Secure Boot still `disabled (setup)`; `sbctl verify` shows every ESP file signed **except** `*fwupd*.efi` (expected, per mobile-chat plan). Also confirm the TZDIR fix if that PR is in this boot (see its plan, Task 2 Step 3).
If the machine fails to boot lanzaboote: pick a previous generation from the boot menu (or GRUB via firmware boot menu) — nothing is enrolled yet, nothing is bricked.

- [ ] **Step 4 (jftx): Enroll keys — the one non-negotiable flag**

```bash
sudo sbctl enroll-keys --microsoft
```

`--microsoft` keeps Microsoft's CA in db so Windows' bootloader and the GPU option ROM keep validating. Expected: enrolls PK/KEK/db from the current setup mode. If it errors about immutable variables, the firmware left setup mode — stop and re-clear keys in firmware first.

- [ ] **Step 5 (jftx): Enable Secure Boot in firmware**

Reboot → firmware setup → Secure Boot: Enabled → save/exit. Back in NixOS:

```bash
bootctl status
```

Expected: `Secure Boot: enabled (user)`.

- [ ] **Step 6 (jftx): Windows round trip — proves BOTH of today's tasks**

Run `boot-windows` (first live use — it should prompt for sudo, then reboot straight into Windows with no further commands). In Windows:
- `msinfo32` → Secure Boot State: **On** (BF6 requirement met).
- Clock shows correct local time immediately (RealTimeIsUniversal fix from the mobile chat, surviving a NixOS round trip).
- Launch BF6.

If `boot-windows` reports no NVRAM entry: run `sudo efibootmgr`, find the actual Windows label, report back — the sed pattern in Task 3 gets adjusted to the real label in a follow-up commit.

- [ ] **Step 7: Merge the PR** (work is proven; merge before cleanup so main matches the running system).

### Task 6: Post-proof cleanup (jftx-gated destructive steps)

**Files:** none in repo — ESP + NVRAM hygiene.

**Interfaces:**
- Consumes: Task 5 fully verified (Secure Boot on, Windows + BF6 confirmed).
- Produces: ESP free of GRUB-era and stale systemd-boot-era artifacts; issue closed.

- [ ] **Step 1 (Claude): Inventory, read-only**

```bash
ls -R /boot/EFI
sudo efibootmgr
ls /boot/grub 2>/dev/null
```

Known-stale candidates from the 2026-08-26 inventory: `/boot/EFI/NixOS-boot/grubx64.efi` (GRUB), `/boot/grub/` (if present), pre-migration leftovers under `/boot/EFI/nixos/*6.18.3[67]*` **only if** lzbt did not adopt/prune them, and any `NixOS-boot`/GRUB NVRAM entry. `EFI/systemd/` and `EFI/BOOT/` are now lanzaboote-managed — do NOT touch.

- [ ] **Step 2 (jftx): Remove confirmed-stale files** — exact `rm`/`efibootmgr -b XXXX -B` commands proposed by Claude from the Step 1 inventory, one by one, each justified against the inventory. Nothing is deleted that the current boot chain references.

- [ ] **Step 3: Close the issue with a summary comment** (state achieved, key locations, the enroll-keys/--microsoft rule for future BIOS flashes).

## Self-Review Notes

- Spec coverage: BF6/Secure Boot (Tasks 2–5), Windows bootability decision (Task 3 helper + Task 5 Step 6), keys hygiene (Global Constraints + Task 5 Step 1), setup-mode-already-active (Task 5 skips the clear-keys firmware trip), BIOS-3.08 decision (recorded in Spec; no task), ESP leftovers (Task 6), cc-branch flake.lock overlap (Global Constraints + merge order).
- Type/name consistency: branch name, issue placeholder `#20`, `pkiBundle = "/var/lib/sbctl"`, and command names (`sbctl`, `boot-windows`) are identical across tasks.
- No placeholders beyond `#20`, which is resolved by Task 1 Step 2 at execution time.
