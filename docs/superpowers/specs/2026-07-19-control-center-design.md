# Island Control Center — Design (Track C v1)

**Date:** 2026-07-19 · **Status:** approved by jftx · **Master plan:** `docs/plans/quickshell-matugen-migration.md` §Track C · **Epic:** #7 · **Issue:** #13 · **Fixes:** #10

The control center is the island's single hub expansion, replacing the SUPER+V
slim volume panel. Track C is built **control-center-first**: instead of
standalone panels later composed into a hub, the hub lands first and every
future panel (network/BT device lists, calendar/weather, media card,
notification history) arrives as a **section PR** that slots into it. Motivations
(jftx): one bind to remember, and hard efficiency — nothing may run, poll, or
occupy memory while the control center is closed, preserving headroom for
gaming.

V1 ships the hub shell with three toggle tiles (Wi-Fi, Bluetooth, DND) and the
sound section (capsule slider + output-device rows), in macOS Control Center
visual language themed by matugen.

## Decisions (jftx, 2026-07-19)

| Question | Decision |
|---|---|
| Build order | **Control-center-first.** Standalone Track C panels become CC sections, one PR each. |
| V1 scope | Toggle tiles: **Wi-Fi, Bluetooth, DND** + volume slider + output-device rows. Night light deferred (no gamma tool installed on blackgarden; needs hyprsunset machinery first). |
| Entry | **SUPER+V opens the control center.** `VolumePanel.qml` deleted; GlobalShortcut renamed `volume` → `control`; `binds.lua` retargeted. Zero new binds. F10–F12 flash OSD, wheel-on-pill, XF86Audio aliases untouched. |
| Structure | **Vertical stack + inline expand.** Sections are Loader slots in a Column; a future tile tap expands its detail list inline in the same surface (mechanism specced, not built, in v1). |
| Visual | **macOS Control Center style**: grouped rounded cards (radius 16, `surface_container_high`) on the island surface; circular icon toggles (`primary` fill when active, like macOS's blue circles but wallpaper-themed); **fat capsule slider** (~36 px, speaker icon embedded in the filled end; icon click = mute). Supersedes the step-9 "slim slider" decision *for the panel context only* — the flash OSD keeps its slim track unchanged. |
| DND semantics | **Total silence** (gaming): while on, ALL notifications are dismissed immediately — critical does **not** bypass. Nothing queues; nothing is replayed on disable. Not persisted across restart (fresh boot = DND off). |
| Blur | Optional feel-tune at verification: Hyprland `layerrule` blur on the `quickshell-island` namespace + translucent surface colors. Affects the whole island (pill/toasts too); one-line revert if readability suffers. Not a blocking part of v1. |
| Resources | Everything mounts inside the existing `expandedContent` Loader — zero idle cost. **No timers, no polling anywhere in the CC.** Native `Quickshell.Networking`/`Quickshell.Bluetooth` are event-driven (NetworkManager/BlueZ D-Bus signals). |
| Issue #10 | Fixed here: during drag the slider owns its value (external `Audio.volume` re-binds suppressed until release), eliminating the coarse ~10-step round-trip. |
| Brightness | **Omitted entirely** — blackgarden is a desktop with no backlight; a DDC/ddcutil monitor-brightness section is a possible future PR, not planned. |

## Architecture

Files (flat in `modules/home/desktop/quickshell/island/`, per convention):

- **`ControlCenter.qml`** (new) — the expansion. ColumnLayout of cards:
  connectivity card (Wi-Fi + Bluetooth `ToggleTile` rows) beside a square DND
  card, then the full-width Sound card (capsule `VolumeSlider` +
  `OutputDeviceList`). The **only** place CC backends get wired (mirrors the
  deleted VolumePanel's role). Imports `Quickshell.Networking` /
  `Quickshell.Bluetooth` **here, not in shell.qml**, so nothing
  network/BT-related is created until the CC first opens (module singletons
  are lazy). Whether they tear down on collapse is impl-verified; worst case
  they persist afterward as idle event-driven D-Bus listeners — no polling,
  no repaints, effectively zero cost. Future sections append as Loader slots at
  the bottom of the Column; the section contract is: an item with
  `implicitWidth/Height`, themed from `qs.theme`, no timers while hidden.
- **`ToggleTile.qml`** (new, reusable) — circular icon button + label +
  status sub-label. Active = `primary` circle / `on_primary` icon; inactive =
  `surface_container_highest` circle / `on_surface` icon; disabled (adapter
  missing) = greyed, non-interactive. 200 ms color Behaviors, matching the
  mute button's existing inversion language.
- **`Island.qml`** (edit) — Loader switch gains `"control"` →
  `controlPanel`; `"volume"` entry and Component removed. New
  `property bool dnd: false`; `notify(n)` gains the gate: when `dnd` is true,
  `n.dismiss()` immediately — no toast, no pending slot, no tracking.
  The flash OSD is unaffected by DND.
- **`shell.qml`** (edit) — GlobalShortcut `volume` renamed `control`
  ("Toggle the island control center"). IPC: `toggle("control")` already
  works via the generic handler; add `dnd(on: bool)` + reading of
  `island.dnd` for scripted verification.
- **`VolumeSlider.qml`** (edit) — capsule restyle (thick rounded bar, fill =
  `primary`, embedded speaker glyph at the fill's left end; glyph click calls
  the existing mute path) + the #10 drag fix: an `interacting` state during
  which `value` binds to the drag position, not `Audio.volume`; on release the
  binding to `Audio.volume` restores. Continuous `onMoved` writes throughout
  the drag are kept. The unmute-on-increase rule stays in `Audio.qml`,
  untouched.
- **`OutputDeviceList.qml`** (edit, light) — radio rows restyled to sit
  inside the Sound card (row highlight radius, spacing); API unchanged.
- **`VolumePanel.qml`** (deleted).
- **`binds.lua`** (edit) — `SUPER+V` dispatcher retargets
  `global, quickshell:volume` → `global, quickshell:control`.

Backends:

- **Wi-Fi**: native Networking module; **impl-verify** the exact 0.3.0 API
  (module/singleton names, radio-enable property) with a probe before
  building, same protocol as step 9's Pipewire probe. Fallback if radio
  toggle is missing from the native API: one-shot `Process`
  running `nmcli radio wifi on|off`, state still read natively.
  Sub-label: connected SSID, else "Off"/"On".
- **Bluetooth**: native Bluetooth module, adapter `enabled`/powered
  property; fallback `bluetoothctl power on|off`. Sub-label "On"/"Off".
- **DND**: `island.dnd` bool only. No service, no persistence.
- **Audio**: existing `Audio.qml` singleton, unchanged — still the only
  PipeWire writer.

Layout (approved sketch):

```
┌────────────────────────────┐
│ ┌───────────────┐  ┌─────┐ │
│ │ (🛜) Wi-Fi Off │  │  ☾  │ │
│ │ (ᛒ) BT     On │  │ DND │ │
│ └───────────────┘  └─────┘ │
│ ┌────────────────────────┐ │
│ │ Sound                  │ │
│ │ ▐🔊━━━━━━●──────────▌  │ │
│ │ ◉ Speakers ○ Headset   │ │
│ └────────────────────────┘ │
└────────────────────────────┘
```

Sizing: panel ~440 wide (was 420), well inside the island's 1200×640 strip;
height from content. All sizes re-checked live on the 5120×1440 monitor.
Icon glyphs are nf codepoints — written as `\u` escapes in QML (Edit-transit
gotcha), python for glyph-adjacent edits.

## Behavior

- Wi-Fi tile toggles the radio (all Wi-Fi off/on, `nmcli radio` semantics);
  Bluetooth tile toggles adapter power; DND flips `island.dnd`. External
  changes (nmcli from a terminal, bluetoothctl) update tiles event-driven —
  no polling.
- Tiles reflect hardware truth: adapter absent/unavailable → tile disabled,
  never hidden (fixed layout).
- Escape, click-outside (focus grab), and SUPER+V re-press all collapse —
  inherited from the expansion system unchanged. The CC is the same single
  grabbing surface; the `HyprlandFocusGrab.onCleared` peek invariant is
  untouched.
- DND on: `notify()` dismisses everything immediately. DND off: normal toast
  flow resumes; nothing suppressed earlier replays.
- Slider: drag is smooth and continuous (#10 fixed); speaker-glyph click
  toggles mute; wheel on the slider ±5% (no flash while open) — unchanged
  from the old panel's behavior.
- Wallpaper change while open: cards recolor live (Theme.qml event-driven
  watch, existing behavior).

## Verification (scripted-first; jftx only for `rb` + feel checks)

1. `qs -c island ipc call island toggle control` + `grim -o DP-3` → cards
   render, colors match current palette.
2. Tile toggles via scripted cursor click (`hyprctl dispatch` cursor move +
   click): assert `nmcli radio wifi` / `bluetoothctl show | grep Powered`
   flips; screenshot tile state. External flip (`nmcli radio wifi off` in
   shell) → tile updates without reopen.
3. DND: `ipc call island dnd true` → `notify-send` normal AND
   `notify-send -u critical` → island stays pill (grim); `dnd false` → toast
   returns. Confirm nothing replays.
4. Slider: scripted press-drag across the capsule → `wpctl get-volume`
   moves smoothly (many distinct values, not ~10 steps); release; re-open
   CC → slider at correct position. jftx feel-check confirms #10 dead.
5. Regression: launcher (ALT+SPACE), wallpaper grid (ALT+SHIFT+W), F10–F12
   flash, wheel-on-pill, hover peek all intact; `quickshell:volume` shortcut
   gone, `quickshell:control` present (`hyprctl globalshortcuts`).
6. `nix flake check` + `trb` clean → jftx runs `rb`, pastes output →
   live SUPER+V, blur feel-tune decision, sizes on 5120×1440.

## Out of scope (future section PRs, epic #7)

Night light (needs hyprsunset first), network/BT device lists (first inline
expands), calendar + weather (fetch-on-open + TTL cache, never a poll timer),
media card (MPRIS) + gated visualizer (runs only while visible), notification
history, DND persistence, monitor brightness via DDC.
