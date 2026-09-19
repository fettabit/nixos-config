# Login Gate + Keyring — Design

**Date:** 2026-09-18 · **Status:** approved by jftx (design walkthrough in chat) · **Issue:** #29 · **Branch:** `feat/login-gate-keyring` · **Follows:** the 2026-09-14 hardening review (finding #1, parked then)

Replace getty autologin on `blackgarden` with a real login prompt (greetd +
tuigreet on VT1) and give the system a Secret Service (gnome-keyring, unlocked
by PAM with the login password). One PR. The trigger was the Proton suite
install of 2026-09-18: with no `org.freedesktop.secrets` provider, Proton's
Linux clients fall back to a plaintext JSON keyring and print a traceback on
every CLI command.

This document carries the diagnosis that motivated it, every decision with its
alternatives, the design, the activation runbook and the rollback path, so it
can be executed without the chat history.

---

## 1. Context

### 1.1 What exists today (`main` @ `60c5743`)

- **Login:** `modules/system/hyprland.nix` sets `services.getty.autologinUser = "jftx"`. `modules/home/programs/bash.nix` `profileExtra` runs `exec uwsm start hyprland-uwsm.desktop` when `uwsm check may-start` passes on `XDG_VTNR=1`. Power on → jftx's Hyprland session, no password.
- **User:** `jftx` has a password (sudo requires it). `mutableUsers` default. No LUKS: ext4 root, plain swap partition. Secure Boot is on via lanzaboote with Microsoft vendor keys enrolled, so Microsoft-signed live media still boots.
- **Lock:** caelestia's lock screen, manual only (ALT+L, `>lock`, session menu → `loginctl lock-session`). Idle = `dpms off` at 600 s, no auto-lock (decided 2026-09-14). `misc.allow_session_lock_restore = true` so a restarted shell re-attaches to a locked session.
- **Keyring:** none. `grep -riE 'keyring|kwallet|secret.?service|libsecret' modules/` is empty. `busctl --user list --activatable` shows no `org.freedesktop.secrets`; no D-Bus service file for one is installed anywhere on `XDG_DATA_DIRS`.
- **SSH agent:** Home Manager `services.ssh-agent` (`modules/home/services/ssh-agent.nix`).
- **Proton (commits `ea09ce1`, `60c5743`, all in `modules/system/packages.nix`):** `proton-cli` 2.2.3 (unofficial), `proton-vpn` 4.16.5 (GUI, binary `protonvpn-app`), `proton-vpn-cli` 1.0.2 (binary `protonvpn`), `proton-pass` 1.38.1, `proton-pass-cli` 2.3.3 (binary `pass-cli`), `protonmail-desktop` 1.14.0 (binary `proton-mail`).

### 1.2 Diagnosis (2026-09-18, read-only)

**VPN CLI/GUI traceback.** Reproduced on `protonvpn status | info | config list`. Every command still completes correctly afterwards. Chain:

1. `jeepney DBusErrorResponse: org.freedesktop.DBus.Error.ServiceUnknown ('The name is not activatable')` — no Secret Service on the session bus.
2. Both backends shipped by `proton-keyring-linux` 0.2.3 (`libsecret`, `secret_service`) need that daemon; `_is_backend_working` catches `keyring.errors.InitError` for each.
3. It then calls `logger.exception("Keyring %s error", backend)`; formatting `%s` calls `keyring.backend.KeyringBackend.__str__`, which reads the `SecretService.Keyring.priority` classproperty, which re-probes D-Bus and raises `RuntimeError: The Secret Service daemon is neither running nor activatable through D-Bus`. Python's logging prints `--- Logging error ---` plus both tracebacks. Upstream bug; harmless in itself.
4. `proton-core` 0.7.0 falls back to `KeyringBackendJsonFiles` → `~/.config/Proton/keyring-proton-sso-account-<id>.json` (mode 0644 inside the 0700 dir `~/.config/Proton`). Contents: `UID`, `AccessToken`, `RefreshToken`, `vpn/vpninfo/VPN/Password`, `vpn/certificate/{ClientKey,Certificate}`, `vpn/secrets/ed25519_privatekey`, location. The GUI (`proton.vpn.app.gtk`) links the same library and is on the same fallback.

**Electron apps (Pass, Mail).** They use Electron `safeStorage`; on Linux without a keyring it degrades to the `basic_text` obfuscation backend. They run and log in fine today.

**Not this track's business but found on the way:** Proton Pass 1.38.1 in nixpkgs (master too) vs 1.40.2 upstream — the in-app update toast is legitimate; Proton Mail logs `Missing proton-mail.desktop file` because it stats `/usr/share/applications/proton-mail.desktop` before asking `xdg-mime` (mailto already resolves to it through `mimeinfo.cache`); the VPN tunnel has never been connected on this host, and `hardening.nix` `rp_filter=1` ("no VPN routing") plus `network.nix` strict DNS-over-TLS will collide with Proton's plain-DNS `10.2.0.1` (`dns-priority -1500`, routing domain `~.`) when it is; `proton-cli update` / `pass-cli update` are self-updaters that cannot work against the read-only store; the six packages sit in system packages although CLAUDE.md prefers `modules/home/packages.nix` for user-facing tools.

### 1.3 nixpkgs facts (verified against the locked rev `e554fab72f81`, 2026-09-17)

- `services.gnome.gnome-keyring.enable` does exactly: install `gnome-keyring` (50.0); add `gnome-keyring` + `gcr_3` to `services.dbus.packages` (D-Bus activation of `org.freedesktop.secrets` and the `gcr` system prompter); add the keyring portal to `xdg.portal.extraPortals`; set **`security.pam.services.login.enableGnomeKeyring = true`**; install a `cap_ipc_lock=ep` wrapper for `gnome-keyring-daemon`. Nothing else. gnome-keyring ≥ 46 has no ssh-agent component.
- `services.greetd`: `enable`, `settings` (TOML), `useTextGreeter` (sets `StandardInput=tty`, `TTYPath=/dev/tty1`, `TTYReset/TTYVHangup/TTYVTDisallocate`), `restart` (default `true` → `Restart=on-success`), `greeterManagesPlymouth`. It forces `terminal.vt = 1`, disables `autovt@tty1`, creates user/group `greeter`, and ships `systemd.tmpfiles.rules = [ "d '/var/cache/tuigreet' - greeter greeter - -" ]`. Its PAM service `greetd` is defined with `useDefaultRules = false` and every stack (`auth`, `account`, `password`, `session`) as a `substack`/`include` of **`login`** — so `login`'s keyring hook applies to greetd logins with no further PAM config.
- `tuigreet` 0.11.1, `greetd` 0.10.3 available. Today's session entry `/run/current-system/sw/share/wayland-sessions/hyprland-uwsm.desktop` has `Exec=uwsm start -e -D Hyprland hyprland.desktop`; `uwsm start hyprland-uwsm.desktop` (what `profileExtra` runs) resolves the same entry.

## 2. Decisions

| # | Decision | Alternatives considered | Why |
|---|----------|------------------------|-----|
| D1 | **Scope = login gate + keyring now; LUKS is a separate later track** | (B) include LUKS now; (C) keyring only, keep autologin | Without disk encryption a login prompt stops only the casual "sit down and use it" case; a Microsoft-signed live USB or a pulled NVMe still reads everything. That was said plainly and jftx chose to land the config-only part today. (C) would leave the keyring auto-unlocked for anyone who powers on — defeats the stated concern. |
| D2 | **greetd + tuigreet** on VT1 | plain getty `login:` prompt (just drop `autologinUser`) | Proper login manager: clock, remembers last user, returns to the greeter when Hyprland exits (`Restart=on-success`), owns VT1 cleanly. The `--cmd` is byte-identical to today's `profileExtra`, so UWSM/session env is unchanged. The getty variant would have been the smallest diff; jftx picked greetd. |
| D3 | **gnome-keyring** as the Secret Service | KeePassXC secret-service; pass-secret-service; kwallet | Only option that unlocks with the login password via PAM and is D-Bus-activatable with zero user action; also what Electron `safeStorage` expects. KeePassXC would duplicate Proton Pass and needs a manual unlock each login. |
| D4 | **No idle auto-lock** | lock at 5 min / screen off at 10 | jftx: keep manual lock only (ALT+L). Idle config in `caelestia.nix` untouched. |
| D5 | **New file `modules/system/login.nix`** for greetd + keyring | put it in `hyprland.nix` | `hyprland.nix` is already "session enablement + PPD + i2c"; login/credential handling is its own concern and gets its own CLAUDE.md row. |
| D6 | **No seahorse**, no extra prompter package | install seahorse for a GUI | YAGNI. `secret-tool` (libsecret) verifies entries; `gcr_3` from the module covers the unlock dialog. |
| D7 | **Proton packages stay where they are** in this PR | move to `modules/home/packages.nix` now | Not what this PR is about; noted as a follow-up in §4 so the diff stays reviewable. |
| D8 | `hardening.nix` **untouched** | relax `rp_filter` now | The tunnel has never been connected; the rp_filter/DoT interplay is the VPN-tunnel track's first test, not this one's. |

## 3. Design

### 3.1 `modules/system/login.nix` (new)

```nix
{pkgs, ...}: {
  # Login gate: greetd owns VT1 (the module disables autovt@tty1) and runs
  # tuigreet; on a successful PAM auth it starts the same UWSM session entry
  # bash.nix used to exec on autologin. Restart=on-success (module default)
  # brings the greeter back when Hyprland exits.
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings.default_session.command =
      "${pkgs.tuigreet}/bin/tuigreet --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'";
  };

  # Secret Service (org.freedesktop.secrets) for Proton's clients and Electron
  # safeStorage. The module wires pam_gnome_keyring into the `login` PAM
  # service; greetd's PAM service is a substack of `login`, so the keyring is
  # created on first login and unlocked with the login password from then on.
  services.gnome.gnome-keyring.enable = true;

  # secret-tool: inspect/verify what lives in the keyring
  # (`secret-tool search --all service Proton`). The spec's runbook relies on
  # it; nothing else in the system pulls libsecret's CLI in.
  environment.systemPackages = [pkgs.libsecret];
}
```

`modules/system/default.nix` imports `./login.nix`. `--remember` writes the last user to `/var/cache/tuigreet` (created by the module). No `--sessions` flag: a single fixed command mirrors today's behaviour; a session menu can come later if a second compositor ever appears.

`pkgs.libsecret` is installed from the same file so `secret-tool` can inspect the keyring (§3.4 step 5).

### 3.2 Removals

- `modules/system/hyprland.nix`: delete `services.getty.autologinUser = "jftx";`. Getty on TTY2+ is untouched (escape hatch, §3.5).
- `modules/home/programs/bash.nix`: delete the `profileExtra` block (`uwsm check may-start` … `exec uwsm start …`). Nothing else in `bash.nix` changes.

### 3.3 Interactions checked

- **UWSM / session env:** unchanged — same `uwsm start` entry point, started by greetd inside a logind session on VT1 instead of by bash on an autologin getty.
- **caelestia lock screen:** authenticates through Quickshell's own PAM context, not greetd; unaffected. `allow_session_lock_restore` stays.
- **HM `ssh-agent`:** gnome-keyring 50 has no ssh component → no `SSH_AUTH_SOCK` contention.
- **`programs.dconf`, portals:** the module adds the keyring portal to `xdg.portal.extraPortals`; the Hyprland portal set already exists via `programs.hyprland`.
- **Electron apps:** Pass and Mail will detect a real `safeStorage` backend on next start and may ask for one fresh login — expected, one-time.
- **Kernel hardening / firewall / resolved:** nothing here touches them.

### 3.4 Proton migration (runbook, post-activation)

1. In a terminal: `busctl --user list | grep -i secrets` → `org.freedesktop.secrets` owned by `gnome-keyring-daemon`.
2. `protonvpn signout && protonvpn signin` → session lands in the keyring. `protonvpn status` prints **no** `--- Logging error ---`.
3. Open `protonvpn-app`, sign out/in once so the GUI's copy migrates too.
4. `rm ~/.config/Proton/keyring-proton-sso-*.json` — the fallback files stay on disk otherwise.
5. `secret-tool search --all service Proton` lists the entries (proton-keyring-linux stores under `KEYRING_SERVICE = "Proton"`, usernames `proton-sso-accounts` / `proton-sso-account-<id>`); `ls ~/.local/share/keyrings/` shows `login.keyring`.
6. Start Proton Pass and Proton Mail; log in again if prompted.

### 3.5 Verification, activation, rollback

**Before activation (Claude):** `git add` new files, `nix flake check`, `trb` (`nixos-rebuild build`) — both green. Diff reviewed: exactly `login.nix` (+), `default.nix` (+1 import), `hyprland.nix` (−1), `bash.nix` (−5), CLAUDE.md, this spec, plan.

**Pre-flight (jftx):** `sudo -k && sudo true` — confirm the password is known; greetd will demand it.

**Activation (jftx):** `nixos-rebuild boot --flake ~/nixos#blackgarden --sudo && reboot`. **Not `rb`:** a live `switch` starts the new greetd unit immediately; it `Conflicts=getty@tty1.service` and opens VT1 with TTY reset/hangup while the running Hyprland session is displayed there. `boot` installs the generation (lanzaboote signs it as usual) and makes it the default without activating anything; the reboot does the switch. The `profileExtra` removal only matters for new logins.

**Expected after reboot:** tuigreet on VT1 with clock; username pre-filled after the first `--remember`; password → Hyprland + caelestia exactly as before; `loginctl` shows one `seat0` session of type `wayland` for jftx; `systemctl --user status caelestia` active; `pgrep -af gnome-keyring-daemon` shows `--daemonize --login` (PAM-started) with `secrets` component. Then §3.4.

**Escape hatch:** if the greeter fails or the session never starts: CTRL+ALT+F2 → getty `login:` → jftx → `sudo nixos-rebuild switch --rollback` → `reboot`. Previous generation still has autologin, so this is always recoverable from the keyboard. Secure Boot is unaffected (lanzaboote signs every generation).

**Risks:**
- Login password ≠ keyring password after a future `passwd` change → PAM cannot unlock, the `gcr` prompter asks for the *old* password at first secret access. Remedy without seahorse: `rm ~/.local/share/keyrings/login.keyring`, log out/in (PAM recreates it with the new password), then re-sign-in to Proton (§3.4 steps 2–3). Documented, not mitigated.
- tuigreet `--remember` needs `/var/cache/tuigreet` writable by `greeter` — module tmpfiles handles it; verify on first boot.
- Activating with `rb`/`switch` instead of `boot` would start greetd under the live session (see Activation). Documented in CLAUDE.md's Key Commands so it is not repeated on later `login.nix` edits.

### 3.6 Docs

- **CLAUDE.md:** Overview sentence ("getty autologin to user jftx" → "greetd/tuigreet login on VT1, gnome-keyring unlocked at login"); `modules/system` file list + `login.nix` row in "Where to make a change"; `hyprland.nix` description loses "getty autologin"; Architecture Notes "Hyprland" bullet: autostart paragraph rewritten; new "Login & keyring" bullet with the Proton keyring consequence and the `signout/signin` migration note; Proton packages mentioned with their binary names.
- **Memory** (`proton-suite.md`, index): status → in flight, #29.

## 4. Out of scope / follow-ups (not in this PR)

- **LUKS for the ext4 root** — the real fix for physical access; offline `cryptsetup reencrypt` or reinstall, passphrase vs TPM2 (`systemd-cryptenroll`, pairs with lanzaboote). New issue after this lands.
- **Idle auto-lock** — declined (D4).
- **Proton Pass 1.38.1 → 1.40.2** — jftx: wait for nixpkgs (PR #555299 open for 1.39.1).
- **VPN tunnel first-connect test** — `rp_filter=1` vs kill-switch policy routing; strict DoT vs Proton DNS `10.2.0.1` (either DNS breaks or NetShield is bypassed via Quad9-through-tunnel). Kill switch already `standard`: lingering `pvpn-killswitch` NM connection → `nmcli con delete pvpn-killswitch`.
- **Move Proton packages** to `modules/home/packages.nix` (D7).
- **Proton Mail `Missing proton-mail.desktop`** — upstream hardcoded FHS path; cosmetic.
