# Island Hover Peek Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The collapsed island pill shows only the clock; hovering it morphs the island open into a display-only "peek" with now-playing (album art, title, artist), a large clock + date, and a slot reserved for Track C network status.

**Architecture:** Third state on the existing morph engine in `Island.qml` (pill / peek / expanded) driven by a debounced `HoverHandler`; a new `PeekView.qml` renders the peek content; `Pill.qml` loses its Mpris block. No focus grab, no keyboard focus, no new windows — the existing `islandRect` size/radius `Behavior`s carry the animation. Spec: `docs/superpowers/specs/2026-07-06-island-hover-peek-design.md`.

**Tech Stack:** Quickshell 0.3.0 QML (`Quickshell.Services.Mpris`, `Quickshell.Widgets.ClippingRectangle`, `SystemClock`), Hyprland 0.55 (`hyprctl dispatch movecursor`), grim for visual verification.

## Global Constraints

- Branch: `feat/quickshell-core` (Track B, issue #6). Small commits; every commit message ends with `Co-Authored-By:` the Claude line used by prior commits on this branch.
- **Never run `rb`/`nixos-rebuild switch`** (jftx-only) — and nothing in this plan needs it: the QML tree `modules/home/desktop/quickshell/` is materialized at `~/.config/quickshell/island` via an out-of-store **directory** symlink, so edits and *new files* appear immediately. No nix evaluation changes → `nix flake check` not required.
- **Quickshell 0.3.0 does NOT hot-reload QML.** After every QML edit, restart with exactly this sequence (never `pkill -f` — it matches your own shell; never two instances — duplicate GlobalShortcut appid:name can crash):

  ```bash
  export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-1
  export HYPRLAND_INSTANCE_SIGNATURE=$(ls -1t /run/user/1000/hypr | head -n1)
  qs kill -c island
  for i in $(seq 1 25); do pgrep -a quickshell | grep -q island || break; sleep 0.2; done
  qs -c island -d -n
  ```

  Expected tail: `INFO: Configuration Loaded` with **no QML error lines above it**. On errors, fix and repeat.
- Display: single output **DP-3, 5120×1440, scale 1**. Collapsed pill center ≈ **(2560, 40)** (top margin 15, pill height 46). "Away" point: **(2560, 720)**.
- **No test suite exists.** Verification is visual: `grim -g "<region>" <file>.png` then Read the PNG. `$SCRATCH` below means your session scratchpad directory.
- Locked values (already live, committed in `Island.qml`): `margins.top: 15`, exclusive-zone pad `+1`, debounce **150 ms in / 250 ms out**, morph 320 ms OutCubic (existing `Behavior`s, untouched).
- Theme singleton (`import qs.theme`) tokens used here — all verified present: `primary`, `on_surface`, `on_surface_variant`, `surface_container`, `surface_container_high`, `fontFamily`, `iconFontFamily`.
- `Island.qml` and `PeekView.qml` share the directory `modules/home/desktop/quickshell/island/`, so QML resolves `PeekView { }` without an import line.

---

### Task 1: PeekView + peek state machine

**Files:**
- Create: `modules/home/desktop/quickshell/island/PeekView.qml`
- Modify: `modules/home/desktop/quickshell/island/Island.qml`

**Interfaces:**
- Consumes: `Theme.*` tokens (singleton, `import qs.theme`); `MprisPlayer.trackTitle/trackArtist/trackArtUrl/playbackState`.
- Produces: `PeekView` item with content-driven `implicitWidth`/`implicitHeight` (Island reads both); `Island.qml` gains `property bool peeked` and `readonly property bool showPeek` (Task 2 relies on the peek existing so the pill can lose its Mpris block without losing the information).

- [ ] **Step 1: Create `PeekView.qml`** with exactly:

```qml
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.theme

// Hover peek content: now-playing block (only while something plays) +
// large clock/date. Display-only — no interaction, no focus. The row
// intentionally ends after the clock; Track C's network indicator takes
// the right slot (plan step-7 addendum).
Row {
    id: root

    // Same "first playing player" rule the pill used before the peek.
    readonly property var player: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing) ?? null
    readonly property string artUrl: root.player?.trackArtUrl ?? ""

    padding: 24
    spacing: 24

    ClippingRectangle {
        visible: root.player !== null
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 56
        implicitHeight: 56
        radius: 14
        color: Theme.surface_container_high

        Image {
            anchors.fill: parent
            visible: root.artUrl !== ""
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(112, 112)
            asynchronous: true
        }

        // No art URL from the player: music-note glyph instead.
        Text {
            visible: root.artUrl === ""
            anchors.centerIn: parent
            text: "" // nf-fa-music
            color: Theme.primary
            font.family: Theme.iconFontFamily
            font.pixelSize: 22
        }
    }

    Column {
        visible: root.player !== null
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Text {
            // implicitWidth is the full-text width, unaffected by
            // width/elide — caps the column without a binding loop.
            width: Math.min(implicitWidth, 340)
            elide: Text.ElideRight
            text: root.player?.trackTitle ?? ""
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }

        Text {
            width: Math.min(implicitWidth, 340)
            elide: Text.ElideRight
            text: root.player?.trackArtist ?? ""
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 15
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        SystemClock {
            id: clock

            precision: SystemClock.Minutes
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "hh:mm")
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 30
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "ddd, MMM d")
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 14
        }
    }
}
```

- [ ] **Step 2: Wire the peek state into `Island.qml`.** Four edits:

**(a)** Below the `collapse()` function, add the peek properties:

```qml
    // Hover peek: display-only third state (no focus grab, no keyboard).
    // Debounced so grazing the screen edge doesn't flicker the island.
    property bool peeked: false
    readonly property bool showPeek: peeked && !expanded
```

**(b)** After the `HyprlandFocusGrab { ... }` block, add the debounce timers:

```qml
    Timer {
        id: peekIn

        interval: 150
        onTriggered: root.peeked = true
    }

    Timer {
        id: peekOut

        interval: 250
        onTriggered: root.peeked = false
    }
```

**(c)** In `islandRect`, replace the two-way `width`/`height` ternaries with three-way ones, and add the `HoverHandler` as the rect's first child:

```qml
        width: root.expanded ? expandedContent.implicitWidth
             : root.showPeek ? peekView.implicitWidth
             : pill.implicitWidth + 2 * pillHPad
        height: root.expanded ? expandedContent.implicitHeight
              : root.showPeek ? peekView.implicitHeight
              : pillHeight
```

```qml
        HoverHandler {
            id: hover

            onHoveredChanged: {
                if (hovered) {
                    peekOut.stop();
                    peekIn.restart();
                } else {
                    peekIn.stop();
                    peekOut.restart();
                }
            }
        }
```

Leave `radius` alone — `root.expanded ? 24 : height / 2` already gives the peek its stadium shape. Leave `HyprlandFocusGrab`, `WlrLayershell.keyboardFocus`, and the mask alone — peek must never take focus.

**(d)** Change the `Pill` instance's opacity line from `opacity: root.expanded ? 0 : 1` to:

```qml
            opacity: root.expanded || root.showPeek ? 0 : 1
```

and insert the peek instance between the `Pill` and the placeholder `Item`:

```qml
        PeekView {
            id: peekView

            anchors.centerIn: parent
            opacity: root.showPeek ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }
```

- [ ] **Step 3: Restart quickshell** using the Global Constraints sequence. Expected: `Configuration Loaded`, no QML errors.

- [ ] **Step 4: Verify hover-in.**

```bash
hyprctl dispatch movecursor 2560 40
sleep 1
grim -g "2160,0 800x260" $SCRATCH/peek-open.png
```

Read the PNG. Expected: wide stadium (~104 px tall); if media is playing — album art (or glyph), title over artist, big clock over date; if idle — clock/date block alone, narrower stadium.

- [ ] **Step 5: Verify hover-out.**

```bash
hyprctl dispatch movecursor 2560 720
sleep 1
grim -g "2160,0 800x260" $SCRATCH/peek-closed.png
```

Read the PNG. Expected: collapsed pill again.

- [ ] **Step 6: Verify expansion beats peek.**

```bash
hyprctl dispatch movecursor 2560 40
sleep 1
qs -c island ipc call island toggle launcher
sleep 0.6
grim -g "2160,0 800x400" $SCRATCH/peek-vs-expanded.png
qs -c island ipc call island collapse
hyprctl dispatch movecursor 2560 720
```

Read the PNG. Expected: the placeholder panel (the word "launcher"), **not** the peek, even though the pointer sits on the island.

- [ ] **Step 7: Commit.**

```bash
git add modules/home/desktop/quickshell/island/PeekView.qml modules/home/desktop/quickshell/island/Island.qml
git commit -m "feature: island hover peek (third morph state)"
```

---

### Task 2: Pill slims to clock-only

**Files:**
- Modify: `modules/home/desktop/quickshell/island/Pill.qml`

**Interfaces:**
- Consumes: nothing from Task 1 code-wise, but MUST land after it (the peek is where now-playing lives from now on).
- Produces: `Pill` keeps its `implicitWidth`/`implicitHeight` contract with `Island.qml` — do not rename or restructure the root `Row`.

- [ ] **Step 1: Replace `Pill.qml`** with exactly:

```qml
import QtQuick
import Quickshell
import qs.theme

// Collapsed island content: clock only. Now-playing lives in the hover
// peek (PeekView.qml).
Row {
    id: root

    spacing: 14

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, "hh:mm")
        color: Theme.on_surface
        font.family: Theme.fontFamily
        font.pixelSize: 20
    }
}
```

(Removes: the `Quickshell.Services.Mpris` import, the `player` property, the icon `Text`, and the title `Text`. The pill no longer changes width with playback.)

- [ ] **Step 2: Restart quickshell** (Global Constraints sequence). Expected: `Configuration Loaded`, no QML errors.

- [ ] **Step 3: Verify.** With media playing (if none is, note it and verify clock-only rendering anyway):

```bash
hyprctl dispatch movecursor 2560 720
sleep 1
grim -g "2360,0 400x120" $SCRATCH/pill-slim.png
```

Read the PNG. Expected: pill shows the clock only — no music icon, no title — even while media plays.

- [ ] **Step 4: Commit.**

```bash
git add modules/home/desktop/quickshell/island/Pill.qml
git commit -m "feature: pill slims to clock-only (now-playing moved to peek)"
```

---

### Task 3: Full-pass verification + push

**Files:** none created/modified (verification only).

**Interfaces:**
- Consumes: everything from Tasks 1–2.
- Produces: pushed branch; jftx feel-test checklist.

- [ ] **Step 1: End-to-end sweep.** Repeat Task 1 Steps 4–6 once more from a cold pointer position (start at `2560 720`), confirming: pill → hover → peek (after ~150 ms), peek → away → pill (after ~250 ms + 320 ms morph), expansion-beats-peek, and that the pill did not regain the track title.

- [ ] **Step 2: Recolor sanity.** Colors are all `Theme.*` bindings, so this should be automatic; verify by either waiting for the 10-min wallpaper timer or noting it for jftx's feel-test rather than forcing a wallpaper change.

- [ ] **Step 3: Push.**

```bash
git push origin feat/quickshell-core
```

- [ ] **Step 4: Report for jftx's live feel-test** (Claude cannot judge motion from stills): morph smoothness pill↔peek, debounce timing (150/250 tunables in `Island.qml`'s `peekIn`/`peekOut`), peek sizes/fonts on the 5120×1440 panel, art rendering with a real Spotify track. Any tuning = one-number edits + qs restart.

---

## Self-review record (2026-07-07)

Spec coverage: state machine ✓ (Task 1 (a)–(c)), display-only guarantee ✓ (no focus-grab/keyboard edits), peek content incl. art fallback + reserved right slot ✓ (PeekView.qml), pill slim ✓ (Task 2), geometry ✓ (tuned values 15/+1 already committed pre-plan), animation reuse ✓ (no new Behaviors except peek opacity fade, mirroring pill's), verification ✓ (Tasks 1/3), plan-doc amendment ✓ (landed with the spec commit). No placeholders; names consistent (`peeked`/`showPeek`/`peekIn`/`peekOut`/`peekView` used identically across tasks).
