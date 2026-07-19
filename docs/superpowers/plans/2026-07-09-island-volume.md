# Island Volume Implementation Plan (Track B step 9)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Volume keys/wheel flash the island as a display-only OSD (replacing swayosd entirely), and SUPER+V morphs it into an output-volume panel (slider, mute, device radio rows).

**Architecture:** A new `Audio.qml` singleton is the shell's only PipeWire writer; every UI surface reads its state and calls its functions. The island gains a 4th display-only morph state (`flashing`, restartable 1000 ms) with priority `expanded > flashing > peeked > pill`. `VolumePanel.qml` fills the existing Loader switch; `VolumeSlider.qml`/`OutputDeviceList.qml` stay Audio-free (property in / signal out) so the Track C control center can remount them unchanged.

**Tech Stack:** Quickshell 0.3.0 QML (`Quickshell.Services.Pipewire`, GlobalShortcut, IpcHandler), Hyprland Lua binds, Nix (swayosd removal).

**Spec:** `docs/superpowers/specs/2026-07-09-island-volume-design.md` — read it first; it holds the approved UX decisions and the values table.

**Plan-time facts (already verified, no impl-verify needed):**
- `Pipewire.preferredDefaultAudioSink` EXISTS in the installed 0.3.0 (grepped `quickshell-service-pipewire.qmltypes` in the nix store on 2026-07-09) — the `wpctl set-default` fallback from the spec is dead, don't build it. Also confirmed present: `PwNode.{audio,isSink,isStream,description,nickname,name,id,ready}`, `PwNodeAudio.{volume,muted}`, `PwObjectTracker.objects`, `Pipewire.{nodes,defaultAudioSink}`.
- `binds.lua` has NO existing F10/F11/F12 binds (free), `ALT+V` is taken (window float) but the spec's `SUPER+V` is free.
- The only remaining impl-verify is **hold-to-repeat** (does `repeating = true` re-fire `hl.dsp.global` while a key is held?) — it needs a physical key hold, so it lands in Task 4's jftx live test, with a two-tier fallback spelled out there.

## Global Constraints

- **Never run two quickshell instances** (duplicate GlobalShortcut appid:name can crash). Safe restart, exactly this recipe (`pkill -f` matches your own shell — never use it):
  ```bash
  qs kill -c island
  for i in $(seq 1 20); do pgrep -f '[b]in/quickshell -c island' >/dev/null || break; sleep 0.2; done
  WAYLAND_DISPLAY=wayland-1 qs -c island -d -n
  ```
  Capture the "Saving logs to <path>" line — grep that file for `WARN`/`ERROR` after every restart.
- Quickshell does **not** hot-reload QML: restart (recipe above) after every QML edit. No `rb` is needed for QML edits (the config dir is an out-of-store symlink); only Task 4's nix/Lua changes need jftx to run `rb` (his alias already includes `hyprctl reload`).
- **jftx runs every `rb` himself** — stop and ask, wait for pasted output. Claude may run `nix flake check` and `nixos-rebuild build` freely.
- **`Audio.qml` is the only PipeWire writer.** No `wpctl` calls from QML, no direct `sink.audio.*` writes outside `Audio.qml`.
- Theme tokens are snake_case (`Theme.on_surface`); fonts only via `Theme.fontFamily` / `Theme.iconFontFamily`. `import qs.theme` resolves the singleton. Files in `island/` see each other (and the `Audio` singleton) without an import; if a restart logs "Audio is not defined", add `import qs.island` to the referencing file and restart again.
- Screenshots: `WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" <scratchpad>/<name>.png` covers the island area (top-center of the 5120×1440 display). Cursor moves: `hyprctl dispatch 'hl.dsp.cursor.move({ x = X, y = Y })'` (jftx's real mouse can fight scripted moves — retry once).
- **Volume etiquette:** record `wpctl get-volume @DEFAULT_AUDIO_SINK@` before each verification block and restore it (`wpctl set-volume @DEFAULT_AUDIO_SINK@ <v>`) after. Never leave the default sink switched to a different device.
- Do not add windows or focus grabs: the single `HyprlandFocusGrab` in `Island.qml` must stay the only grab surface (step-7.5 `onCleared` invariant).
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Audio.qml singleton + IPC volume hooks

**Files:**
- Create: `modules/home/desktop/quickshell/island/Audio.qml`
- Modify: `modules/home/desktop/quickshell/shell.qml` (IpcHandler block, currently lines 33–47)

**Interfaces:**
- Consumes: `Quickshell.Services.Pipewire` (verified API above).
- Produces (used by Tasks 2–3):
  - Singleton `Audio` with: `sink: PwNode?`, `ready: bool`, `volume: real (0–1)`, `muted: bool`, `sinks: list of PwNode`, `setVolume(v: real)`, `step(dir: int)` (±5%; `dir > 0` unmutes), `toggleMute()`, `setSink(node)`.
  - IPC (scripted verification): `qs -c island ipc call island volumeUp|volumeDown|volumeMute` — Task 2 appends `island.flash()` to these same functions.

- [ ] **Step 1: Create Audio.qml**

Create `modules/home/desktop/quickshell/island/Audio.qml`:

```qml
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// The shell's single PipeWire writer. Every volume/mute/device change
// routes through here; UI components only read state and call these
// functions. Null-safe throughout: the default sink can be absent at
// startup or vanish on device removal.
// Spec: docs/superpowers/specs/2026-07-09-island-volume-design.md
Singleton {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.ready && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : false

    // Hardware outputs for the device list (sink nodes, not app streams).
    readonly property var sinks: [...Pipewire.nodes.values]
        .filter(n => n.isSink && !n.isStream)

    // Bind the sinks so their audio properties are live.
    PwObjectTracker {
        objects: root.sinks
    }

    // One unmute rule (spec): raising the volume unmutes — shared by
    // F12/wheel-up (step) and slider drags (setVolume).
    function setVolume(v: real): void {
        if (!ready)
            return;
        const clamped = Math.max(0, Math.min(1, v));
        if (clamped > sink.audio.volume)
            sink.audio.muted = false;
        sink.audio.volume = clamped;
    }

    function step(dir: int): void {
        if (!ready)
            return;
        // Explicit unmute here too: at 100% a further F12 raises nothing,
        // but must still unmute.
        if (dir > 0 && sink.audio.muted)
            sink.audio.muted = false;
        setVolume(volume + dir * 0.05);
    }

    function toggleMute(): void {
        if (!ready)
            return;
        sink.audio.muted = !sink.audio.muted;
    }

    // Untyped param on purpose: PwNode annotations are not worth the
    // qmlcachegen risk; callers only ever pass nodes from `sinks`.
    function setSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }
}
```

- [ ] **Step 2: Add IPC volume functions**

In `modules/home/desktop/quickshell/shell.qml`, inside the `IpcHandler { target: "island" }` block, add after the `search(text)` function:

```qml
        function volumeUp(): void {
            Audio.step(1);
        }

        function volumeDown(): void {
            Audio.step(-1);
        }

        function volumeMute(): void {
            Audio.toggleMute();
        }
```

(`Audio` resolves via the existing `import qs.island`.)

- [ ] **Step 3: Restart quickshell and check the log**

Run the safe-restart recipe (Global Constraints). Then:

```bash
grep -iE "warn|error" <logfile> | grep -v "libpng" | head
```

Expected: no QML errors referencing Audio.qml or shell.qml. (If `Singleton` complains about the `PwObjectTracker` child, wrap it: some Quickshell versions want non-visual children under `Item {}` — but Theme.qml already parents `FileView` directly under `Singleton`, so this should just work.)

- [ ] **Step 4: Verify writes end-to-end via wpctl**

```bash
V0=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')   # save
wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5                        # deterministic base (V0 could be at the 1.0 clamp)
qs -c island ipc call island volumeUp
wpctl get-volume @DEFAULT_AUDIO_SINK@                             # expect 0.55
qs -c island ipc call island volumeDown
wpctl get-volume @DEFAULT_AUDIO_SINK@                             # expect 0.50
qs -c island ipc call island volumeMute
wpctl get-volume @DEFAULT_AUDIO_SINK@                             # expect "Volume: 0.50 [MUTED]"
qs -c island ipc call island volumeUp
wpctl get-volume @DEFAULT_AUDIO_SINK@                             # expect 0.55, NO [MUTED] (up unmutes)
wpctl set-volume @DEFAULT_AUDIO_SINK@ "$V0"                       # restore
```

Expected: each line matches its comment. If volume doesn't move, check the log for a Pipewire service warning before touching code.

- [ ] **Step 5: Commit**

```bash
git add modules/home/desktop/quickshell/island/Audio.qml modules/home/desktop/quickshell/shell.qml
git commit -m "feature: Audio singleton — the island's single PipeWire writer

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Flash morph state + VolumeFlash.qml + GlobalShortcuts + wheel

**Files:**
- Create: `modules/home/desktop/quickshell/island/VolumeFlash.qml`
- Modify: `modules/home/desktop/quickshell/island/Island.qml` (state block ~lines 16–38, `mask` ~line 54, `islandRect` width/height ~lines 92–97, `Pill` opacity ~line 149, new child + new WheelHandler)
- Modify: `modules/home/desktop/quickshell/shell.qml` (GlobalShortcuts + IPC functions from Task 1)

**Interfaces:**
- Consumes: `Audio.step(dir)`, `Audio.volume`, `Audio.muted` (Task 1).
- Produces:
  - `Island.flash()` — shows the flash for 1000 ms (restartable), no-op while expanded.
  - `Island.flashing: bool` — read by Task 3's verification only.
  - GlobalShortcuts `volumeUp`/`volumeDown`/`volumeMute` (Task 4 binds them).

- [ ] **Step 1: Create VolumeFlash.qml**

Create `modules/home/desktop/quickshell/island/VolumeFlash.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import qs.theme

// Display-only volume OSD content (the island's flash morph state).
// No input handlers — the flash never takes clicks or keys; Island.qml
// keeps the input mask pill-sized while it shows.
// Spec: docs/superpowers/specs/2026-07-09-island-volume-design.md
Item {
    id: root

    implicitWidth: 340
    implicitHeight: 46

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 14

        Text {
            // nf-fa-volume_up / nf-fa-volume_off
            text: Audio.muted ? "\uf026" : "\uf028"
            color: Audio.muted ? Theme.on_surface_variant : Theme.primary
            font.family: Theme.iconFontFamily
            font.pixelSize: 18
            // The two glyphs differ in advance width; fix the cell so the
            // track doesn't shift when mute toggles mid-flash.
            Layout.preferredWidth: 24
        }

        // Slim track, the panel slider's visual vocabulary (spec).
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 4
            radius: 2
            color: Theme.surface_container_highest

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * Audio.volume
                height: parent.height
                radius: 2
                color: Theme.primary
                opacity: Audio.muted ? 0.35 : 1

                Behavior on width {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Text {
            text: Math.round(Audio.volume * 100) + "%"
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 14
            horizontalAlignment: Text.AlignRight
            // Fixed cell: "5%" vs "100%" must not resize the track.
            Layout.preferredWidth: 40
        }
    }
}
```

- [ ] **Step 2: Add the flash state to Island.qml**

In `modules/home/desktop/quickshell/island/Island.qml`:

**(a)** Below the `search(text)` function, add:

```qml
    // Flash: display-only volume OSD, the 4th morph state (priority:
    // expanded > flashing > peeked > pill). Restartable so key repeats
    // hold it open; suppressed while expanded — the panel already shows
    // the change live.
    property bool flashing: false

    function flash(): void {
        if (expanded)
            return;
        flashing = true;
        flashOut.restart();
    }

    onExpandedChanged: {
        if (expanded) {
            flashOut.stop();
            flashing = false;
        }
    }
```

**(b)** Change the `showPeek` line (currently `readonly property bool showPeek: peeked && !expanded`) to:

```qml
    readonly property bool showPeek: peeked && !expanded && !flashing
```

**(c)** Next to the `peekIn`/`peekOut` Timers, add:

```qml
    Timer {
        id: flashOut

        interval: 1000
        onTriggered: root.flashing = false
    }
```

**(d)** Change the `mask` block (currently `mask: Region { item: islandRect }`) to:

```qml
    // While flashing, the input region stays pill-sized: clicks in the
    // flash's extra width pass through to windows below (spec).
    mask: Region {
        item: root.flashing ? pill : islandRect
    }
```

**(e)** In `islandRect`, extend the `width`/`height` chains (flash slots between expanded and peek):

```qml
        width: root.expanded ? expandedContent.implicitWidth
             : root.flashing ? flashView.implicitWidth
             : root.showPeek ? peekView.implicitWidth
             : pill.implicitWidth + 2 * pillHPad
        height: root.expanded ? expandedContent.implicitHeight
              : root.flashing ? flashView.implicitHeight
              : root.showPeek ? peekView.implicitHeight
              : pillHeight
```

The `radius` line needs **no change**: the flash is pill-height (46), so the existing `pillHeight / 2` capsule branch already yields the spec's radius 23.

**(f)** In the `Pill` child, change the opacity line to:

```qml
            opacity: root.expanded || root.showPeek || root.flashing ? 0 : 1
```

**(g)** After the `PeekView` child, add:

```qml
        VolumeFlash {
            id: flashView

            anchors.centerIn: parent
            opacity: root.flashing ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }
```

**(h)** Next to the `HoverHandler` in `islandRect`, add the wheel path (pill, peek, and flash states; the panel has its own slider wheel):

```qml
        WheelHandler {
            // target: null — a WheelHandler's default target is its
            // parent, which it would try to transform.
            target: null
            enabled: !root.expanded
            onWheel: event => {
                Audio.step(event.angleDelta.y > 0 ? 1 : -1);
                root.flash();
            }
        }
```

- [ ] **Step 3: Wire GlobalShortcuts and flash into shell.qml**

In `modules/home/desktop/quickshell/shell.qml`:

**(a)** After the `GlobalShortcut { name: "wallpapers" … }` block, add:

```qml
    GlobalShortcut {
        name: "volumeUp"
        description: "Raise volume 5% (island flash)"
        onPressed: {
            Audio.step(1);
            island.flash();
        }
    }

    GlobalShortcut {
        name: "volumeDown"
        description: "Lower volume 5% (island flash)"
        onPressed: {
            Audio.step(-1);
            island.flash();
        }
    }

    GlobalShortcut {
        name: "volumeMute"
        description: "Toggle mute (island flash)"
        onPressed: {
            Audio.toggleMute();
            island.flash();
        }
    }
```

**(b)** In the IpcHandler, append `island.flash();` to each Task 1 function so scripted calls exercise the same path as keys:

```qml
        function volumeUp(): void {
            Audio.step(1);
            island.flash();
        }

        function volumeDown(): void {
            Audio.step(-1);
            island.flash();
        }

        function volumeMute(): void {
            Audio.toggleMute();
            island.flash();
        }
```

- [ ] **Step 4: Restart quickshell and check the log**

Safe-restart recipe; grep the new log for `warn|error` (expected: none for our files — a `Region` binding warning here would mean the conditional mask item needs the fallback: keep `item: islandRect` unconditionally and note the 1 s click-swallow as accepted).

- [ ] **Step 5: Verify flash lifecycle via IPC + grim**

```bash
SP=<scratchpad>; export WAYLAND_DISPLAY=wayland-1
V0=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
qs -c island ipc call island volumeUp && sleep 0.45
grim -g "2100,0 920x700" $SP/f-flash.png
sleep 1.2
grim -g "2100,0 920x700" $SP/f-expired.png
qs -c island ipc call island volumeMute && sleep 0.45
grim -g "2100,0 920x700" $SP/f-muted.png
sleep 1.2
qs -c island ipc call island volumeMute && sleep 1.4   # unmute, let flash die
qs -c island ipc call island toggle volume && sleep 0.6
qs -c island ipc call island volumeUp && sleep 0.45
grim -g "2100,0 920x700" $SP/f-suppressed.png
qs -c island ipc call island collapse
wpctl set-volume @DEFAULT_AUDIO_SINK@ "$V0"
```

Read each PNG. Expected: `f-flash` = wide capsule (~340), volume glyph + slim track with primary fill + percentage, no clock; `f-expired` = clock pill restored; `f-muted` = muted glyph (volume-off \uf026, dimmed color) + dimmed track fill; `f-suppressed` = the **placeholder panel** (Task 3 replaces it) with NO flash capsule — the island must still show the expanded state. Also confirm `wpctl get-volume` moved ±5% at each step.

- [ ] **Step 6: Verify peek suppression during flash**

```bash
hyprctl dispatch 'hl.dsp.cursor.move({ x = 2560, y = 40 })' && sleep 0.4   # hover the pill
qs -c island ipc call island volumeUp && sleep 0.45
grim -g "2100,0 920x700" $SP/f-hover-flash.png                             # flash, NOT peek
sleep 1.3
grim -g "2100,0 920x700" $SP/f-hover-after.png                             # peek settles in
hyprctl dispatch 'hl.dsp.cursor.move({ x = 2560, y = 900 })'               # leave
wpctl set-volume @DEFAULT_AUDIO_SINK@ "$V0"
```

Expected: `f-hover-flash` shows the flash capsule (track + %), not the peek (clock+date/album art); `f-hover-after` shows the peek (pointer still hovering after expiry). If the mouse fought the scripted move, retry once.

- [ ] **Step 7: Commit**

```bash
git add modules/home/desktop/quickshell/island/VolumeFlash.qml modules/home/desktop/quickshell/island/Island.qml modules/home/desktop/quickshell/shell.qml
git commit -m "feature: island volume flash OSD (4th morph state) + wheel on pill

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Volume panel — slider, mute, device rows + Loader case

**Files:**
- Create: `modules/home/desktop/quickshell/island/VolumeSlider.qml`
- Create: `modules/home/desktop/quickshell/island/OutputDeviceList.qml`
- Create: `modules/home/desktop/quickshell/island/VolumePanel.qml`
- Modify: `modules/home/desktop/quickshell/island/Island.qml` (Loader `sourceComponent` switch ~line 184, new Component)
- Modify: `modules/home/desktop/quickshell/shell.qml` (IpcHandler: `setSink` verification hook)

**Interfaces:**
- Consumes: `Audio.{volume,muted,sink,sinks,setVolume,toggleMute,setSink}` (Task 1); Loader pattern + `root.collapse()` (existing).
- Produces:
  - `VolumeSlider { property real value; signal moved(real newValue) }` — **Audio-free**, remountable by Track C.
  - `OutputDeviceList { property var devices; property var current; signal selected(var node) }` — **Audio-free**, remountable by Track C.
  - `VolumePanel { signal dismissRequested() }` — the only place Audio is wired to the two components.
  - IPC: `qs -c island ipc call island setSink <id>` (scripted device-switch verification).

- [ ] **Step 1: Create VolumeSlider.qml**

Create `modules/home/desktop/quickshell/island/VolumeSlider.qml`:

```qml
import QtQuick
import qs.theme

// Thin-track slider (flash-matched vocabulary: 4 px track, small knob).
// Deliberately Audio-free — value in via property, changes out via
// moved() — so the Track C control center can remount it unchanged.
Item {
    id: root

    property real value: 0
    signal moved(real newValue)

    implicitHeight: 24

    function emitFromX(x: real): void {
        moved(Math.max(0, Math.min(1, x / track.width)));
    }

    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        height: 4
        radius: 2
        color: Theme.surface_container_highest

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * root.value
            height: parent.height
            radius: 2
            color: Theme.primary
        }
    }

    Rectangle {
        id: knob

        x: Math.max(0, Math.min(track.width - width, root.value * track.width - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        radius: 7
        color: Theme.primary
        scale: mouse.pressed ? 1.25 : 1

        Behavior on scale {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutBack
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        onPressed: event => root.emitFromX(event.x)
        onPositionChanged: event => {
            if (pressed)
                root.emitFromX(event.x);
        }
    }

    WheelHandler {
        target: null
        onWheel: event => root.moved(
            Math.max(0, Math.min(1, root.value + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
```

- [ ] **Step 2: Create OutputDeviceList.qml**

Create `modules/home/desktop/quickshell/island/OutputDeviceList.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import qs.theme

// Output-device radio rows. Deliberately Audio-free — devices/current in
// via properties, choice out via selected() — so the Track C control
// center can remount it unchanged.
Column {
    id: root

    property var devices: []
    property var current: null
    signal selected(var node)

    spacing: 2

    Repeater {
        model: root.devices

        delegate: Item {
            id: row

            required property var modelData
            readonly property bool isCurrent: root.current !== null
                && modelData.id === root.current.id

            width: root.width
            height: 44

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Theme.surface_container_high
                opacity: rowMouse.containsMouse && !row.isCurrent ? 0.4 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    radius: 9
                    color: "transparent"
                    border.width: 2
                    border.color: row.isCurrent ? Theme.primary : Theme.outline

                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.primary
                        visible: row.isCurrent
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: row.modelData.description || row.modelData.nickname || row.modelData.name
                    color: row.isCurrent ? Theme.primary : Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: row.isCurrent ? Font.Bold : Font.Medium
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }

            MouseArea {
                id: rowMouse

                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.selected(row.modelData)
            }
        }
    }
}
```

- [ ] **Step 3: Create VolumePanel.qml**

Create `modules/home/desktop/quickshell/island/VolumePanel.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import qs.theme

// Island volume expansion (output only, spec): slim slider + mute toggle
// + output-device radio rows. This panel is the only place Audio gets
// wired to the reusable components.
Item {
    id: root

    signal dismissRequested()

    implicitWidth: 420
    implicitHeight: content.implicitHeight + 32

    focus: true
    Keys.onEscapePressed: root.dismissRequested()

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            spacing: 14

            // Mute toggle: launcher-style inversion when active.
            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 12
                color: Audio.muted ? Theme.primary : Theme.surface_container_high

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: Audio.muted ? "\uf026" : "\uf028"
                    color: Audio.muted ? Theme.on_primary : Theme.on_surface
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 18
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Audio.toggleMute()
                }
            }

            VolumeSlider {
                Layout.fillWidth: true
                value: Audio.volume
                onMoved: newValue => Audio.setVolume(newValue)
            }

            Text {
                text: Math.round(Audio.volume * 100) + "%"
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 14
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: 40
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Qt.alpha(Theme.outline_variant, 0.5)
        }

        OutputDeviceList {
            Layout.fillWidth: true
            devices: Audio.sinks
            current: Audio.sink
            onSelected: node => Audio.setSink(node)
        }
    }
}
```

- [ ] **Step 4: Add the Loader case in Island.qml**

In `modules/home/desktop/quickshell/island/Island.qml`, change the Loader's `sourceComponent` chain to:

```qml
            sourceComponent: root.expandedFeature === "launcher" ? launcherPanel
                : root.expandedFeature === "volume" ? volumePanel
                : root.expanded ? placeholderPanel : null
```

and add next to the `launcherPanel` Component:

```qml
        Component {
            id: volumePanel

            VolumePanel {
                onDismissRequested: root.collapse()
            }
        }
```

- [ ] **Step 5: Add the setSink IPC hook**

In `modules/home/desktop/quickshell/shell.qml`, in the IpcHandler after `volumeMute()`:

```qml
        // Scripted device-switch verification: ids from `wpctl status`.
        function setSink(id: int): void {
            for (const node of Audio.sinks) {
                if (node.id === id) {
                    Audio.setSink(node);
                    return;
                }
            }
        }
```

- [ ] **Step 6: Restart quickshell, check log, verify panel**

Safe-restart recipe; grep the log (expected clean). Then:

```bash
SP=<scratchpad>; export WAYLAND_DISPLAY=wayland-1
V0=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
wpctl status | sed -n '/Sinks:/,/Sources:/p'                     # note sink ids + current default (*)
qs -c island ipc call island toggle volume && sleep 0.8
grim -g "2100,0 920x700" $SP/p-open.png
qs -c island ipc call island volumeUp && sleep 0.45
grim -g "2100,0 920x700" $SP/p-up-expanded.png
qs -c island ipc call island setSink <other-sink-id> && sleep 0.5
grim -g "2100,0 920x700" $SP/p-switched.png
wpctl status | sed -n '/Sinks:/,/Sources:/p'                     # default (*) moved
qs -c island ipc call island setSink <original-sink-id>          # switch BACK
qs -c island ipc call island collapse && sleep 0.6
grim -g "2100,0 920x700" $SP/p-collapsed.png
wpctl set-volume @DEFAULT_AUDIO_SINK@ "$V0"
```

Read each PNG. Expected: `p-open` = panel morphed from the pill: mute tile + thin slider with knob + percentage on the top row, hairline, device rows below with the radio dot on the current default; `p-up-expanded` = NO flash capsule (suppression), slider fill/knob/percentage advanced by 5%; `p-switched` = radio dot moved to the other device AND `wpctl status` default marker moved; `p-collapsed` = clock pill. If the machine has only one sink, skip the switch pair and note it for jftx's live test (he has multiple outputs).

- [ ] **Step 7: Commit**

```bash
git add modules/home/desktop/quickshell/island/VolumeSlider.qml modules/home/desktop/quickshell/island/OutputDeviceList.qml modules/home/desktop/quickshell/island/VolumePanel.qml modules/home/desktop/quickshell/island/Island.qml modules/home/desktop/quickshell/shell.qml
git commit -m "feature: island volume panel (slider, mute, output devices)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Binds + swayosd removal + rb gate + live test

**Files:**
- Modify: `modules/home/desktop/hypr/modules/binds.lua:68-88` (volume key block)
- Modify: `modules/home/desktop/quickshell.nix:19-21` (drop swayosd)
- Modify: `modules/home/programs/matugen/config.toml:44-46` (drop swayosd template block)
- Delete: `modules/home/programs/matugen/templates/swayosd.css.template`
- Modify: `modules/home/services/scripts/matugen-reload.sh:15-16` (drop swayosd restart)
- Modify: `docs/plans/quickshell-matugen-migration.md` (step-9 done marker)

**Interfaces:**
- Consumes: GlobalShortcuts `volumeUp`/`volumeDown`/`volumeMute`/`volume` in `shell.qml` (Tasks 2 + scaffold); `hl.dsp.global("quickshell:<name>")` — the Lua wrapper is verified live on this Hyprland 0.55.4 (step 8; raw `hyprctl dispatch global x` does NOT work on this Lua-native build).
- Produces: live F10/F11/F12 + XF86 aliases + SUPER+V; swayosd fully out of the system.

- [ ] **Step 1: Rewrite the volume key block in binds.lua**

In `modules/home/desktop/hypr/modules/binds.lua`, replace the block from the comment `-- Laptop multimedia keys for volume and LCD brightness` through the `XF86AudioMicMute` bind's closing `)` (lines 68–88) with:

```lua
-- Volume → island (Audio.qml is the PipeWire writer; the island flashes
-- as the OSD). jftx's board emits plain F10/F11/F12 — the XF86Audio
-- variants never fire here but stay as aliases for other keyboards.
hl.bind("F12", hl.dsp.global("quickshell:volumeUp"), { locked = true, repeating = true })
hl.bind("F11", hl.dsp.global("quickshell:volumeDown"), { locked = true, repeating = true })
hl.bind("F10", hl.dsp.global("quickshell:volumeMute"), { locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.global("quickshell:volumeUp"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.global("quickshell:volumeDown"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.global("quickshell:volumeMute"), { locked = true })
hl.bind(
	"XF86AudioMicMute",
	hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
	{ locked = true }
)
```

(Deliberate changes: mute binds lose `repeating` — a held mute key must not oscillate; MicMute keeps wpctl per spec. The `XF86MonBrightness*` lines that followed stay untouched.)

Then, in the `MY PROGRAMS`/keybind section after the `mainMod .. " + SPACE"` launcher bind (line 24), add:

```lua
hl.bind("SUPER + V", hl.dsp.global("quickshell:volume"))
```

(`ALT+V` is window-float; the spec and master plan put the panel on SUPER per the reference layout.)

- [ ] **Step 2: Remove swayosd from the nix config**

**(a)** `modules/home/desktop/quickshell.nix`: delete the trailing block (lines 19–21):

```nix
  # Volume/caps-lock OSD. Matugen writes ~/.config/swayosd/style.css,
  # which is swayosd-server's default stylesheet lookup path.
  services.swayosd.enable = true;
```

**(b)** `modules/home/programs/matugen/config.toml`: delete the block:

```toml
[templates.swayosd]
input_path = "templates/swayosd.css.template"
output_path = "~/.config/swayosd/style.css"
```

**(c)** Delete the template:

```bash
git rm modules/home/programs/matugen/templates/swayosd.css.template
```

**(d)** `modules/home/services/scripts/matugen-reload.sh`: delete both lines:

```bash
# SwayOSD: restarting the service is the only way to reload its CSS.
systemctl --user try-restart swayosd.service 2>/dev/null || true
```

- [ ] **Step 3: Validate**

```bash
cd ~/nixos && nix flake check
grep -rn swayosd modules/
```

Expected: flake check clean; the grep returns **nothing** (docs/ still mentions swayosd historically — that's fine, modules/ must be clean).

- [ ] **Step 4: Update the master plan doc**

In `docs/plans/quickshell-matugen-migration.md`, append to the end of the step-9 line (which already carries the 2026-07-09 spec revision): ` **✅ done 2026-07-09** (spec + plan in docs/superpowers/).`

- [ ] **Step 5: Commit**

```bash
git add modules/home/desktop/hypr/modules/binds.lua modules/home/desktop/quickshell.nix modules/home/programs/matugen/config.toml modules/home/services/scripts/matugen-reload.sh docs/plans/quickshell-matugen-migration.md
git commit -m "feature: volume keys + SUPER+V route to island; swayosd removed

F10/F11/F12 bound directly (this board emits plain keysyms; the old
XF86Audio binds never fired), XF86Audio kept as aliases. The island
flash replaces swayosd as the volume OSD: service, matugen template,
and reload hook all removed.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 6: STOP — request rb from jftx**

Ask jftx to run `rb` (his alias includes `hyprctl reload`) and paste the output. Do not proceed on errors. Home Manager will stop/remove the swayosd user service on activation; the stale generated `~/.config/swayosd/style.css` may remain on disk (orphaned output, harmless — rm at will).

- [ ] **Step 7: jftx live test (includes the one open impl-verify)**

jftx checks, in order:

1. **F12 tap** → island flashes (track + %), volume +5% audibly/wpctl.
2. **F12 HOLD** → volume ramps while held, flash stays open (restartable timer). **This is impl-verify #1**: does `repeating = true` re-fire the `global` dispatcher on key hold? If volume moves only once per press, see the fallback below.
3. **F11 tap/hold** symmetric; **F10** toggles mute (flash shows muted glyph); F12 while muted unmutes.
4. **Wheel on the pill/peek** → ±5% + flash. Wheel repeatedly — flash must not flicker between events.
5. **SUPER+V** → panel; slider drag (smooth, knob pop), mute tile, device radio switch mid-playback (audio jumps devices); ESC and click-outside collapse; volume keys while open move the slider with NO flash.
6. **ALT+W with the panel open** → wallpaper changes and the panel recolors live (master-plan step-9 verify; Theme bindings make this automatic — this just proves it).
7. `systemctl --user status swayosd` → `Unit swayosd.service could not be found.`

Claude confirms the binds registered: `hyprctl -j binds | grep -iE 'f1[012]|xf86audio' -A2 -B2` (expect `__lua` dispatcher entries), then pushes:

```bash
git push
```

**Fallback if F12-hold does not ramp (impl-verify #1 fails):**

- *Tier 1 (protocol path):* Hyprland may fire `released` on key-up even when `pressed` doesn't repeat. In `shell.qml`, give `volumeUp`/`volumeDown` a ramp timer:

  ```qml
  GlobalShortcut {
      name: "volumeUp"
      description: "Raise volume 5% (island flash)"
      onPressed: {
          Audio.step(1);
          island.flash();
          rampUp.start();
      }
      onReleased: rampUp.stop()
  }
  // next to the shortcuts:
  Timer {
      id: rampUp
      interval: 150
      repeat: true
      onTriggered: {
          Audio.step(1);
          island.flash();
      }
  }
  ```

  (mirror `rampDown` for volumeDown; binds.lua drops `repeating` from F11/F12 + aliases). **Verify `onReleased` actually fires** (log a step: hold, release, volume must STOP) — if release never arrives, the timer ramps forever: abort to Tier 2.
- *Tier 2 (guaranteed):* binds.lua uses the exec path with repeat — `hl.bind("F12", hl.dsp.exec_cmd("qs -c island ipc call island volumeUp"), { locked = true, repeating = true })` — exec repeating is proven (the old wpctl binds used it). Costs a process spawn per repeat tick; acceptable at keyboard repeat rate.
- Either fallback is a small follow-up commit: `fix: volume hold-to-ramp fallback (repeating × global)`.

---

## Self-review notes (already applied)

- Spec coverage: Audio singleton + one unmute rule (T1), flash state/geometry/mask/peek-gate/wheel (T2), panel + reusable slider/device-list + Loader case + setSink verification (T3), binds + aliases + MicMute untouched + swayosd removal + SUPER+V + rb gate + hold-to-ramp verify with two-tier fallback (T4). Values table honored: 340×46 flash, radius 23 (= pillHeight/2, no radius change needed), 1000 ms restartable, ±5%/clamp, 420 panel, 4 px track/14 px knob, 44 px device rows, 40-px %-cells.
- Plan-time verification retired spec impl-verify #2 (`preferredDefaultAudioSink` exists — grepped qmltypes); impl-verify #1 (hold-repeat) placed at the only point it can be tested (physical key, T4 step 7).
- Type consistency: `Audio.step(dir: int)` / `setVolume(v: real)` / `setSink(node)` / `sinks` used identically in T1 code, T2 shortcuts/IPC/wheel, T3 panel wiring and IPC `setSink(id)` lookup (`node.id === id`, `PwNode.id` verified in qmltypes). `island.flash()` produced in T2 (a), consumed by T2 (h)/shortcuts/IPC. `VolumeSlider.moved(real)` / `OutputDeviceList.selected(var)` match their T3 consumers.
- No placeholders: every QML/Lua/nix/bash block is complete and paste-ready; both fallback tiers include real code or an exact bind line.
