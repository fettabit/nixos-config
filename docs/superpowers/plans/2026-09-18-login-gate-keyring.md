# Login Gate + Keyring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace getty autologin on `blackgarden` with a greetd + tuigreet password login on VT1 and provide a PAM-unlocked Secret Service (gnome-keyring) so Proton's clients stop falling back to a plaintext JSON keyring.

**Architecture:** One new system module `modules/system/login.nix` enables `services.greetd` (tuigreet, fixed `--cmd 'uwsm start hyprland-uwsm.desktop'`) and `services.gnome.gnome-keyring`. The getty autologin line leaves `hyprland.nix` and the `profileExtra` autostart leaves `bash.nix`; greetd now starts the identical UWSM session entry after PAM auth. greetd's PAM service is a substack of `login`, and the gnome-keyring module hooks `pam_gnome_keyring` into `login`, so the keyring is created on first login and unlocked with the login password with no further PAM config.

**Tech Stack:** NixOS unstable flake (nixpkgs locked at `e554fab72f81`, 2026-09-17), greetd 0.10.3, tuigreet 0.11.1, gnome-keyring 50.0 (+ gcr_3 prompter from the module), UWSM 0.26.7, alejandra.

**Spec:** `docs/superpowers/specs/2026-09-18-login-gate-keyring-design.md` — read it first; every task cites the spec section it implements. Issue #29, branch `feat/login-gate-keyring`.

## Global Constraints

- **Never run `rb` / `nixos-rebuild switch`.** Validation is `nix flake check` and `trb` (`nixos-rebuild build --flake ~/nixos#blackgarden --sudo`). Activation is jftx's and **requires a reboot** (spec §3.5).
- **`git add` new files before `nix flake check`** — untracked files are invisible to flake evaluation.
- Work on branch `feat/login-gate-keyring`; never commit to `main`. Commit messages end with `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.
- The greeter command is exactly `uwsm start hyprland-uwsm.desktop` — byte-identical to today's `profileExtra` (spec §3.1, D2). No `--sessions`, no second compositor.
- Only `services.gnome.gnome-keyring.enable = true` for the keyring: **no** extra `security.pam.services.*.enableGnomeKeyring`, **no** seahorse (spec §1.3, D6).
- Do not touch `hardening.nix`, `network.nix`, `caelestia.nix` idle config, or the Proton package list (D4, D7, D8).
- LUKS is out of scope; jftx is researching it himself — do not add it anywhere.
- Format Nix with `alejandra` before committing.

## File Structure

| File | Change | Responsibility |
|------|--------|----------------|
| `modules/system/login.nix` | **create** | Login gate (greetd + tuigreet on VT1) and Secret Service (gnome-keyring). |
| `modules/system/default.nix` | modify (import) | Aggregates per-concern system modules. |
| `modules/system/hyprland.nix` | modify (−1 line) | Loses `services.getty.autologinUser`; keeps Hyprland/UWSM, dconf, PPD, i2c. |
| `modules/home/programs/bash.nix` | modify (−5 lines) | Loses the `profileExtra` autostart; aliases and `initExtra` unchanged. |
| `CLAUDE.md` | modify | Overview, layout list, "where to change", Hyprland bullet, new Login & keyring bullet, reboot note under `rb`. |
| `docs/superpowers/specs/2026-09-18-login-gate-keyring-design.md` | append §4b | Post-activation findings (Task 5, after jftx's runbook). |

There is no test suite. Each task's "test" is a `nix eval` assertion against `.#nixosConfigurations.blackgarden.config` (fails before, passes after) and, for the final task, `grep` assertions against the built system closure.

---

### Task 1: `modules/system/login.nix` — greetd + gnome-keyring, autologin removed

Implements spec §3.1, §3.2 (system half), §3.3. One commit: adding greetd while leaving `services.getty.autologinUser` set would autologin jftx on TTY2+ (the option applies to every getty instance), which is a bypass of the gate — so the removal lands in the same change.

**Files:**
- Create: `modules/system/login.nix`
- Modify: `modules/system/default.nix:6` (add import after `./hyprland.nix`)
- Modify: `modules/system/hyprland.nix:2` (delete the autologin line)

**Interfaces:**
- Consumes: `pkgs.tuigreet`, the `hyprland-uwsm.desktop` session entry that `programs.hyprland.withUWSM = true` already installs under `/run/current-system/sw/share/wayland-sessions/`.
- Produces: `config.services.greetd.enable = true`, `config.services.greetd.settings.default_session.command` (string containing `tuigreet` and `uwsm start hyprland-uwsm.desktop`), `config.services.gnome.gnome-keyring.enable = true`, `config.security.pam.services.login.enableGnomeKeyring = true`, `config.services.getty.autologinUser = null`. Tasks 2–4 rely on these names.

- [ ] **Step 1: Record the failing assertions (current state)**

Run from `~/nixos` on branch `feat/login-gate-keyring`:

```bash
C=.#nixosConfigurations.blackgarden.config
nix eval "$C.services.greetd.enable"
nix eval "$C.services.gnome.gnome-keyring.enable"
nix eval "$C.security.pam.services.login.enableGnomeKeyring"
nix eval "$C.services.getty.autologinUser"
```

Expected (all four are the "before" values): `false`, `false`, `false`, `"jftx"`.

- [ ] **Step 2: Create `modules/system/login.nix`**

```nix
{pkgs, ...}: {
  # Login gate: greetd owns VT1 (the module disables autovt@tty1) and runs
  # tuigreet; on a successful PAM auth it starts the same UWSM session entry
  # bash.nix used to exec on autologin. Restart=on-success (module default)
  # brings the greeter back when Hyprland exits. TTY2+ stay plain gettys —
  # password login, then `sudo nixos-rebuild switch --rollback` if needed.
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session.command = "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'";
  };

  # Secret Service (org.freedesktop.secrets) for Proton's clients and Electron
  # safeStorage. Without it proton-keyring-linux silently falls back to
  # plaintext JSON under ~/.config/Proton. The module wires pam_gnome_keyring
  # into the `login` PAM service; greetd's PAM service is a substack of
  # `login`, so the keyring is created on first login and unlocked with the
  # login password from then on — no extra PAM config.
  services.gnome.gnome-keyring.enable = true;
}
```

- [ ] **Step 3: Import it and remove the autologin line**

`modules/system/default.nix` — insert `./login.nix` directly after `./hyprland.nix` so the list reads:

```nix
{...}: {
  imports = [
    ./boot.nix
    ./audio.nix
    ./graphics.nix
    ./hyprland.nix
    ./login.nix
    ./fonts.nix
    ./network.nix
    ./nix.nix
    ./gaming.nix
    ./packages.nix
    ./hardening.nix
  ];
}
```

`modules/system/hyprland.nix` — delete line 2 (`services.getty.autologinUser = "jftx";`). The file then starts:

```nix
{...}: {
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };
```

- [ ] **Step 4: Format and stage**

```bash
alejandra modules/system/login.nix modules/system/default.nix modules/system/hyprland.nix
git add modules/system/login.nix modules/system/default.nix modules/system/hyprland.nix
```

`alejandra` may reflow the long `command =` string onto its own line; either form is fine.

- [ ] **Step 5: Run the assertions again (must flip)**

```bash
C=.#nixosConfigurations.blackgarden.config
nix eval "$C.services.greetd.enable"                              # true
nix eval "$C.services.gnome.gnome-keyring.enable"                 # true
nix eval "$C.security.pam.services.login.enableGnomeKeyring"      # true
nix eval "$C.services.getty.autologinUser"                        # null
nix eval --raw "$C.services.greetd.settings.default_session.command"; echo
#   /nix/store/…-tuigreet-0.11.1/bin/tuigreet --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'
nix eval "$C.services.greetd.settings.terminal.vt"                # 1
nix eval "$C.systemd.services.\"autovt@tty1\".enable"             # false
```

Every value must match the comment. If `autologinUser` is not `null`, something else still sets it — `grep -rn autologinUser modules/ hosts/` and remove it.

- [ ] **Step 6: `nix flake check`**

```bash
nix flake check
```

Expected: exits 0, no `error:` lines (the pre-existing `renamed-option`/`trace:` warnings, if any, are not from this change).

- [ ] **Step 7: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(login): greetd + tuigreet on VT1, gnome-keyring; drop getty autologin (#29)

modules/system/login.nix: services.greetd runs tuigreet with the same
`uwsm start hyprland-uwsm.desktop` entry bash.nix execs today, and
services.gnome.gnome-keyring provides org.freedesktop.secrets unlocked by
pam_gnome_keyring on `login` (greetd's PAM stack is a substack of it).
services.getty.autologinUser removed — it applied to every getty, so TTY2+
would otherwise stay a bypass of the gate.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `bash.nix` — remove the autologin autostart

Implements spec §3.2 (home half). Separate commit: it is a Home Manager change and the only way to confirm it is that the generated `~/.profile` no longer contains the exec.

**Files:**
- Modify: `modules/home/programs/bash.nix:26-30` (delete the `profileExtra` attribute)

**Interfaces:**
- Consumes: nothing from Task 1 (independent).
- Produces: `config.home-manager.users.jftx.programs.bash.profileExtra = ""`.

- [ ] **Step 1: Record the failing assertion**

```bash
nix eval --raw '.#nixosConfigurations.blackgarden.config.home-manager.users.jftx.programs.bash.profileExtra'
```

Expected (before): prints the three-line `if uwsm check may-start …` block.

- [ ] **Step 2: Delete the block**

Remove lines 26–30 of `modules/home/programs/bash.nix`:

```nix
    profileExtra = ''
      if uwsm check may-start && [ "$XDG_VTNR" = 1 ]; then
          exec uwsm start hyprland-uwsm.desktop
      fi
    '';
```

The attribute set then ends right after `initExtra`:

```nix
      unset _cs
    '';
  };
}
```

Nothing else in the file changes (aliases, `initExtra` with `SSH_AUTH_SOCK`/`TZDIR`/sequences replay stay).

- [ ] **Step 3: Format, stage, re-assert**

```bash
alejandra modules/home/programs/bash.nix
git add modules/home/programs/bash.nix
nix eval --raw '.#nixosConfigurations.blackgarden.config.home-manager.users.jftx.programs.bash.profileExtra'; echo "<end>"
```

Expected: prints only `<end>` (empty string).

- [ ] **Step 4: `nix flake check`**

```bash
nix flake check
```

Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat(login): drop bash profileExtra autostart — greetd starts the session (#29)

The TTY1 `exec uwsm start hyprland-uwsm.desktop` only made sense with
getty autologin; greetd now runs the identical command after PAM auth.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: CLAUDE.md

Implements spec §3.6. Doc-only; the "test" is that every stale mention of autologin is gone.

**Files:**
- Modify: `CLAUDE.md:7` (Overview), `:16-17` (rb comment), `:42` (system file list), `:48` (system concern list), `:59` (Hyprland bullet), new bullet after `:59`.

**Interfaces:**
- Consumes: the names from Task 1 (`login.nix`, greetd/tuigreet, gnome-keyring, PAM `login` substack).
- Produces: nothing code-facing.

- [ ] **Step 1: Failing assertion**

```bash
grep -nE 'autologin|profileExtra' CLAUDE.md
```

Expected (before): three hits (lines 7, 59 ×2).

- [ ] **Step 2: Overview (line 7)**

Replace the sentence

> `Runs Hyprland on Wayland via UWSM, with getty autologin to user `jftx`.`

with

> `Runs Hyprland on Wayland via UWSM, started by greetd/tuigreet on VT1 (password login; gnome-keyring is unlocked by PAM at login and provides the Secret Service).`

- [ ] **Step 3: Key Commands — reboot note (after line 17, inside the first code block)**

Directly under the line `# Activation is jftx's call — Claude validates, then asks him to run rb and paste output.` add:

```
# Changes to modules/system/login.nix (greetd, PAM, keyring) need a reboot
# after rb: greetd takes VT1 over from getty only at boot.
```

- [ ] **Step 4: Layout list (line 42)**

In the `default.nix aggregates per-concern files:` list, replace

> `` `boot.nix`, `audio.nix`, `graphics.nix`, `hyprland.nix`, `fonts.nix`, `network.nix`, `nix.nix`, `gaming.nix`, `packages.nix`. ``

with

> `` `boot.nix`, `audio.nix`, `graphics.nix`, `hyprland.nix`, `login.nix`, `fonts.nix`, `network.nix`, `nix.nix`, `gaming.nix`, `packages.nix`, `hardening.nix`. ``

(`hardening.nix` was already imported but missing from this list.)

- [ ] **Step 5: "Where to make a change" (line 48)**

Replace

> `- A **system concern** (boot, audio, graphics, Hyprland session enablement + power-profiles-daemon + i2c, network/bluetooth/DNS, nix/gc/autoUpgrade, fonts, gaming/Steam, kernel hardening sysctls) → the matching file in `modules/system/` (`hardening.nix` holds the sysctl block + `protectKernelImage`; `network.nix` holds systemd-resolved with strict DNS-over-TLS to Quad9 — the router's DNS is deliberately ignored).`

with

> `- A **system concern** (boot, audio, graphics, Hyprland session enablement + power-profiles-daemon + i2c, login gate + keyring, network/bluetooth/DNS, nix/gc/autoUpgrade, fonts, gaming/Steam, kernel hardening sysctls) → the matching file in `modules/system/` (`login.nix` holds greetd/tuigreet + gnome-keyring; `hardening.nix` holds the sysctl block + `protectKernelImage`; `network.nix` holds systemd-resolved with strict DNS-over-TLS to Quad9 — the router's DNS is deliberately ignored).`

- [ ] **Step 6: Hyprland bullet (line 59)**

Replace the opening of the bullet

> `- **Hyprland:** enabled system-wide with UWSM in `modules/system/hyprland.nix` (which also holds getty autologin, dconf, power-profiles-daemon and i2c). Autostart: `bash.nix` `profileExtra` execs `uwsm start hyprland-uwsm.desktop` on TTY1. The compositor config is **hand-written Lua**`

with

> `- **Hyprland:** enabled system-wide with UWSM in `modules/system/hyprland.nix` (which also holds dconf, power-profiles-daemon and i2c). Session start: greetd runs tuigreet on VT1 (`modules/system/login.nix`) and, after PAM auth, execs `uwsm start hyprland-uwsm.desktop` — the entry `programs.hyprland.withUWSM` installs. TTY2+ are ordinary password gettys (escape hatch: CTRL+ALT+F2 → `sudo nixos-rebuild switch --rollback` → reboot). The compositor config is **hand-written Lua**`

The rest of the bullet (Lua location, `recursive = true`, `allow_session_lock_restore`) is unchanged.

- [ ] **Step 7: New "Login & keyring" bullet (insert directly after the Hyprland bullet)**

```markdown
- **Login & keyring:** `modules/system/login.nix`. `services.greetd` + `tuigreet --time --remember` (last user cached in `/var/cache/tuigreet`, created by the module); `Restart=on-success` returns to the greeter when Hyprland exits. `services.gnome.gnome-keyring.enable` provides `org.freedesktop.secrets` (D-Bus-activated) and hooks `pam_gnome_keyring` into the `login` PAM service; greetd's PAM stack is a substack of `login`, so the keyring is created on first login and unlocked with the login password — **do not add `security.pam.services.*.enableGnomeKeyring` lines**. gnome-keyring 50 has no ssh component (HM `services.ssh-agent` is untouched). Consumers: Proton VPN CLI/GUI via `proton-keyring-linux` (without a Secret Service they fall back to plaintext JSON in `~/.config/Proton/keyring-proton-sso-*.json` and print a `--- Logging error ---` traceback per command — that is the symptom of a missing/locked keyring) and Electron `safeStorage` (Proton Pass/Mail). If the login password changes, the keyring password no longer matches: `rm ~/.local/share/keyrings/login.keyring`, log out/in, re-sign-in to Proton. Proton binaries: `protonvpn` (CLI), `protonvpn-app` (GUI), `pass-cli`, `proton-cli`, `proton-mail`, `proton-pass`; their `update` subcommands cannot work against the read-only store. Verify the keyring with `busctl --user list | grep secrets` and `secret-tool search --all service Proton`.
```

- [ ] **Step 8: Assert and commit**

```bash
grep -nE 'autologin|profileExtra' CLAUDE.md || echo "clean"
grep -c 'login.nix' CLAUDE.md
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: CLAUDE.md — greetd/tuigreet login, gnome-keyring, reboot note (#29)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

Expected: first grep prints `clean`; second prints `4` or more.

---

### Task 4: Full build, closure assertions, PR

Implements spec §3.5 "Before `rb`". This is the only step that catches what evaluation cannot (unit files, PAM files, D-Bus service files are materialised here).

**Files:** none modified. Read-only checks against the build output.

- [ ] **Step 1: Build without activating**

```bash
nixos-rebuild build --flake ~/nixos#blackgarden --sudo
```

Expected: exit 0, `./result` symlink present in `~/nixos`. (Takes a few minutes; greetd/tuigreet/gnome-keyring come from the binary cache.)

- [ ] **Step 2: Assert against the closure**

```bash
R=~/nixos/result
# greetd config: tuigreet with the exact uwsm command, on vt 1, as user greeter
cat $R/etc/greetd/config.toml
grep -q "tuigreet --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'" $R/etc/greetd/config.toml && echo "OK greetd cmd"
grep -q '^vt = 1' $R/etc/greetd/config.toml && echo "OK vt1"
# greetd owns tty1 (useTextGreeter) and autovt@tty1 is masked
grep -E 'TTYPath|TTYReset|Restart=' $R/etc/systemd/system/greetd.service
readlink -f $R/etc/systemd/system/autovt@tty1.service       # -> /dev/null
# no autologin left on any getty. -R (capital) is required: every unit file
# under etc/systemd/system is a symlink into the store and -r skips symlinks,
# which would make this check pass vacuously.
grep -Rl -- '--autologin' $R/etc/systemd/system/ || echo "OK no autologin"
# PAM: keyring on login; greetd delegates to login
grep pam_gnome_keyring $R/etc/pam.d/login
grep -E 'substack login|include login' $R/etc/pam.d/greetd | head -2
# Secret Service is D-Bus activatable
ls $R/sw/share/dbus-1/services/ | grep -E 'secrets|gnome.keyring'
# session entry still there
grep '^Exec' $R/sw/share/wayland-sessions/hyprland-uwsm.desktop
# the generated ~/.profile no longer execs uwsm (HM home files live in a
# home-manager-files derivation inside the system closure)
HF=$(nix-store -qR $R | grep -m1 -- '-home-manager-files$')
grep -n 'uwsm' "$HF/.profile" || echo "OK no uwsm in .profile"
```

Expected, line by line: `OK greetd cmd`, `OK vt1`; `TTYPath=/dev/tty1`, `TTYReset=yes`, `Restart=on-success`; `/dev/null`; `OK no autologin`; two `pam_gnome_keyring.so` lines (auth + session) in `login`; substack/include lines in `greetd`; `org.freedesktop.secrets.service` (and `org.gnome.keyring.service`); `Exec=…/uwsm start -e -D Hyprland hyprland.desktop`; `OK no uwsm in .profile`.

If any assertion fails, stop — do not open the PR — and fix the corresponding task.

- [ ] **Step 3: Open the PR**

```bash
git push -u origin feat/login-gate-keyring
gh pr create --title "Login gate (greetd/tuigreet) + gnome-keyring; drop getty autologin" --body "$(cat <<'EOF'
Closes #29. Spec: `docs/superpowers/specs/2026-09-18-login-gate-keyring-design.md`, plan: `docs/superpowers/plans/2026-09-18-login-gate-keyring.md`.

## What
- New `modules/system/login.nix`: `services.greetd` + tuigreet on VT1 (`--time --remember --cmd 'uwsm start hyprland-uwsm.desktop'`), `services.gnome.gnome-keyring.enable`.
- `services.getty.autologinUser` removed (it applied to every getty — TTY2+ would have stayed a bypass).
- `bash.nix` `profileExtra` autostart removed; greetd runs the identical UWSM entry after PAM auth.
- CLAUDE.md updated (login/keyring bullet, reboot note).

## Why
Physical-access gate (hardening finding #1, parked 2026-09-14) and a real `org.freedesktop.secrets` provider: without one, Proton VPN CLI/GUI store tokens + VPN key in plaintext JSON and print a logging traceback per command. greetd's PAM service is a substack of `login`, so the gnome-keyring module's `login` hook already covers it — no extra PAM lines.

## Validation
`nix flake check` ✓, `nixos-rebuild build` ✓, closure assertions ✓ (greetd config/unit, `autovt@tty1` masked, no `--autologin` anywhere, `pam_gnome_keyring` in `login`, `org.freedesktop.secrets.service` present).

## Activation (jftx)
`sudo -k && sudo true` (know your password) → `rb` → **reboot** → spec §3.5 checks → Proton migration §3.4. Escape hatch: CTRL+ALT+F2 → `sudo nixos-rebuild switch --rollback` → reboot.

Out of scope: LUKS (separate track), idle auto-lock (declined), Proton Pass override (waiting on nixpkgs), VPN tunnel test vs rp_filter/DoT.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed. Post it to jftx together with the activation checklist below.

---

### Task 5: Activation runbook (jftx at the keyboard) + post-activation findings

Implements spec §3.4, §3.5. **Claude does not run any of the commands in Steps 1–4**; jftx runs them and pastes output. Claude's job is to read the pasted output against the expectations and, at the end, append §4b to the spec.

- [ ] **Step 1 (jftx): pre-flight + activate**

```bash
sudo -k && sudo true        # prompts for the password — this is the same password greetd will ask for
rb                          # nixos-rebuild switch … && hyprctl reload && systemctl --user restart caelestia
```

Expected: activation succeeds; the `rb` tail may print a warning about greetd/getty units changing — expected. **Then reboot.**

- [ ] **Step 2 (jftx): first login**

Expected on VT1: tuigreet with a clock; username field (pre-filled from the second boot on); password → Hyprland + caelestia bar exactly as before. If the greeter never appears or login loops: CTRL+ALT+F2, log in as jftx (password), `sudo nixos-rebuild switch --rollback`, `reboot`, report what was on screen.

- [ ] **Step 3 (jftx): session + keyring checks — paste the output**

```bash
loginctl list-sessions
loginctl show-session "$(loginctl list-sessions --no-legend | awk '$3=="jftx"{print $1; exit}')" -p Type -p Service -p TTY
systemctl --user is-active caelestia
pgrep -a gnome-keyring-daemon
busctl --user list | grep -iE 'secrets|keyring'
ls -la ~/.local/share/keyrings/
ls -la /var/cache/tuigreet/
```

Expected: one session, `Type=wayland`, `Service=greetd`, `TTY=tty1`; `active`; a `gnome-keyring-daemon --daemonize --login` process; `org.freedesktop.secrets` owned (activatable or running); `login.keyring` present; `lastuser` (or similar) file owned by `greeter`.

- [ ] **Step 4 (jftx): Proton migration — paste the output**

```bash
protonvpn signout && protonvpn signin              # follow the prompts
protonvpn status                                   # must print NO "--- Logging error ---"
protonvpn-app &                                    # sign out, sign back in, close
rm -v ~/.config/Proton/keyring-proton-sso-*.json
secret-tool search --all service Proton 2>&1 | grep -E '^\[|attribute.username'
ls ~/.config/Proton/
```

Expected: `status` is clean; `secret-tool` lists entries with `username = proton-sso-accounts` and `proton-sso-account-<id>`; `~/.config/Proton/` holds only `VPN/`. Then open Proton Pass and Proton Mail — a one-time re-login is expected; confirm both open normally afterwards.

- [ ] **Step 5 (Claude): record findings**

Append to `docs/superpowers/specs/2026-09-18-login-gate-keyring-design.md`:

```markdown
## 4b. Post-activation findings (2026-09-18)

- Activated: <commit>, rebooted <time>. Greeter/login: <as expected | deviation>.
- Keyring: <daemon args>, `org.freedesktop.secrets` <owned by …>.
- Proton: CLI clean after signout/signin: <yes/no>; GUI re-login: <ok>; Pass/Mail re-login prompted: <yes/no>; JSON fallback files removed: <yes>.
- Deviations from §3.5 expectations and how they were resolved: <none | list>.
```

Fill every `<…>` from jftx's pasted output — no field may stay a placeholder. Commit on the branch and push:

```bash
git add docs/superpowers/specs/2026-09-18-login-gate-keyring-design.md
git commit -m "$(cat <<'EOF'
docs(spec): §4b post-activation findings for the login gate (#29)

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push
```

Then update memory (`proton-suite.md` → ACTIVATED, next = LUKS is jftx's own research; tunnel test track pending) and hand the PR to jftx to merge.
