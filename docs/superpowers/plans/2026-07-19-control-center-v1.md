# Control Center v1 Implementation Plan (Track C, #13)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SUPER+V morphs the island into a macOS-style control center — Wi-Fi/Bluetooth/DND toggle tiles + a Sound card (capsule slider, output devices) — replacing the slim volume panel, with zero idle cost and the #10 slider-drag fix.

**Architecture:** `ControlCenter.qml` fills the island's existing expansion Loader under a new `"control"` feature name (the `"volume"` feature and `VolumePanel.qml` are deleted). It is the only place CC backends get wired: the native `Networking`/`Bluetooth` singletons (imported there, not `shell.qml`, so nothing is created until first open), the existing `Audio` singleton, and a new `island.dnd` bool whose gate in `notify()` implements total-silence DND. `ToggleTile.qml` is the reusable tile row; `VolumeSlider.qml` is restyled to a fat capsule and gains drag-ownership (#10).

**Tech Stack:** Quickshell 0.3.0 QML (`Quickshell.Networking`, `Quickshell.Bluetooth`, existing `Audio.qml`/Pipewire), Hyprland Lua binds, Nix flake validation.

**Spec:** `docs/superpowers/specs/2026-07-19-control-center-design.md` — read it first; it holds the approved UX decisions (macOS card language, DND total silence, no-polling rule).

**Plan-time facts (verified against the installed 0.3.0 qmltypes in the nix store, 2026-07-19 — no impl-verify needed):**
- `Networking` singleton (`Quickshell.Networking`): `wifiEnabled` is **read/write** (`write: "setWifiEnabled"`), notify `wifiEnabledChanged`; `devices` is an `UntypedObjectModel*` → use the `[...Networking.devices.values]` idiom (same as `Pipewire.nodes.values` in `Audio.qml`); `DeviceType` enum members are exactly `None`, `Wifi`, `Wired`; `WifiDevice.network` is a `Network*` with `.name` (the SSID), null when disconnected.
- `Bluetooth` singleton (`Quickshell.Bluetooth`): `defaultAdapter` is a nullable `BluetoothAdapter*`; `adapter.enabled` is **read/write** (`write: "setEnabled"`). **The spec's nmcli/bluetoothctl fallbacks are dead — do not build them.**
- `binds.lua` line 25 is the SUPER+V bind: `hl.bind("SUPER + V", hl.dsp.global("quickshell:volume"))`.
- Icon glyphs: the shell's existing glyphs use the BMP `\uf0xx` Font Awesome range of Iosevka Nerd Font (`\uf026`/`\uf028` in VolumePanel today). This plan uses BMP-only codepoints: Wi-Fi `\uf1eb`, Bluetooth `\uf293`, moon `\uf186` — always written as `\u` escapes in QML source, never literal glyphs (Edit-transit strips them).
- blackgarden hardware: Wi-Fi device `wlp7s0` exists (tile enabled), Bluetooth enabled in `modules/system/network.nix`.
- Remaining impl-verify (Task 1, step 1): the exact `qs -p` flag spelling for `ipc`/`kill` against a path-launched instance. Expected: `qs -p <path> ipc call island <fn>` and `qs kill -p <path>`; if `-p` is rejected there, fall back to `--path` (check `qs --help`).

## Global Constraints

- **Dev loop (post-systemd-flip — differs from every Track B plan):** `~/.config/quickshell/island` is now a **pure store path** and `quickshell.service` owns the single instance. QML iteration therefore runs a dev instance from the repo working tree, with the service stopped first (never two instances — duplicate GlobalShortcut appid:name can crash):
  ```bash
  QSP=~/nixos/modules/home/desktop/quickshell
  systemctl --user stop quickshell                       # island disappears — warn jftx FIRST
  WAYLAND_DISPLAY=wayland-1 qs -p "$QSP" -d -n           # capture the "Saving logs to <path>" line
  # after every QML edit (no hot reload):
  qs kill -p "$QSP"
  for i in $(seq 1 20); do pgrep -f '[b]in/quickshell' >/dev/null || break; sleep 0.2; done
  WAYLAND_DISPLAY=wayland-1 qs -p "$QSP" -d -n
  # IPC against the dev instance:
  qs -p "$QSP" ipc call island <fn> [args]
  # end of every work session (restores the OLD store-path shell — expected):
  qs kill -p "$QSP" && systemctl --user start quickshell
  ```
  Grep the captured log path for `WARN`/`ERROR` after every restart. Never `pkill -f quickshell` (matches your own shell). Hyprland keybinds may not route to the dev instance (appid drift) — all scripted verification goes through IPC; live binds are verified once, post-`rb`, in Task 4.
- **jftx runs every `rb` himself** — stop and ask, wait for pasted output. `nix flake check` and `nixos-rebuild build --flake ~/nixos#blackgarden --sudo` (trb) may be run freely. `git add` new files before `nix flake check` (untracked files are invisible to flake eval).
- **jftx is at the keyboard**: his clicks/keys land in focus-grabbed expansions. Batch probes into single tight bash calls and warn him before each dev-instance session or screenshot batch.
- **No timers, no polling, no new windows, no new focus grabs** anywhere in CC code. The single `HyprlandFocusGrab` in `Island.qml` stays the only grab surface (its `onCleared` peek invariant untouched). `Audio.qml` stays the only PipeWire writer; `ControlCenter.qml` is the only file that touches `Networking`/`Bluetooth`.
- Theme tokens are snake_case via `import qs.theme` (`Theme.surface_container_high`); fonts only `Theme.fontFamily` / `Theme.iconFontFamily`. Files in `island/` see each other and singletons without imports.
- Screenshots: `WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" <scratchpad>/<name>.png` (island area, top-center of 5120×1440). Cursor moves: `hyprctl dispatch 'hl.dsp.cursor.move({ x = X, y = Y })'` — jftx's real mouse can fight scripted moves, retry once. There is no scripted mouse-click/drag: write-path clicks (tiles, slider drags) are verified by jftx in Task 4's live checklist; scripted verification covers read paths (external state flips → UI updates) and IPC.
- **Volume etiquette:** record `wpctl get-volume @DEFAULT_AUDIO_SINK@` before each verification block, restore after. Never leave the default sink switched.
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: VolumeSlider capsule restyle + #10 drag fix

**Files:**
- Modify: `modules/home/desktop/quickshell/island/VolumeSlider.qml` (full rewrite, currently 74 lines)

**Interfaces:**
- Consumes: `qs.theme` only (stays Audio-free).
- Produces (used by Task 2's Sound card): `VolumeSlider` with properties `value: real (0–1)`, `muted: bool`, signals `moved(real newValue)`, `muteToggled()`, `implicitHeight: 36`. Existing consumers (`VolumePanel.qml`, until Task 2 deletes it) pass only `value`/`onMoved` — the new `muted`/`muteToggled` members are additive, so the old panel keeps working this task (its glyph just always shows the unmuted symbol; the panel's separate mute button still works).

- [ ] **Step 1: Verify the dev-loop flag spelling**

Run: `qs --help 2>&1 | grep -A2 '\-p' | head -6` and `qs kill --help 2>&1 | head -8`
Expected: `-p, --path` accepted by both. If not, substitute the spelling `--help` shows in every later command.

- [ ] **Step 2: Rewrite VolumeSlider.qml**

Replace the entire file with:

```qml
import QtQuick
import qs.theme

// macOS-style capsule slider: thick rounded track, primary fill, speaker
// glyph embedded in the fill's left end (click = mute). Deliberately
// Audio-free — value/muted in via properties, moved()/muteToggled() out —
// so any panel can mount it.
// While pressed the slider renders its own drag position and ignores
// external value re-binds: the value → PipeWire → value round trip lags
// ~0.5 s and quantized drags into ~10 coarse steps (#10).
Item {
    id: root

    property real value: 0
    property bool muted: false
    signal moved(real newValue)
    signal muteToggled()

    readonly property real shown: drag.pressed ? drag.dragValue : value

    implicitHeight: 36

    function valueAt(x: real): real {
        return Math.max(0, Math.min(1, x / width));
    }

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        color: Theme.surface_container_highest
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(track.height, track.width * root.shown)
            radius: track.radius
            color: Theme.primary
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 13
        anchors.verticalCenter: parent.verticalCenter
        text: root.muted ? "\uf026" : "\uf028"
        color: Theme.on_primary
        font.family: Theme.iconFontFamily
        font.pixelSize: 16
    }

    MouseArea {
        id: drag

        property real dragValue: 0

        anchors.fill: parent
        onPressed: event => {
            dragValue = root.valueAt(event.x);
            root.moved(dragValue);
        }
        onPositionChanged: event => {
            if (pressed) {
                dragValue = root.valueAt(event.x);
                root.moved(dragValue);
            }
        }
    }

    // On top of the drag area: the glyph zone eats its own clicks for
    // mute; drags simply start to its right.
    MouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 40
        onClicked: root.muteToggled()
    }

    WheelHandler {
        target: null
        onWheel: event => root.moved(
            Math.max(0, Math.min(1, root.value + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
```

- [ ] **Step 3: Verify against the still-existing volume panel (dev instance)**

Warn jftx, then:

```bash
QSP=~/nixos/modules/home/desktop/quickshell
SAVED=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
systemctl --user stop quickshell
WAYLAND_DISPLAY=wayland-1 qs -p "$QSP" -d -n
sleep 1
qs -p "$QSP" ipc call island toggle volume
sleep 0.6
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" /tmp/claude-1000/-home-jftx-nixos/a4e917d5-7e7b-4708-bd2d-43235c3f0e72/scratchpad/t1-capsule.png
qs -p "$QSP" ipc call island collapse
```

Read the screenshot. Expected: the panel shows a **36 px capsule** (fill = wallpaper primary, speaker glyph inside the fill's left end) instead of the old 4 px track + knob. Grep the dev log for `WARN|ERROR` — none related to VolumeSlider. Restore volume: `wpctl set-volume @DEFAULT_AUDIO_SINK@ ${SAVED##* }` (drag feel and mute-click are jftx's Task 4 checklist — no scripted clicks exist).

- [ ] **Step 4: Commit**

```bash
git add modules/home/desktop/quickshell/island/VolumeSlider.qml
git commit -m "feat(island): capsule volume slider with drag ownership (fixes #10)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: ToggleTile + ControlCenter + SUPER+V retarget

**Files:**
- Create: `modules/home/desktop/quickshell/island/ToggleTile.qml`
- Create: `modules/home/desktop/quickshell/island/ControlCenter.qml`
- Modify: `modules/home/desktop/quickshell/island/Island.qml` (property block ~line 41, Loader switch lines 357–360, Components lines 379–393)
- Modify: `modules/home/desktop/quickshell/shell.qml` (GlobalShortcut lines 21–25)
- Modify: `modules/home/desktop/quickshell/island/OutputDeviceList.qml` (line 33)
- Modify: `modules/home/desktop/hypr/modules/binds.lua` (line 25)
- Delete: `modules/home/desktop/quickshell/island/VolumePanel.qml`

**Interfaces:**
- Consumes: Task 1's `VolumeSlider` (`value`, `muted`, `moved(real)`, `muteToggled()`); existing `Audio` singleton (`volume`, `muted`, `sinks`, `sink`, `setVolume(v)`, `toggleMute()`, `setSink(node)`); existing `OutputDeviceList` (`devices`, `current`, `selected(node)`); native `Networking.wifiEnabled: bool (rw)`, `Networking.devices.values`, `DeviceType.Wifi`, `Bluetooth.defaultAdapter?.enabled: bool (rw)`.
- Produces (used by Task 3): `Island` property `dnd: bool` (default false), wired to the CC's DND card; feature name `"control"` in the Loader switch; GlobalShortcut name `control`.

- [ ] **Step 1: Create ToggleTile.qml**

```qml
import QtQuick
import QtQuick.Layouts
import qs.theme

// macOS-Control-Center row tile: circular icon button + label + status
// sub-label. Backend-free: state in via properties, intent out via
// toggled(). enabled=false greys the tile (absent adapter) but keeps the
// layout fixed.
Item {
    id: root

    property string icon: ""
    property string label: ""
    property string status: ""
    property bool active: false
    signal toggled()

    implicitHeight: 44
    opacity: enabled ? 1 : 0.4

    RowLayout {
        anchors.fill: parent
        spacing: 12

        Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            radius: 16
            color: root.active ? Theme.primary : Theme.surface_container_highest

            Behavior on color {
                ColorAnimation {
                    duration: 200
                }
            }

            Text {
                anchors.centerIn: parent
                text: root.icon
                color: root.active ? Theme.on_primary : Theme.on_surface
                font.family: Theme.iconFontFamily
                font.pixelSize: 15
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
                Layout.fillWidth: true
                text: root.label
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.status
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 11
                visible: text !== ""
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.enabled
        onClicked: root.toggled()
    }
}
```

- [ ] **Step 2: Create ControlCenter.qml**

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Bluetooth
import qs.theme

// Island control center: macOS-CC-style hub (spec 2026-07-19). The only
// place CC backends get wired: the Networking/Bluetooth singletons
// (imported here, not shell.qml, so nothing exists until first open),
// Audio, and the island's dnd flag. Future Track C sections append as
// cards below the Sound card. No timers, no polling — everything here is
// event-driven and dies with the expansion Loader.
Item {
    id: root

    property bool dnd: false
    signal dndToggled()
    signal dismissRequested()

    implicitWidth: 440
    implicitHeight: content.implicitHeight + 36

    focus: true
    Keys.onEscapePressed: root.dismissRequested()

    // First Wi-Fi-capable device; null on machines without one.
    readonly property var wifiDevice: [...Networking.devices.values]
        .find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var btAdapter: Bluetooth.defaultAdapter

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Connectivity card: Wi-Fi + Bluetooth rows.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: Theme.surface_container_high
                implicitHeight: connectivity.implicitHeight + 24

                ColumnLayout {
                    id: connectivity

                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 6

                    ToggleTile {
                        Layout.fillWidth: true
                        icon: "\uf1eb"
                        label: "Wi-Fi"
                        enabled: root.wifiDevice !== null
                        active: Networking.wifiEnabled
                        status: root.wifiDevice && root.wifiDevice.network
                            ? root.wifiDevice.network.name
                            : Networking.wifiEnabled ? "On" : "Off"
                        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                    }

                    ToggleTile {
                        Layout.fillWidth: true
                        icon: "\uf293"
                        label: "Bluetooth"
                        enabled: root.btAdapter !== null
                        active: root.btAdapter !== null && root.btAdapter.enabled
                        status: root.btAdapter === null ? "No adapter"
                            : root.btAdapter.enabled ? "On" : "Off"
                        onToggled: root.btAdapter.enabled = !root.btAdapter.enabled
                    }
                }
            }

            // DND card: square, moon icon, primary_container tint when on.
            Rectangle {
                Layout.preferredWidth: 96
                Layout.fillHeight: true
                radius: 16
                color: root.dnd ? Theme.primary_container : Theme.surface_container_high

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 32
                        height: 32
                        radius: 16
                        color: root.dnd ? Theme.primary : Theme.surface_container_highest

                        Behavior on color {
                            ColorAnimation {
                                duration: 200
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf186"
                            color: root.dnd ? Theme.on_primary : Theme.on_surface
                            font.family: Theme.iconFontFamily
                            font.pixelSize: 15
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "DND"
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.dndToggled()
                }
            }
        }

        // Sound card: capsule slider + output-device rows.
        Rectangle {
            Layout.fillWidth: true
            radius: 16
            color: Theme.surface_container_high
            implicitHeight: sound.implicitHeight + 24

            ColumnLayout {
                id: sound

                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Text {
                    text: "Sound"
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    VolumeSlider {
                        Layout.fillWidth: true
                        value: Audio.volume
                        muted: Audio.muted
                        onMoved: newValue => Audio.setVolume(newValue)
                        onMuteToggled: Audio.toggleMute()
                    }

                    Text {
                        Layout.preferredWidth: 36
                        text: Math.round(Audio.volume * 100) + "%"
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        horizontalAlignment: Text.AlignRight
                    }
                }

                OutputDeviceList {
                    Layout.fillWidth: true
                    devices: Audio.sinks
                    current: Audio.sink
                    onSelected: node => Audio.setSink(node)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Wire Island.qml**

Three edits:

(a) Below the `flashing` property block (after line ~48), add:

```qml
    // DND (spec 2026-07-19): total silence while on — the notify() gate
    // lands in Task 3. State is session-only; a fresh shell starts false.
    property bool dnd: false
```

(b) In the Loader `sourceComponent` switch, replace the line

```qml
                : root.expandedFeature === "volume" ? volumePanel
```

with

```qml
                : root.expandedFeature === "control" ? controlPanel
```

(c) Replace the whole `volumePanel` Component block

```qml
        Component {
            id: volumePanel

            VolumePanel {
                onDismissRequested: root.collapse()
            }
        }
```

with

```qml
        Component {
            id: controlPanel

            ControlCenter {
                dnd: root.dnd
                onDndToggled: root.dnd = !root.dnd
                onDismissRequested: root.collapse()
            }
        }
```

- [ ] **Step 4: Rename the GlobalShortcut in shell.qml**

Replace lines 21–25:

```qml
    GlobalShortcut {
        name: "control"
        description: "Toggle the island control center"
        onPressed: island.toggle("control")
    }
```

- [ ] **Step 5: Retarget binds.lua and delete VolumePanel**

`modules/home/desktop/hypr/modules/binds.lua` line 25 becomes:

```lua
hl.bind("SUPER + V", hl.dsp.global("quickshell:control"))
```

Then: `git rm modules/home/desktop/quickshell/island/VolumePanel.qml`

- [ ] **Step 6: OutputDeviceList hover fix**

Inside the new Sound card the row-hover fill equals the card background and would be invisible. `OutputDeviceList.qml` line 33:

```qml
                color: Theme.surface_container_highest
```

(was `Theme.surface_container_high`).

- [ ] **Step 7: Verify (dev instance)**

Warn jftx, then:

```bash
QSP=~/nixos/modules/home/desktop/quickshell
qs kill -p "$QSP" 2>/dev/null
for i in $(seq 1 20); do pgrep -f '[b]in/quickshell' >/dev/null || break; sleep 0.2; done
WAYLAND_DISPLAY=wayland-1 qs -p "$QSP" -d -n
sleep 1
qs -p "$QSP" ipc call island toggle control
sleep 0.6
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" /tmp/claude-1000/-home-jftx-nixos/a4e917d5-7e7b-4708-bd2d-43235c3f0e72/scratchpad/t2-cc.png
nmcli radio wifi off && sleep 1
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" /tmp/claude-1000/-home-jftx-nixos/a4e917d5-7e7b-4708-bd2d-43235c3f0e72/scratchpad/t2-wifi-off.png
nmcli radio wifi on
qs -p "$QSP" ipc call island collapse
```

Read both screenshots. Expected: `t2-cc.png` shows connectivity card (Wi-Fi row with circle icon, Bluetooth row) + DND card + Sound card with capsule slider and device rows, all in current wallpaper colors. `t2-wifi-off.png` shows the Wi-Fi circle no longer primary-filled and status "Off" — proving the event-driven read path with **no reopen**. Then `ipc call island toggle volume` → the placeholder panel (text "volume") appears, confirming the old feature name is gone from the switch. Dev log: no `WARN|ERROR` from ControlCenter/ToggleTile. (Tile *clicks* are jftx's Task 4 checklist.)

- [ ] **Step 8: Flake validation + commit**

```bash
git add modules/home/desktop/quickshell/island/ToggleTile.qml modules/home/desktop/quickshell/island/ControlCenter.qml
nix flake check
```

Expected: clean. Then:

```bash
git add -A
git commit -m "feat(island): control center hub replaces volume panel on SUPER+V (#13)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: DND gate + IPC

**Files:**
- Modify: `modules/home/desktop/quickshell/island/Island.qml` (`notify()`, lines 67–77)
- Modify: `modules/home/desktop/quickshell/shell.qml` (IpcHandler block)

**Interfaces:**
- Consumes: Task 2's `island.dnd: bool`.
- Produces: IPC `qs -p <path> ipc call island dnd true|false` (also `qs -c island ipc call ...` post-rb) — used by Task 4's regression sweep.

- [ ] **Step 1: Gate notify()**

In `Island.qml`, `notify()` gains the DND gate as its first statement:

```qml
    function notify(n): void {
        // DND (spec 2026-07-19): total silence — everything, critical
        // included, is dismissed unseen; nothing queues or replays.
        if (dnd) {
            n.dismiss();
            return;
        }
        n.tracked = true;
        if (expanded) {
            if (pending)
                pending.dismiss();
            pending = n;
            pendingAt = Date.now();
            return;
        }
        display(n);
    }
```

- [ ] **Step 2: Add the IPC function**

In `shell.qml`'s `IpcHandler`, after `collapse()`:

```qml
        function dnd(on: bool): void {
            island.dnd = on;
        }
```

- [ ] **Step 3: Verify (dev instance)**

Warn jftx, then one tight batch:

```bash
QSP=~/nixos/modules/home/desktop/quickshell
SCRATCH=/tmp/claude-1000/-home-jftx-nixos/a4e917d5-7e7b-4708-bd2d-43235c3f0e72/scratchpad
qs kill -p "$QSP"
for i in $(seq 1 20); do pgrep -f '[b]in/quickshell' >/dev/null || break; sleep 0.2; done
WAYLAND_DISPLAY=wayland-1 qs -p "$QSP" -d -n
sleep 1
qs -p "$QSP" ipc call island dnd true
notify-send "dnd-probe" "must NOT toast"
notify-send -u critical "dnd-critical-probe" "must NOT toast either"
sleep 0.7
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" "$SCRATCH/t3-dnd-on.png"
qs -p "$QSP" ipc call island dnd false
sleep 5
notify-send "dnd-off-probe" "must toast"
sleep 0.7
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" "$SCRATCH/t3-dnd-off.png"
```

Read both. Expected: `t3-dnd-on.png` = collapsed pill (neither probe toasted, critical included); `t3-dnd-off.png` = toast showing "dnd-off-probe" only — the 5 s wait proves the suppressed pair did **not** replay after DND off. Dev log clean.

- [ ] **Step 4: Commit**

```bash
git add modules/home/desktop/quickshell/island/Island.qml modules/home/desktop/quickshell/shell.qml
git commit -m "feat(island): total-silence DND gate + dnd IPC (#13)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Regression sweep, docs, rb gate, PR

**Files:**
- Modify: `docs/plans/quickshell-matugen-migration.md` (Track C bullet list, lines 175–180)

**Interfaces:**
- Consumes: everything above; jftx for `rb` + live checklist.
- Produces: merged-ready PR for #13.

- [ ] **Step 1: Scripted regression sweep (dev instance)**

Warn jftx, then:

```bash
QSP=~/nixos/modules/home/desktop/quickshell
SCRATCH=/tmp/claude-1000/-home-jftx-nixos/a4e917d5-7e7b-4708-bd2d-43235c3f0e72/scratchpad
SAVED=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
qs -p "$QSP" ipc call island toggle launcher && sleep 0.6
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" "$SCRATCH/t4-launcher.png"
qs -p "$QSP" ipc call island toggle wallpapers && sleep 0.6
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" "$SCRATCH/t4-wallpapers.png"
qs -p "$QSP" ipc call island collapse
qs -p "$QSP" ipc call island volumeUp && sleep 0.3
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" "$SCRATCH/t4-flash.png"
wpctl set-volume @DEFAULT_AUDIO_SINK@ ${SAVED##* }
```

Expected: launcher and wallpaper grid render as before; flash OSD appears and `wpctl get-volume` moved. Then end the dev session: `qs kill -p "$QSP" && systemctl --user start quickshell` (old shell returns until rb).

- [ ] **Step 2: Tick the master plan**

In `docs/plans/quickshell-matugen-migration.md`, replace the Track C "Control center" bullet's leading text so the section records the order flip and v1:

```markdown
- **Control center** (added 2026-07-08 per jftx; **v1 ✅ 2026-07-19**, spec + plan in docs/superpowers/, PR for #13): Track C is now **control-center-first** — the hub landed before the panels, and every remaining panel arrives as a CC section PR. v1 = Wi-Fi/BT/DND tiles + Sound card (capsule slider fixing #10, output rows) on SUPER+V (slim volume panel deleted). Still to come as sections: network/BT device lists (inline expand), calendar/weather, media card + gated visualizer, notification history. DND is total-silence (critical does not bypass; jftx, gaming). Composes the other Track C panels' backends instead of duplicating them; absorbs the standalone notification-history idea.
```

- [ ] **Step 3: Full build validation**

```bash
git add -A
nix flake check
nixos-rebuild build --flake ~/nixos#blackgarden --sudo
```

Expected: both clean.

- [ ] **Step 4: Commit docs**

```bash
git add docs/plans/quickshell-matugen-migration.md
git commit -m "docs: master plan tick — control-center-first, v1 (#13)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: rb gate (jftx) + live checklist**

Stop and ask jftx to run `rb` and paste output. Then walk him through, batching asks:

1. SUPER+V opens the control center; Escape / click-outside / SUPER+V again collapse it.
2. Wi-Fi tile click flips the radio — assert `nmcli radio wifi` from a terminal; Bluetooth tile click — assert `bluetoothctl show | grep Powered`.
3. DND card click, then `notify-send -u critical probe` → nothing; click again → toasts return.
4. Slider drag feels continuous (#10 dead — many distinct values on `wpctl get-volume`, no ~10-step chunking); glyph click mutes; wheel on the slider still steps ±5%.
5. `hyprctl globalshortcuts` lists `quickshell:control` and no `quickshell:volume`.
6. Regression: ALT+SPACE launcher, ALT+SHIFT+W wallpaper grid, F10–F12 flash, wheel-on-pill, hover peek, wallpaper change while CC open recolors it live.
7. Blur probe (optional, non-persistent): `hyprctl keyword layerrule 'blur, quickshell-island'` — if jftx likes it, file a follow-up issue (persistence needs translucent surface colors via the matugen template — out of v1); `hyprctl reload` reverts the probe either way.

- [ ] **Step 6: PR**

```bash
git push -u origin feat/control-center-v1
gh pr create --title "Track C: control center v1 (#13)" --body "$(cat <<'EOF'
SUPER+V now opens a macOS-style control center: Wi-Fi/Bluetooth/DND toggle
tiles + Sound card (capsule slider, output-device rows). The slim volume
panel is deleted — zero new binds. DND is total silence (critical does not
bypass). Everything mounts inside the expansion Loader: zero idle cost, no
polling, native event-driven Networking/Bluetooth modules.

Closes #13. Fixes #10. Part of epic #7.

Spec: docs/superpowers/specs/2026-07-19-control-center-design.md
Plan: docs/superpowers/plans/2026-07-19-control-center-v1.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

jftx merges after review.
