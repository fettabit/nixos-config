# Island Volume — Design (Track B step 9)

**Date:** 2026-07-09 · **Status:** approved by jftx · **Master plan:** `docs/plans/quickshell-matugen-migration.md` §3.5 step 9

Volume control renders as two island morph states: a **flash** (display-only
OSD replacing swayosd entirely) triggered by volume keys and wheel, and a
**panel** (slider + mute + output-device rows) on SUPER+V. A new `Audio.qml`
singleton is the only PipeWire writer in the shell. swayosd — the service and
its matugen template — is removed in this step.

## Decisions (jftx, 2026-07-09)

| Question | Decision |
|---|---|
| OSD | Island **flash**: a 4th display-only morph state (icon + slim track + percentage). swayosd dropped entirely — `services.swayosd`, the matugen swayosd template, and the master-plan audio path all go. |
| Panel scope | **Output only**: volume slider, mute toggle, output-device radio rows. Mic stays on `wpctl` (XF86AudioMicMute bind unchanged). |
| Slider style | Slim, flash-matched: thin track + small knob (per jftx's reference screenshot), not a chunky filled bar. |
| Volume keys | jftx's board emits **plain F10/F11/F12 keysyms — the existing XF86Audio binds have never fired**. Bind F10=mute, F11=down, F12=up directly; keep `XF86Audio{Mute,LowerVolume,RaiseVolume}` as aliases to the same dispatchers. |
| Wheel | On pill and peek: ±5% + flash. On the panel slider: ±5%, no flash (panel is open). |
| Mute interplay | Any island-initiated volume **increase** (F12, wheel up, slider drag up) unmutes. |
| Step / clamp | ±5% per step; volume clamps to 0–100%. |
| Reusability | `VolumeSlider.qml` + `OutputDeviceList.qml` built standalone so the Track C control center mounts them unchanged. |

## Architecture

New files in `modules/home/desktop/quickshell/island/` (flat, per existing
convention):

- **`Audio.qml`** — `pragma Singleton` (same mechanism as `theme/Theme.qml`).
  Wraps `Quickshell.Services.Pipewire`: the **only** component that writes to
  PipeWire. Holds the `PwObjectTracker` for the default sink + the sink list.
  API: `volume`, `muted`, `sink`, `sinks`, `setVolume(v)`, `step(dir)`
  (±5%), `toggleMute()`, `setSink(node)`. Both write paths clamp 0–100%
  and **unmute when the result is higher than the current volume** — the
  one unmute rule shared by F12, wheel up, and slider drag.
  Null-safe: every property guards `sink === null` (startup race, sink
  removal). Emits no UI signals — flash triggering stays with the callers.
- **`VolumeFlash.qml`** — flash content: nf volume glyph (mute state swaps
  the glyph), slim track, percentage label. Display-only; no MouseArea.
- **`VolumePanel.qml`** — the expansion: `VolumeSlider` + mute toggle +
  `OutputDeviceList`. Plain Item exposing implicit size; the island's
  existing Behaviors animate geometry (launcher pattern).
- **`VolumeSlider.qml`** — thin track + knob, drag + wheel, Material tokens.
  Value in/out via properties + signal; no Audio.qml reference inside (the
  panel wires it), keeping it mountable in Track C.
- **`OutputDeviceList.qml`** — radio rows from `Audio.sinks`; emits
  `selected(node)`; no Audio.qml reference inside.

Changed files:

- **`Island.qml`** — new `flashing` state driven by a restartable 1000 ms
  `Timer`; morph priority `expanded > flashing > peeked > pill`;
  `showPeek` becomes `peeked && !expanded && !flashing`. Flash geometry:
  capsule ~340×46, radius 23 (height/2 — capsule like the pill, not the
  panel's 18). Loader switch gains `"volume" → volumePanel`. Wheel handler
  on the pill/peek MouseArea: `Audio.step(±1)` + `flash()`. Public
  `flash()` function restarts the timer.
- **`shell.qml`** — three new `GlobalShortcut`s: `volumeUp`, `volumeDown`,
  `volumeMute` → `Audio.step(+1)/step(-1)/toggleMute()` + `island.flash()`.
  Existing `volume` shortcut → `island.toggle("volume")` (wiring already
  stubbed). `IpcHandler` gains matching methods for scripted verification.
- **`binds.lua`** — F10/F11/F12 (`locked`, `repeating`) →
  `hl.dsp.global("quickshell:volumeMute/Down/Up")`; XF86Audio trio rewired
  from `wpctl` execs to the same globals (aliases); `SUPER+V` →
  `global quickshell:volume`; **XF86AudioMicMute keeps its wpctl exec**.
- **`quickshell.nix`** — `services.swayosd.enable` removed.
- **`matugen/config.toml`** — `[templates.swayosd]` block removed;
  `templates/swayosd.css.template` deleted.
- **`scripts/matugen-reload.sh`** — the swayosd `try-restart` line
  (`matugen-reload.sh:16`) dropped.
- **Master plan** — step 9/12 lines and the swayosd-era audio-path sections
  rewritten (done in this commit; see plan file history).

## Interaction

- **Keys:** F10 mute-toggles, F11/F12 step ∓5%. Each press flashes. F12
  while muted unmutes (then raises). Hold-to-ramp relies on Hyprland
  `repeating` re-firing the `global` dispatcher — **impl-time verify #1**;
  fallback: `GlobalShortcut.onPressed/onReleased` + 150 ms ramp Timer in
  the shell.
- **Flash:** appears on key/wheel volume changes only — external changes
  (another app moving the sink volume) update bindings silently, no flash.
  Restartable 1000 ms Timer; repeated presses hold the flash open.
  **Suppressed while expanded** (panel already shows the change live).
  Display-only: no input mask surface area beyond the pill's — clicks pass
  through as today; hover during flash does not peek (`&& !flashing`);
  when the timer expires with the pointer on the island it settles into
  peek naturally.
- **Panel:** SUPER+V toggles. Slider drags and wheels ±5%; drag up unmutes.
  Mute toggle button reflects + flips `Audio.muted`. Device radio rows show
  all sinks with the default checked; click switches the default sink —
  via `Pipewire.preferredDefaultAudioSink` (**impl-time verify #2**;
  fallback `wpctl set-default <node.id>` via Quickshell `Process` — the
  one permitted external call if the QML API is missing in 0.3.0).
  ESC / click-outside collapse via existing patterns; no second focus-grab
  surface (peek invariant untouched).
- **Wheel on pill/peek:** ±5% + flash, no click needed.

## Visuals (Material tokens)

- Flash: chrome inherited from `islandRect` (surface_container, 1 px
  primary border). Glyph in `Theme.primary` (muted: `on_surface_variant`),
  track = 4 px rounded rect — fill `Theme.primary` over
  `Theme.surface_container_highest` remainder; percentage in
  `Theme.on_surface`, tabular numerals.
- Panel slider: same track vocabulary + 14 px knob (`Theme.primary`,
  subtle scale-pop on drag like the launcher's tile pop).
- Mute toggle: icon button; active-mute state tints `Theme.primary`
  container like the launcher's selected-row inversion.
- Device rows: radio dot + device description, row height 44, selected row
  `on_primary`-on-`primary` accent consistent with the launcher.

## Values (audit on 5120×1440; single-number tunes expected)

| Value | Initial |
|---|---|
| Flash size / radius | ~340 × 46 / 23 |
| Flash: glyph / track / % font | 18 px / 4×200 px / 14 px |
| Flash timer | 1000 ms restartable |
| Volume step / clamp | 5% / 0–100% |
| Panel width | 420 |
| Slider track / knob | 4 px / 14 px |
| Device row height / font | 44 / 14 px |
| Panel max height | slider+mute row 56 + N×44 device rows + margins (N = sink count, typically 2–3 ⇒ ~200; ≪ 640 strip budget) |

## Verification (Claude self-drives before requesting rb)

1. **Impl-verify #1 (hold-to-repeat):** `hyprctl dispatch` the global
   repeatedly / hold F12 after reload → `wpctl get-volume` deltas confirm
   ramp. If `repeating` doesn't re-fire `global`, switch to the
   onPressed/onReleased fallback *before* building further.
2. **Impl-verify #2 (default-sink API):** probe
   `Pipewire.preferredDefaultAudioSink` in 0.3.0 (qs log on assignment);
   fall back to `wpctl set-default`.
3. Flash: `hyprctl dispatch 'hl.dsp.global("quickshell:volumeUp")'` (or
   `qs ipc`) → grim shows flash capsule, `wpctl get-volume` +5%; second
   grim after 1.2 s shows pill restored.
4. Mute: volumeMute → `wpctl get-mute` flips, grim shows muted glyph;
   volumeUp while muted → unmuted + raised.
5. Panel: `quickshell:volume` → grim shows slider/mute/device rows;
   device click → `wpctl status` default sink moved; volumeUp while
   expanded → **no flash**, slider visibly moved (grim).
6. Peek suppression: cursor-move onto pill mid-flash → no peek until
   timer expiry (grim pair).
7. swayosd gone: repo grep clean (except historical plan lines);
   `nix flake check` passes.
8. After jftx rb + reload: F10–F12 live keys, hold-ramp feel, wheel on
   pill, device switch mid-playback, `systemctl --user status swayosd`
   reports no unit; stale `~/.config/swayosd/style.css` may remain on disk
   (orphaned output, harmless — rm at will).

## Out of scope

Mic controls beyond the existing wpctl bind, per-app volume mixer and
media controls (Track C control center), input-device selection,
click-on-flash to open the panel, brightness (desktop, no backlight),
capslock OSD (swayosd's other trick — dropped without replacement;
revisit in Track C only if missed).
