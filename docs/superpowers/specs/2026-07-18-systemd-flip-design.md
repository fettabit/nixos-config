# Systemd Flip + Solidify — Design (Track B step 12, FINAL)

**Date:** 2026-07-18 · **Status:** approved by jftx · **Master plan:** `docs/plans/quickshell-matugen-migration.md` §3.5 step 12

The island stops being a manually-daemonized dev artifact and becomes a
**systemd user service**; the QML config solidifies from the dev
out-of-store symlink to a **pure store path** (matching the hypr-Lua
workflow); **waybar and swaync leave the system entirely**; CLAUDE.md is
rewritten to describe the machine as it actually is. This closes Track B
— the step ends with the branch PR + merge (issue #6).

## Decisions (jftx, 2026-07-18)

| Question | Decision |
|---|---|
| Waybar/swaync disposition | **Full removal** — files and packages. Resolves a master-plan self-contradiction: the step 12 line said "files + packages stay in repo", but the step 10 note ("swaync D-Bus activation file survives until step 12") and the 2026-07-15 handoff said drop. Drop wins; git history is the fallback if waybar is ever wanted back. |
| CLAUDE.md scope | **Full accuracy audit** — verify every claim against the repo, not just the plan's targeted list. Two claims already known flat-out wrong (channel, bootloader); stale CLAUDE.md claims cost real debugging time. |
| Sequencing | **One rb cycle, commits per concern.** (Two-phase flip-then-remove rejected: waybar being installed is no fallback for island-only features; costs a second rb + reboot for near-zero safety. Single atomic commit rejected: jams a prose rewrite into a system commit; NixOS generations already give atomic rollback.) |
| `rb` alias | Gains a third link: `systemctl --user restart quickshell` (jftx request). One `rb` refreshes system + Hyprland Lua + island QML. |
| ALT+R | Removed with waybar, key left unbound — no replacement binding (YAGNI). |

## Architecture — `quickshell.nix` (flip + solidify)

Two semantic lines change:

- `configs.island = ./quickshell;` — replaces `mkOutOfStoreSymlink`.
  The QML tree is copied into the store at build time, materialized
  read-only at `~/.config/quickshell/island`. **QML edits now require
  `rb`** (which restarts the unit via the new alias) — no hot reload.
- `systemd.enable = true;` — generates `quickshell.service`.

HM module facts (verified against the module source this session, not
assumed): `ExecStart = quickshell --config island` (picks up
`activeConfig`), `Restart=on-failure`, `After`/`WantedBy =
config.wayland.systemd.target` → default `graphical-session.target`,
which UWSM manages with the session env imported. **No unit overrides
needed.** `Restart=on-failure` also covers the "global binds inert if
the shell dies" caveat; systemd's single-instance guarantee retires the
duplicate-GlobalShortcut crash class.

Known cosmetic consequence (0.3.0 doesn't canonicalize config paths):
the shell ID changes at solidify → per-shell cache/state resets once.

File comments rewritten to describe the final state, not the dev phase.

## Architecture — `bash.nix`

```
rb = "nixos-rebuild switch --flake ~/nixos#blackgarden --sudo && hyprctl reload && systemctl --user restart quickshell";
```

Near-instant and harmless on rebuilds that didn't touch QML; manual
`systemctl restart` never conflicts with `Restart=on-failure`.

## Architecture — waybar/swaync removal (all deletions)

- **`autostart.lua`** — drop `hl.exec_cmd("waybar")`; `awww-daemon`
  stays (wallpaper daemon, load-bearing).
- **`binds.lua:28`** — remove the ALT+R waybar launch bind.
- **Files** — delete `modules/home/desktop/waybar/` (config.jsonc,
  style.css, scripts/launch.sh) and `waybar.nix`; remove the import
  from `modules/home/default.nix`.
- **`modules/system/packages.nix`** — remove `waybar` and
  `swaynotificationcenter`.

Payoff: swaync's D-Bus activation file leaves the system, so nothing
can race the island for `org.freedesktop.Notifications` again — the
post-reboot `pkill swaync` ritual dies here. Verified during
exploration: nothing else references either tool (no matugen templates,
no other imports). The `shell.qml` "atomic swaync swap" comment reads
as history and stays.

## CLAUDE.md — full accuracy audit

Method: walk every claim against the repo; fix, add, keep. Structure
stays (Overview → Key Commands → Layout → Architecture Notes); it
remains a guidance doc — detail lives in the master plan, which
CLAUDE.md now points to.

**Known-wrong fixes:** channel `nixos-26.05` → `nixos-unstable` (verify
home-manager branch from `flake.nix` while editing); bootloader
systemd-boot/limit 10 → GRUB (Windows dual-boot)/limit 5; `rb` alias
description → the new three-link chain; home import list → includes
`desktop/{quickshell,theme}.nix`, drops waybar.

**New content:** island shell section (quickshell 0.3.0 as
`quickshell.service`; QML source of truth
`modules/home/desktop/quickshell/` via store path; edit → `rb`
workflow; GlobalShortcut/`global` dispatcher keybind routing; the
island **is** the notification daemon). Theming pipeline section
(matugen → `/tmp/qs_colors.json` → event-driven `Theme.qml`;
`wallpaper-set` as the sole front door; the **never-restart-
`wallpaper.timer`** gotcha encoded permanently — `OnActiveSec=5s`
fires a random pick 5 s later). Plan locations
(`docs/plans/quickshell-matugen-migration.md` master plan +
`docs/superpowers/{specs,plans}/` per-feature).

**Verify-while-editing (unknown freshness):** nix.gc claim, stale-files
note (root `configuration.nix`/`home.nix`), fonts/spicetify sections.
Whatever checks out stays untouched.

## Commits

1. `feature: quickshell systemd service + store-path solidify` —
   quickshell.nix flip, rb alias.
2. `feature: waybar + swaync retired` — autostart/binds/packages/files.
3. `docs: CLAUDE.md rewritten for the island era` — the full audit.
4. `docs: step 12 done marker` — master plan checkbox, **after** live
   verification.

## Verification

**Pre-rb gates (Claude):** `git add` all adds/deletes first (flake
purity), then `nix flake check` + `trb` (`nixos-rebuild build`). No new
shell scripts this step; the build gate stays standard.

**Activation (jftx):** no manual island instance is currently running
(confirmed 2026-07-18), so the sequence is simply `rb` → paste output →
**full reboot**. Guard: if a manual `qs` instance *were* running at rb
time, quit it first — a systemd instance starting alongside it risks
the duplicate-GlobalShortcut crash.

**Post-reboot checklist** (clean session, zero manual intervention;
probes batched tight — jftx's clicks land in focus-grabbed expansions):

1. `systemctl --user status quickshell` → active (running), pulled in
   by `graphical-session.target`.
2. Island up untouched: clock ticking; `notify-send` drives a toast;
   `pgrep swaync` empty — **no pkill ritual**.
3. Binds: ALT+SPACE launcher, SUPER+V volume, F10–F12 flash,
   ALT+SHIFT+W grid; ALT+R does nothing; no waybar process.
4. `wallpaper-set ~/wallpapers/<img>` → full retheme cascade including
   the island; `list-timers` shows wallpaper NEXT ≈ 10 min.
5. `journalctl --user -u quickshell` free of errors.

**Then:** Track B PR + merge closing issue #6
(finishing-a-development-branch flow, code review pass before merge).

## Out of scope

Any waybar replacement for ALT+R, issue #10 slider granularity
(deferred to Track C), all Track C items (panels, control center,
lockscreen/session, clipboard), spicetify-matugen (master-plan
exclusion). The master plan's step 12 "files + packages stay" wording
is superseded by this spec, not edited retroactively — the done marker
(commit 4) records the deviation.
