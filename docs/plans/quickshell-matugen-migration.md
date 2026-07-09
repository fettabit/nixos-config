# Quickshell + Matugen Desktop Shell Migration

**Status:** Track A (theming pipeline) **MERGED** — PR #8, squash `4556abf`, 2026-07-05. Track B **REVISED 2026-07-05, awaiting approval** — native Quickshell 0.3.0 rewrite; the reference repo is design inspiration only, none of its code is vendored. Revision decisions confirmed with jftx in the 2026-07-05 gap interview.
**Reference (visuals only):** https://github.com/ilyamiro/nixos-configuration @ `d66c4a5` — consult for island/launcher/picker aesthetics. Do **not** port code: it predates Quickshell 0.2's breaking changes and its helper-script layer is superseded by 0.3.0 built-ins (see 3.2b).

This document is self-contained: a future Claude Code session can execute it without re-deriving context.

---

## Locked-in decisions

From the 2026-07-04 gap interview:

| Topic | Decision |
|---|---|
| Bar | **Not** a port of his TopBar. Build an iOS-style **dynamic island**: floating centered pill showing only the clock, which expands/morphs when features open. |
| Theming | Matugen is canonical. Wallpaper-driven, regenerates on **every** wallpaper change including the 10-min systemd timer. Dark mode always. Drives everything it can touch incl. Hyprland window decorations. |
| Wallpapers | `~/wallpapers`, backend is **awww** (swww successor, CLI-compatible). **No video wallpapers.** |
| Keybinds | Keep jftx's ALT binds: `ALT+SPACE` = app launcher (replacing rofi drun), `ALT+Q` = close window, `ALT+W` / `ALT+SHIFT+W` = wallpaper random/picker. Everything else follows the reference layout (SUPER+…). |
| Incumbents | Waybar, swaync, rofi-launcher get **removed from autostart/binds but files kept in repo** for now. |
| Scope now | **Core tier only**: island bar, notifications, app launcher, volume popup (+swayosd), wallpaper picker. Panels/Session/Extras are Track C (later sessions). |
| swayosd | Yes (volume/capslock OSD; no brightness keys on this desktop). |
| Bluetooth | `hardware.bluetooth` enabled (landed in Track A). |
| Consumers | Quickshell, Hyprland decorations, kitty, GTK3/4 + Qt (qt6ct + adw-gtk3), vesktop, firefox userChrome (deferred until a profile exists), cava, swayosd CSS. Spicetify deferred. Rofi templates skipped. |
| Git workflow | Feature branches off `main`, GitHub issues per track, PRs. Claude may run `nix flake check` and `nixos-rebuild build` (`trb`) itself. **`rb` (switch) is run by jftx only** — stop, ask, and wait for pasted output. |

Revision 2026-07-05 (Track B gap interview):

| Topic | Decision |
|---|---|
| Track B approach | **Native rewrite** against Quickshell 0.3.0 built-ins (FileView, Pipewire, DesktopEntries, GlobalShortcut, Mpris, NotificationServer, SystemClock). No vendored QML, no bash/python sidecars. Reference repo = design language only. |
| Island scope | **Everything morphs**: launcher, volume popup, notifications, and wallpaper picker all render as expansions of the single island window — one window, one animation system. |
| Notifications UX | Incoming notification morphs the island open (app icon, summary, body), auto-collapses after timeout. No history/notification-center in core tier — that is a Track C panel. |
| Idle pill | Clock always; pill widens with now-playing track title (native Mpris service) when media plays. |
| Service lifecycle | Quickshell + swayosd run as **systemd user services** via Home Manager modules (`programs.quickshell.systemd`, `services.swayosd`) on `graphical-session.target` (activated by UWSM) — not `autostart.lua` execs. `Restart=on-failure` replaces the reference's zombie-watchdog script. |

## Hardware/context facts

Verified 2026-07-05:

- Host `blackgarden`: desktop, single monitor **DP-3 5120×1440@240, scale 1** (super-ultrawide; all reference sizing was tuned on 1920×1080 — re-audit everything). No battery/backlight. Bluetooth enabled.
- Flake tracks **nixos-unstable** (CLAUDE.md stale — says 26.05; fixed at step 12). Installed: **Quickshell 0.3.0, Matugen 4.1.0, Hyprland 0.55.4**.
- The nixpkgs quickshell build ships **all** optional QML modules (verified on disk): `Quickshell.{Io,Wayland,Widgets,Hyprland,Bluetooth,Networking,DBusMenu,WindowManager}` + `Quickshell.Services.{Pipewire,Notifications,Mpris,SystemTray,Pam,Polkit,UPower,Greetd}`. No extra Qt wrangling needed for any tier.
- Home Manager (pinned rev) ships `programs.quickshell` (configs attrset, `activeConfig`, systemd service with `Restart=on-failure`, `WantedBy=graphical-session.target`) and `services.swayosd` (`stylePath`, systemd unit). UWSM activates `graphical-session.target`, so both services start on login.
- Landed in Track A: matugen, fonts (`jetbrains-mono`, `nerd-fonts.iosevka`), qt5ct/qt6ct, adw-gtk3, adwaita-icon-theme, dconf, bluetooth.
- Still missing for core: **swayosd** (enabled at step 6). Missing for later tiers: hypridle, satty, cliphist.

---

## 3.1 Current architecture (jftx's repo, post-Track A)

`flake.nix` (nixos-unstable + home-manager + spicetify-nix) → `hosts/blackgarden` + `modules/system/*` and `modules/home/*` via HM-as-NixOS-module (`useGlobalPkgs`, `backupFileExtension = "backup"`).

Session path: getty autologin on TTY1 → `bash.nix profileExtra` → `uwsm start hyprland-uwsm.desktop` → Hyprland reads hand-written **Lua** at `~/.config/hypr/hyprland.lua` (materialized from `modules/home/desktop/hypr/` via `xdg.configFile."hypr"`, `recursive = true`) → `modules/autostart.lua` execs **waybar, swaync, awww-daemon** (waybar/swaync retire in Track B).

**Theming pipeline (Track A, live):** templates in `modules/home/programs/matugen/` render to runtime paths — `/tmp/qs_colors.json` (for Quickshell), `~/.cache/matugen/hypr-colors.lua` (loaded by `decorations.lua` via `pcall` with static fallback), `/tmp/kitty-matugen-colors.conf` (kitty include), `~/.cache/matugen/colors-gtk.css` (GTK `@import` via `theme.nix`), qt5ct/qt6ct scheme+qss, `~/.config/swayosd/style.css`, vesktop theme, cava colors. Trigger: `wallpaper-random.sh`/`wallpaper-picker.sh` run `matugen image "$pick" --mode dark --prefer saturation` then `matugen-reload` (kitty SIGUSR1, swayosd try-restart, GTK gsettings bounce, `hyprctl reload` with instance-signature discovery). Timer: 5 s after login, then every 10 min; `ALT+W` restarts the service resetting the countdown; no-repeat state in `~/.local/state/wallpaper-current`.

## 3.2 Reference architecture (recon record — NOT ported)

*Retained for context; as of the 2026-07-05 revision this is design inspiration only.*

Channel-based NixOS (no flake), HM as NixOS module, `mkOutOfStoreSymlink "/etc/nixos/config/..."` everywhere. Shell: `Main.qml` (IPC dispatcher + a single morphing master window hosting all popups + notification daemon), `TopBar.qml` (not wanted), `Floating.qml` (out of scope). All keybinds route through `scripts/qs_manager.sh` (cache prep, zombie respawn, IPC call). Support singletons poll state via `Process` + Timers; `MatugenColors.qml` polls `/tmp/qs_colors.json` every 1 s and maps Material tokens to Catppuccin names. Helper layer: `app_fetcher.py` (launcher entries), `audio_control.sh`/`get_audio_state.py` (volume), `caching.sh` (imagemagick thumbnails).

What we keep from it: the **morphing-island visual concept**, the launcher and wallpaper-picker look, the matugen template set (already adapted in Track A), and the atomic swaync-swap insight.

### 3.2b Why the reference code is not vendored (2026-07-05 research)

1. **Quickshell 0.2.0 breaking changes postdate his QML**: relative-path escapes (`../../foo.png`) banned; `Quickshell.shellRoot` → `shellDir`; root-relative `import qs.path.to.module` scheme introduced (with QMLLS support). Every vendored file would need patching before the planned path/font/awww adaptations even start.
2. **Quickshell 0.3.0 built-ins supersede the entire helper layer:**

| Reference mechanism | Native 0.3.0 replacement |
|---|---|
| `MatugenColors.qml` 1 s `cat` polling | `FileView { watchChanges: true }` + `JsonAdapter` — event-driven |
| `app_fetcher.py` | `DesktopEntries` singleton |
| `audio_control.sh` + `get_audio_state.py` + watchers | `Quickshell.Services.Pipewire` (`PwObjectTracker` + `defaultAudioSink.audio`) — live bindings |
| `qs_manager.sh` keybind routing | `GlobalShortcut` (Hyprland `global` dispatcher) — no process spawn per keypress |
| `qs_manager.sh` zombie watchdog | `programs.quickshell.systemd` (`Restart=on-failure`) |
| `caching.sh` thumbnail pre-gen | `Image { sourceSize }` async downscaling (revisit only if slow) |
| Clock Timer+Date | `SystemClock` |
| Catppuccin token mapping | dropped — our QML uses Material You token names directly |

## 3.3 Track B delta (revised 2026-07-05)

### New files

```
modules/home/desktop/quickshell.nix   # programs.quickshell (named config "island", systemd) + services.swayosd
modules/home/desktop/quickshell/      # the QML tree = the "island" config
  shell.qml                           # ShellRoot: Island window, NotificationServer, GlobalShortcuts, IpcHandler
  theme/Theme.qml                     # pragma Singleton: FileView(watchChanges)+JsonAdapter over /tmp/qs_colors.json;
                                      #   Material You token properties (primary, surface, …) with built-in dark
                                      #   fallbacks (pre-first-generation boots); central font family constants
  island/Island.qml                   # PanelWindow anchored top-center: morph engine (states + animated size),
                                      #   Loader/LazyLoader per feature, ESC/click-outside collapse
  island/Pill.qml                     # collapsed content: SystemClock clock + Mpris now-playing text
  launcher/Launcher.qml               # DesktopEntries + fuzzy filter, entry.execute(), ESC closes
  volume/VolumePopup.qml              # Pipewire default sink: volume slider, mute, output-device selection
  notifications/NotificationView.qml  # in-island rendering of tracked notifications, auto-collapse timeout
  wallpapers/WallpaperPicker.qml      # FolderListModel over ~/wallpapers, async thumbnails, select → wallpaper-set
modules/home/services/scripts/wallpaper-set.sh  # NEW: shared "apply wallpaper <path>" (state file + awww img +
                                                #   matugen + matugen-reload), extracted from wallpaper-random.sh
```

QML conventions: root-relative imports (`import qs.theme`), no `../` escapes, one directory per concern mirroring the repo's `modules/` style. No bash/python sidecars — the shell's only external calls are `wallpaper-set` (picker selection) and nothing else; volume binds call `swayosd-client` from Hyprland, not from QML.

### Modified files

```
modules/home/default.nix          # import desktop/quickshell.nix
modules/system/packages.nix       # remove quickshell + qt6.qtdeclarative (programs.quickshell owns the package;
                                  #   verify at step 6 trb/manual run that nothing else needed qtdeclarative)
modules/home/services/wallpaper.nix              # add wallpaper-set writeShellApplication; wallpaper-random
modules/home/services/scripts/wallpaper-random.sh #   becomes "pick non-repeating, then exec wallpaper-set"
modules/home/desktop/hypr/modules/binds.lua      # ALT+SPACE → global quickshell:launcher (rofi drun bind removed);
                                                 # ALT+SHIFT+W → global quickshell:wallpapers (script kept as fallback);
                                                 # SUPER+V → global quickshell:volume; volume keys wpctl → swayosd-client;
                                                 # step 12: remove ALT+R waybar launch bind
modules/home/desktop/hypr/modules/autostart.lua  # step 10: drop swaync; step 12: drop waybar (awww-daemon stays)
modules/home/desktop/hypr/modules/windowrules.lua # layerrules for quickshell layer namespaces (audit at steps 7–9)
CLAUDE.md                                        # step 12: unstable channel, island shell, theming pipeline, plan location
```

### Explicitly NOT added

`qs_manager.sh`, `caching.sh`, `app_fetcher.py`, `audio_control.sh`/`get_audio_state.py`, watcher loops, `WindowRegistry.js`, Catppuccin token mapping (all superseded by 0.3.0 built-ins). Still excluded from before: mpvpaper/video paths, eww, blueman, his plymouth/rofi/zsh/neovim configs.

## 3.4 Integration strategy (revised 2026-07-05)

**Branching**: `feat/quickshell-core` off `main`, tracked by issue #6, small commits per step, PR at the end. Claude runs `nix flake check` + `nixos-rebuild build` freely; **every activation (`rb`) is jftx's** — stop and request it, wait for pasted output.

**Config wiring & iteration speed**: `programs.quickshell.configs.island = <source>; activeConfig = "island"` → materialized at `~/.config/quickshell/island`, launched as `qs -c island`. Dev phase: source is `mkOutOfStoreSymlink "${config.home.homeDirectory}/nixos/modules/home/desktop/quickshell"` so QML edits hot-reload live; step 12 switches to the pure store path (matching the hypr-Lua workflow). `programs.quickshell.systemd.enable` stays **false** until step 12 — during steps 6–11 quickshell is launched manually in a kitty. 0.3.0 note: config paths are no longer canonicalized, so the shell ID differs between the symlinked dev path and the final store path — per-shell cache/state resets once at solidify; harmless.

**Keybind routing**: `GlobalShortcut` objects in `shell.qml` (appid `quickshell`; names `launcher`, `volume`, `wallpapers`) bound in `binds.lua` via Hyprland's `global` dispatcher (`global, quickshell:launcher`). If the `hl.*` Lua API has no wrapper for it, use its generic dispatcher call; `qs ipc call` remains as scripting/testing fallback (an `IpcHandler` is kept in `shell.qml` regardless). Caveats: duplicate appid:name registrations can crash — exactly one quickshell instance (enforced by systemd at step 12); if the shell is down, `global` binds are inert — `Restart=on-failure` covers it, and `ALT+RETURN` (kitty) never routes through the shell.

**Audio path**: volume keys → `swayosd-client --output-volume raise/lower`, `--output-volume mute-toggle` (changes volume *and* shows the themed OSD). Quickshell's Pipewire bindings observe the change live — no IPC between swayosd and the island needed. `services.swayosd.enable = true`; matugen already writes `~/.config/swayosd/style.css`, swayosd-server's default lookup path (set `stylePath` explicitly only if step 6 verification shows it isn't picked up).

**Notification daemon conflict**: quickshell and swaync both claim `org.freedesktop.Notifications` — the swap is atomic in step 10 (same commit enables `NotificationServer` and removes swaync from `autostart.lua`); rollback = revert one commit.

**Matugen**: pipeline untouched. `Theme.qml` consumes `/tmp/qs_colors.json` event-driven (`FileView.watchChanges`); recolor latency drops from ≤1 s (reference polling) to effectively instant. All fallback behavior from Track A remains.

**Wallpaper machinery**: extracting `wallpaper-set` keeps a single code path shared by the random timer, the rofi fallback picker, and the QML picker — state-file no-repeat logic preserved for all three.

## 3.5 Step-by-step implementation order

**Track A — theming pipeline: ✅ MERGED 2026-07-05** (PR #8, squash `4556abf`; steps 0–5 of the original plan). Matugen 4.1.0 renders 2.x-era templates unchanged; `--prefer saturation --mode dark` wired for non-interactive runs.

**Track B — island shell core (branch `feat/quickshell-core`, issue #6)**

6. **Scaffold + theme service.** `quickshell.nix` (programs.quickshell w/ dev out-of-store symlink config `island`, systemd **off**; `services.swayosd.enable`); move quickshell package ownership from `modules/system/packages.nix` to the HM module (drop `qt6.qtdeclarative` too — restore if the step-6 manual run misses QML modules); `shell.qml` stub + `theme/Theme.qml`. Verify: `nix flake check` + `trb`; **rb (ask jftx)**; `qs -c island` renders a test rect in wallpaper colors, `ALT+W` recolors it instantly; `swayosd-client --output-volume raise` shows a themed OSD.
7. **Island pill + morph engine.** `Island.qml` (PanelWindow, top-center), `Pill.qml` (SystemClock + Mpris now-playing), morph states + animated width/height with a placeholder expanded panel, `GlobalShortcut`s + `IpcHandler`, ESC/click-outside collapse. Size audit on 5120×1440. Verify (manual run): live clock; track title appears when Spotify plays; `qs ipc call` toggles the placeholder expansion smoothly; recolors live.
   **Addendum 2026-07-06 (approved):** the pill becomes clock-only; now-playing moves to a hover-triggered **peek** — a third, display-only morph state (no focus grab) showing album art + title/artist, large clock + date, with the right slot reserved for Track C network status. Spec: `docs/superpowers/specs/2026-07-06-island-hover-peek-design.md`. Also: `margins.top` 12→15, exclusive-zone bottom pad 10→1 (values feel-tuned by jftx). Implementation plan: `docs/superpowers/plans/2026-07-07-island-hover-peek.md`.
8. **Launcher.** `Launcher.qml` (DesktopEntries + fuzzy filter) as an island expansion; `binds.lua`: `ALT+SPACE` → `global, quickshell:launcher`, rofi drun bind removed (same commit). Verify: ALT+SPACE expands island, fuzzy-finds, launches, ESC collapses. **✅ done 2026-07-08** (spec + plan in docs/superpowers/; inverted-fzf layout with breathing height per jftx's design — search bar at the panel's bottom edge, results stack upward, tiered fuzzy ranking in fuzzy.js; Lua side uses `hl.dsp.global("quickshell:launcher")`).
9. **Volume.** `VolumePopup.qml` (Pipewire sink volume/mute/device select) as an island expansion on `SUPER+V`; volume keys switch `wpctl` → `swayosd-client`. Verify: keys show themed OSD; popup slider and device switch work live; island recolors on wallpaper change mid-popup.
10. **Notifications.** `NotificationServer` in `shell.qml` + `NotificationView.qml` island morph with auto-collapse; **same commit** removes swaync from `autostart.lua`. Verify: **rb (ask jftx)** + `pkill swaync`; `notify-send test` morphs the island; `journalctl --user` shows no daemon conflict.
11. **Wallpaper picker.** `wallpaper-set` extraction in `wallpaper.nix` + scripts; `WallpaperPicker.qml` thumbnail grid as island expansion; `ALT+SHIFT+W` → `global, quickshell:wallpapers` (rofi picker script kept, bind replaced). Verify: grid opens, selection sets wallpaper + full retheme cascade (island included), 10-min timer no-repeat logic intact.
12. **Systemd flip + solidify.** `programs.quickshell.systemd.enable = true`; `autostart.lua` drops waybar (`ALT+R` launch bind removed; waybar/swaync files + packages stay in repo); quickshell config source switched to the pure store path; CLAUDE.md updated (unstable channel, island shell, theming pipeline, this plan). Verify: **rb + full reboot (ask jftx)** → clean session: island up via systemd (`systemctl --user status quickshell swayosd`), 10-min retheme cascade works, ALT binds intact, `nix flake check` clean. PR + merge.

**Track C — later sessions (planned, not now)**
- **Panels** (one PR each): network + bluetooth panel — now via native `Quickshell.Networking`/`Quickshell.Bluetooth` (no nmcli/bluetoothctl parsing); a compact network indicator also fills the island peek's reserved right slot (see step 7 addendum); calendar (+weather); music popup + cava; monitors; settings; guide.
- **Control center** (added 2026-07-08 per jftx): one island expansion aggregating quick-toggle tiles (Wi-Fi, Bluetooth, DND, night light), volume + brightness sliders, output-device row, media card with controls, and notification history — Android-quick-settings style (reference screenshot from jftx, 2026-07-08 session). Composes the other Track C panels' backends instead of duplicating them; absorbs the standalone notification-history idea. Step 9 builds its volume slider + output-device row as reusable components so this panel can mount them unchanged.
- **Session**: lockscreen via `Quickshell.Services.Pam` + hypridle (decide value on an autologin machine); screenshot overlay (grim/slurp + satty). 0.3.0's Polkit-agent support could replace hyprpolkitagent — evaluate here.
- **Extras**: clipboard manager (+cliphist), quickactions, focustime.
- **Deferred/excluded**: spicetify-matugen (fights Nix-managed spicetify), stewart, movies, updater.

## 3.6 Risks and mitigations (revised 2026-07-05)

| Risk | Mitigation |
|---|---|
| **Morph engine is custom code** (the most novel part now that nothing is vendored) | Built at step 7 against a placeholder panel *before* any feature lands; feature Loaders stay decoupled from animation logic; each later step only fills a Loader slot. |
| **Ultrawide mis-sizing** (island proportions on 5120×1440) | Island is custom-built for this display; audit sizes at every step; test at full res each step. |
| **Notification daemon conflict** (swaync vs quickshell) | Atomic swap in step 10 (same commit removes swaync autostart); rollback = revert one commit. |
| **GlobalShortcut caveats** | Duplicate appid:name can crash — single instance enforced by systemd (step 12); binds inert if shell down — `Restart=on-failure` + `ALT+RETURN` kitty bind never routes through the shell; NixOS generation rollback as last resort. |
| **Runtime outputs vs declarative HM** | Unchanged from Track A: outputs only in `/tmp`, `~/.cache`, writable config dirs; all consumers have no-output fallbacks; timer self-heals 5 s after login. |
| **10-min retheme side effects** (GTK toggle flash, swayosd restart pop) | Accept initially; tune later (drop swayosd restart from the timer path, keep for manual picks). |
| **Dev symlink shell-ID drift** (0.3.0 removed path canonicalization) | Per-shell cache/state resets once when step 12 solidifies the store path — cosmetic. |
| **Removing `qt6.qtdeclarative` from system packages** | Done at step 6 with immediate `trb` + manual-run verification; restore if any QML import breaks. |
| **`rb` requires user action** | Protocol locked: Claude stops and requests activation; jftx runs `rb` and pastes output. `trb`/`nix flake check` cover most verification. |
