# Connectivity View Implementation Plan (Track C section, #15)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A radial connectivity page inside the control center — Internet + Bluetooth tabs with a center device circle, orbiting info chips, squiggle connectors, scan lists (Wi-Fi with inline PSK entry), and per-tab power toggle — entered by tapping a CC tile's label.

**Architecture:** `ControlCenter.qml` gains root ↔ connectivity page navigation (one island feature, Escape steps back). `ConnectivityView.qml` is the page shell and the only new backend-wired file; `RadialDeviceView.qml` (rings/squiggles/center/chips, backend-free) is mounted by both tabs; `WifiNetworkList.qml`/`BtDeviceList.qml` are signal-out scan lists. Scanning (`adapter.discovering`, `wifiDevice.scannerEnabled`) is imperatively synced to "scan subview visible" and force-stopped on every exit path.

**Tech Stack:** Quickshell 0.3.0 QML (`Quickshell.Networking`, `Quickshell.Bluetooth`, Canvas), existing island morph/expansion system.

**Spec:** `docs/superpowers/specs/2026-07-19-connectivity-view-design.md` — read first; holds the approved UX decisions.

**Plan-time facts (verified against installed 0.3.0 qmltypes + nmcli, 2026-07-19):**
- `WifiNetwork.connectWithPsk(psk: string)` is a **Method**; `requestConnectWithPsk` is a signal — ignore it. `Network.connectionFailed(reason)` is a **Signal**; `ConnectionFailReason` = `Unknown | NoSecrets | WifiClientDisconnected | WifiClientFailed | WifiAuthTimeout | WifiNetworkLost`. Wrong-password set: `NoSecrets`, `WifiAuthTimeout`, `WifiClientFailed`.
- `ConnectionState` = `Unknown | Connecting | Connected | Disconnecting | Disconnected`; `WifiSecurityType` includes `Open` (lock glyph = `security !== WifiSecurityType.Open`); `DeviceType` = `None | Wifi | Wired`; `BluetoothDeviceState` = `Disconnected | Connected | Disconnecting | Connecting`; `BluetoothAdapterState` = `Disabled | Enabled | Enabling | Disabling | Blocked`.
- Writable: `BluetoothAdapter.{enabled,discovering}`, `Networking.wifiEnabled`, `WifiDevice.scannerEnabled`. `Network.connect()/disconnect()`, `BluetoothDevice.connect()/disconnect()/pair()`.
- Object lists are `UntypedObjectModel` → `[...X.values]` idiom (`Networking.devices`, `Bluetooth.defaultAdapter.devices`).
- `NetworkDevice.address: string` — semantics (MAC vs IP) unverified; the chip label is the neutral "Address" so either is correct. `BluetoothDevice.battery: double` — scale guarded in code (`b <= 1 ? Math.round(b*100) : Math.round(b)`).
- No saved Wi-Fi profiles exist (`nmcli connection show`: wired only) — PSK path is the first-connect path.
- **Glyph codepoints (BMP FA range, ALWAYS ASCII `\uXXXX` escape text in QML source — never literal glyphs):** globe f0ac, plug f1e6, wifi f1eb, bluetooth f293, power f011, back-chevron f053, search f002, lock f023, signal f012, chain-broken f127, microchip f2db, tachometer f0e4, sitemap f0e8, link f0c1, battery f240, tag f02b, headphones f025, speaker f028, gamepad f11b, keyboard f11c, mouse-pointer f245, mobile f10b, desktop f108.

## Global Constraints

- Dev loop, single-instance rule, jftx-at-keyboard batching, screenshot geometry (`grim -g "2100,0 920x760"` — note taller region), volume etiquette, snake_case theme tokens, `git add` before `nix flake check`: all identical to `docs/superpowers/plans/2026-07-19-control-center-v1.md` Global Constraints — reread them there before starting.
- **Glyph transport:** Write QML with `GLYPH_NAME` placeholder tokens, then python-swap each to its `'\\uXXXX'` escape with `assert count`, exactly as CC v1 did. Never place glyph literals in heredocs or Edit strings. After any file write containing glyph escapes, byte-check: `python3 -c "s=open(F).read(); assert not any(0xE000 <= ord(c) <= 0xF8FF for c in s)"`.
- **No timers, no polling, no new windows/grabs.** Scanning may only be true while its scan subview is visible; every exit path (tab switch, back, collapse, destruction) forces it off. Native module imports stay confined to `ControlCenter.qml` + `ConnectivityView.qml`.
- There is no scripted mouse click: write-path interactions (tile label tap, list row taps, PSK typing) are verified structurally + by jftx at the rb gate; scripted verification covers IPC navigation, renders (grim), external state flips, and scan-lifecycle assertions via `bluetoothctl show` / process state.
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Tile split + CC page navigation + IPC

**Files:**
- Modify: `modules/home/desktop/quickshell/island/ToggleTile.qml` (MouseArea restructure)
- Modify: `modules/home/desktop/quickshell/island/ControlCenter.qml` (page state + Loaders)
- Modify: `modules/home/desktop/quickshell/island/Island.qml` (strip height 640→760; `openConnectivity`)
- Modify: `modules/home/desktop/quickshell/shell.qml` (IPC `connectivity`)

**Interfaces:**
- Produces (Tasks 2–4 rely on): `ToggleTile.openRequested()` signal; `ControlCenter` properties `page: string ("root"|"connectivity")`, `connectivityTab: string ("internet"|"bluetooth")`, function `openConnectivity(tab: string)`; `Island.openConnectivity(tab: string)`; IPC `qs -p <path> ipc call island connectivity internet|bluetooth`. Connectivity content mounts via `Component { id: connectivityPage }` — this task ships a placeholder inside it that Task 2 replaces.

- [ ] **Step 1: Split ToggleTile's hit areas**

In `ToggleTile.qml`: add `signal openRequested()` under `signal toggled()`, delete the full-tile MouseArea at the bottom of the file, and add per-zone areas. The icon Rectangle gains its own MouseArea; the label ColumnLayout is wrapped so its zone is clickable:

```qml
    signal toggled()
    signal openRequested()
```

Inside the icon `Rectangle` (after the `Text`):

```qml
            MouseArea {
                anchors.fill: parent
                enabled: root.enabled
                onClicked: root.toggled()
            }
```

Replace the file-bottom full-tile MouseArea with a label-zone area as the last child of the root Item (fills everything right of the icon):

```qml
    MouseArea {
        anchors.fill: parent
        anchors.leftMargin: 44
        enabled: root.enabled
        onClicked: root.openRequested()
    }
```

- [ ] **Step 2: Page navigation in ControlCenter.qml**

Add state + function after the `btAdapter` property:

```qml
    // Page navigation (spec §Integration): root ↔ connectivity. Content
    // resets to root whenever the island collapses (the expansion Loader
    // recreates this whole component on reopen).
    property string page: "root"
    property string connectivityTab: "internet"

    function openConnectivity(tab: string): void {
        connectivityTab = tab;
        page = "connectivity";
    }
```

Wrap the existing root `ColumnLayout` (id `content`) in a Loader pair. The
existing ColumnLayout moves verbatim into `rootPage`'s Component; sizing
switches to track whichever page is live:

```qml
    implicitWidth: pageLoader.item ? pageLoader.item.implicitWidth + 36 : 440
    implicitHeight: pageLoader.item ? pageLoader.item.implicitHeight + 36 : 200

    Loader {
        id: pageLoader

        anchors.fill: parent
        anchors.margins: 18
        sourceComponent: root.page === "connectivity" ? connectivityPage : rootPage
    }

    Component {
        id: rootPage

        ColumnLayout {
            // ... the existing `content` ColumnLayout body, unchanged ...
        }
    }

    Component {
        id: connectivityPage

        // Task 1 placeholder — Task 2 replaces this with ConnectivityView.
        Item {
            implicitWidth: 600
            implicitHeight: 540
            focus: true

            Keys.onEscapePressed: root.page = "root"

            Text {
                anchors.centerIn: parent
                text: "connectivity: " + root.connectivityTab
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 20
            }
        }
    }
```

Notes: the old `implicitWidth: 440` / `implicitHeight: content.implicitHeight + 36` lines are replaced by the pageLoader-tracking pair above; `anchors.margins: 18` moves from the ColumnLayout to the Loader; the root-page ColumnLayout keeps everything else identical. `Keys.onEscapePressed: root.dismissRequested()` stays on the CC root Item (fires when the root page has focus); the connectivity placeholder overrides Escape to go back instead.

Wire the tiles (root page) to open pages:

```qml
                    ToggleTile {
                        // Wi-Fi tile: existing bindings unchanged, plus
                        onOpenRequested: root.openConnectivity("internet")
                    }
                    ToggleTile {
                        // Bluetooth tile: existing bindings unchanged, plus
                        onOpenRequested: root.openConnectivity("bluetooth")
                    }
```

- [ ] **Step 3: Island strip + entry function**

`Island.qml`: change `implicitHeight: 640` to `implicitHeight: 760` (comment: `// Strip must fit the largest expansion (connectivity page).`). Add below `search()` (same scripted-entry pattern):

```qml
    // Scripted/deep entry: open the control center on the connectivity
    // page. Reached via `qs -c island ipc call island connectivity <tab>`.
    function openConnectivity(tab: string): void {
        expandedFeature = "control";
        expandedContent.item.openConnectivity(tab);
    }
```

`shell.qml` IpcHandler, after `dnd`:

```qml
        function connectivity(tab: string): void {
            island.openConnectivity(tab);
        }
```

- [ ] **Step 4: Verify (dev instance)**

Warn jftx. Then:

```bash
QSP=~/nixos/modules/home/desktop/quickshell
SCRATCH=/tmp/claude-1000/-home-jftx-nixos/a4e917d5-7e7b-4708-bd2d-43235c3f0e72/scratchpad
systemctl --user stop quickshell
WAYLAND_DISPLAY=wayland-1 qs -p "$QSP" -d -n
sleep 1.5
qs -p "$QSP" ipc call island connectivity bluetooth
sleep 0.8
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c1-placeholder.png"
qs -p "$QSP" ipc call island collapse
sleep 0.5
qs -p "$QSP" ipc call island toggle control
sleep 0.8
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c1-root-reset.png"
qs -p "$QSP" ipc call island collapse
```

Read both: `c1-placeholder.png` shows "connectivity: bluetooth" in an island-sized panel; `c1-root-reset.png` shows the normal CC root (page state reset by collapse). Dev log: no new WARN/ERROR.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(island): CC page navigation + split tiles + connectivity IPC (#15)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: InfoChip + RadialDeviceView + ConnectivityView radial tabs

**Files:**
- Create: `modules/home/desktop/quickshell/island/InfoChip.qml`
- Create: `modules/home/desktop/quickshell/island/RadialDeviceView.qml`
- Create: `modules/home/desktop/quickshell/island/ConnectivityView.qml`
- Modify: `modules/home/desktop/quickshell/island/ControlCenter.qml` (placeholder → ConnectivityView)

**Interfaces:**
- Consumes: Task 1's `ControlCenter.page/connectivityTab`, `Networking`/`Bluetooth` singletons (imports move into ConnectivityView too).
- Produces (Tasks 3–4 rely on): `ConnectivityView` properties `tab: string` (alias to CC), `subview: string ("radial"|"scan")`, signal `backRequested()`; `RadialDeviceView` API: `icon/title/subtitle: string`, `dimmed: bool`, `actionText/actionSubText: string`, `chips: var` (array of `{icon, value, label}`), `signal actionClicked()`; `InfoChip` API: `icon/value/label: string`.

- [ ] **Step 1: Create InfoChip.qml** (placeholder-token protocol NOT needed — no glyph literals; glyphs arrive via the `icon` property)

```qml
import QtQuick
import QtQuick.Layouts
import qs.theme

// Radial-view satellite chip: glyph + value + grey sub-label (spec
// reference: MAC / battery / device-type boxes). Backend-free.
Rectangle {
    id: root

    property string icon: ""
    property string value: ""
    property string label: ""

    implicitWidth: row.implicitWidth + 28
    implicitHeight: 54
    radius: 12
    color: Theme.surface_container_high
    border.width: 1
    border.color: Qt.alpha(Theme.outline_variant, 0.6)

    RowLayout {
        id: row

        anchors.centerIn: parent
        spacing: 10

        Text {
            text: root.icon
            color: Theme.primary
            font.family: Theme.iconFontFamily
            font.pixelSize: 15
        }

        ColumnLayout {
            spacing: 0

            Text {
                text: root.value
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                elide: Text.ElideRight
                Layout.maximumWidth: 150
            }

            Text {
                text: root.label
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 10
            }
        }
    }
}
```

- [ ] **Step 2: Create RadialDeviceView.qml**

Fixed chip slots (left, right, bottom) + top action pill, centered circle at (300, 250) in a 600×500 canvas; rings and squiggles are painted once per size/theme/chip change (`onPaint` only — no timers). Squiggle wobble is deterministic per chip index.

```qml
import QtQuick
import qs.theme

// The orbital composition from jftx's reference (spec 2026-07-19):
// concentric rings, center device circle, up to 3 satellite InfoChips
// joined by static hand-drawn-style squiggles, top action pill.
// Backend-free: everything in via properties, actionClicked() out.
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool dimmed: false
    property string actionText: ""
    property string actionSubText: ""
    property var chips: []
    signal actionClicked()

    implicitWidth: 600
    implicitHeight: 500

    readonly property point center: Qt.point(300, 260)

    onChipsChanged: links.requestPaint()

    // Concentric rings.
    Canvas {
        id: rings

        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = Qt.alpha(Theme.outline, 0.18);
            ctx.lineWidth = 1;
            for (const r of [120, 175, 230]) {
                ctx.beginPath();
                ctx.arc(root.center.x, root.center.y, r, 0, 2 * Math.PI);
                ctx.stroke();
            }
        }

        Connections {
            target: Theme

            function onPrimaryChanged() {
                rings.requestPaint();
                links.requestPaint();
            }
        }
    }

    // Squiggle connectors: center edge → each chip's near edge, two
    // quadratic segments with alternating perpendicular wobble seeded by
    // chip index (static — painted, never animated).
    Canvas {
        id: links

        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = Qt.alpha(Theme.outline, 0.7);
            ctx.lineWidth = 1.4;
            for (let i = 0; i < chipRepeater.count; i++) {
                const item = chipRepeater.itemAt(i);
                if (!item)
                    continue;
                const tx = item.x + item.width / 2;
                const ty = item.y + item.height / 2;
                const dx = tx - root.center.x;
                const dy = ty - root.center.y;
                const len = Math.sqrt(dx * dx + dy * dy);
                const sx = root.center.x + dx / len * 92;
                const sy = root.center.y + dy / len * 92;
                const px = -dy / len;
                const py = dx / len;
                const w = (i % 2 === 0 ? 10 : -10);
                const mx1 = sx + dx * 0.33 + px * w;
                const my1 = sy + dy * 0.33 + py * w;
                const mx2 = sx + dx * 0.66 - px * w;
                const my2 = sy + dy * 0.66 - py * w;
                ctx.beginPath();
                ctx.moveTo(sx, sy);
                ctx.bezierCurveTo(mx1, my1, mx2, my2, tx - dx / len * (item.width / 2 + 6), ty - dy / len * (item.height / 2 + 6));
                ctx.stroke();
            }
        }
    }

    // Center circle: soft two-layer disc, icon + title + state.
    Rectangle {
        x: root.center.x - 92
        y: root.center.y - 92
        width: 184
        height: 184
        radius: 92
        color: Qt.alpha(Theme.primary, root.dimmed ? 0.08 : 0.22)

        Rectangle {
            anchors.centerIn: parent
            width: 168
            height: 168
            radius: 84
            color: root.dimmed ? Theme.surface_container_high : Theme.primary_container

            Column {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.icon
                    color: root.dimmed ? Theme.on_surface_variant : Theme.on_primary_container
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 34
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.title
                    color: root.dimmed ? Theme.on_surface_variant : Theme.on_primary_container
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    width: 140
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.subtitle
                    color: root.dimmed ? Theme.on_surface_variant : Qt.alpha(Theme.on_primary_container, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }
    }

    // Chip slots: left-mid, right-mid, bottom-left (reference layout).
    Repeater {
        id: chipRepeater

        model: root.chips

        delegate: InfoChip {
            required property var modelData
            required property int index

            icon: modelData.icon
            value: modelData.value
            label: modelData.label
            x: index === 0 ? 30 : index === 1 ? 440 : 170
            y: index === 0 ? 205 : index === 1 ? 255 : 420
            onXChanged: links.requestPaint()
            Component.onCompleted: links.requestPaint()
        }
    }

    // Top action pill (Scan Devices / Switch View).
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        width: actionCol.implicitWidth + 44
        height: 52
        radius: 14
        color: Theme.surface_container_high
        border.width: 1
        border.color: Theme.primary

        Row {
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "GLYPH_SEARCH"
                color: Theme.on_surface
                font.family: Theme.iconFontFamily
                font.pixelSize: 14
            }

            Column {
                id: actionCol

                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: root.actionText
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Text {
                    text: root.actionSubText
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.actionClicked()
        }
    }
}
```

After writing, python-swap `GLYPH_SEARCH` → `'\\uf002'` (assert count 1) and byte-check the file.

- [ ] **Step 3: Create ConnectivityView.qml**

The page shell: models for both tabs, tab bar, power button, subview switching (this task: radial only — the action pill sets `subview = "scan"`, whose Loader shows a Task-3/4 placeholder Text).

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Bluetooth
import qs.theme

// Connectivity page (spec 2026-07-19): Internet | Bluetooth tabs, radial
// device view ↔ scan list subviews, per-tab power toggle. Wires the
// Networking/Bluetooth singletons; child views stay backend-free.
Item {
    id: root

    property string tab: "internet"
    property string subview: "radial"
    signal backRequested()

    implicitWidth: 600
    implicitHeight: 560

    focus: true
    Keys.onEscapePressed: {
        if (subview === "scan")
            subview = "radial";
        else
            root.backRequested();
    }

    onTabChanged: subview = "radial"

    // ---- backends ----
    readonly property var wifiDevice: [...Networking.devices.values]
        .find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var activeDevice: [...Networking.devices.values]
        .find(d => d.connected && d.type !== DeviceType.None) ?? null
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property var btDevice: btAdapter
        ? ([...btAdapter.devices.values].find(d => d.connected) ?? null)
        : null

    // BlueZ icon string → label + glyph (spec: device-type chip).
    function btTypeLabel(ic: string): string {
        const m = {
            "audio-headset": "Headset",
            "audio-headphones": "Headphones",
            "audio-card": "Speaker",
            "input-gaming": "Gamepad",
            "input-keyboard": "Keyboard",
            "input-mouse": "Mouse",
            "phone": "Phone",
            "computer": "Computer"
        };
        return m[ic] ?? "Device";
    }

    function btTypeGlyph(ic: string): string {
        const m = {
            "audio-headset": "GLYPH_HEADPHONES",
            "audio-headphones": "GLYPH_HEADPHONES",
            "audio-card": "GLYPH_SPEAKER",
            "input-gaming": "GLYPH_GAMEPAD",
            "input-keyboard": "GLYPH_KEYBOARD",
            "input-mouse": "GLYPH_MOUSE",
            "phone": "GLYPH_MOBILE",
            "computer": "GLYPH_DESKTOP"
        };
        return m[ic] ?? "GLYPH_BLUETOOTH";
    }

    function batteryText(d): string {
        if (!d || !d.batteryAvailable)
            return "";
        return (d.battery <= 1 ? Math.round(d.battery * 100) : Math.round(d.battery)) + "%";
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.subview === "radial"
                ? (root.tab === "internet" ? internetRadial : bluetoothRadial)
                : scanPlaceholder
        }

        // Bottom bar: tab switcher + power.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 48

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: tabRow.implicitWidth + 12
                Layout.preferredHeight: 44
                radius: 12
                color: Theme.surface_container_high

                Row {
                    id: tabRow

                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: [
                            { key: "internet", icon: "GLYPH_GLOBE", label: "Internet" },
                            { key: "bluetooth", icon: "GLYPH_BLUETOOTH", label: "Bluetooth" }
                        ]

                        delegate: Rectangle {
                            required property var modelData

                            readonly property bool current: root.tab === modelData.key

                            width: tabContent.implicitWidth + 28
                            height: 36
                            radius: 9
                            color: current ? Theme.primary : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }

                            Row {
                                id: tabContent

                                anchors.centerIn: parent
                                spacing: 8

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.icon
                                    color: current ? Theme.on_primary : Theme.on_surface
                                    font.family: Theme.iconFontFamily
                                    font.pixelSize: 13
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: current ? Theme.on_primary : Theme.on_surface
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.tab = modelData.key
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Power: BT tab → adapter; Internet tab → Wi-Fi radio only.
            Rectangle {
                readonly property bool on: root.tab === "bluetooth"
                    ? (root.btAdapter !== null && root.btAdapter.enabled)
                    : Networking.wifiEnabled

                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 22
                color: on ? Theme.primary : Theme.surface_container_high

                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "GLYPH_POWER"
                    color: parent.on ? Theme.on_primary : Theme.on_surface
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 16
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.tab === "bluetooth") {
                            if (root.btAdapter)
                                root.btAdapter.enabled = !root.btAdapter.enabled;
                        } else {
                            Networking.wifiEnabled = !Networking.wifiEnabled;
                        }
                    }
                }
            }
        }
    }

    Component {
        id: internetRadial

        RadialDeviceView {
            readonly property var dev: root.activeDevice

            icon: dev ? (dev.type === DeviceType.Wired ? "GLYPH_PLUG" : "GLYPH_WIFI") : "GLYPH_BROKEN"
            title: dev ? (dev.network ? dev.network.name : dev.name) : "Disconnected"
            subtitle: dev ? "Connected" : ""
            dimmed: dev === null
            actionText: "Wi-Fi Networks"
            actionSubText: "Switch View"
            chips: dev ? [
                { icon: "GLYPH_SITEMAP", value: dev.name, label: "Interface" },
                { icon: "GLYPH_TACHO", value: dev.type === DeviceType.Wired ? dev.linkSpeed + " Mb/s" : "Wireless", label: dev.type === DeviceType.Wired ? "Link Speed" : "Medium" },
                { icon: "GLYPH_MICROCHIP", value: dev.address || "GLYPH_EMDASH", label: "Address" }
            ] : []
            onActionClicked: root.subview = "scan"
        }
    }

    Component {
        id: bluetoothRadial

        RadialDeviceView {
            readonly property var dev: root.btDevice
            readonly property bool adapterOn: root.btAdapter !== null && root.btAdapter.enabled

            icon: dev ? root.btTypeGlyph(dev.icon) : "GLYPH_BLUETOOTH"
            title: dev ? (dev.deviceName || dev.name) : "Bluetooth"
            subtitle: dev ? "Connected" : (adapterOn ? "On" : "Off")
            dimmed: dev === null
            actionText: "Scan Devices"
            actionSubText: "Switch View"
            chips: dev ? [
                { icon: "GLYPH_MICROCHIP", value: dev.address, label: "MAC Address" },
                { icon: "GLYPH_BATTERY", value: root.batteryText(dev) || "GLYPH_EMDASH", label: "Battery" },
                { icon: "GLYPH_TAG", value: root.btTypeLabel(dev.icon), label: "Device Type" }
            ] : []
            onActionClicked: root.subview = "scan"
        }
    }

    Component {
        id: scanPlaceholder

        Item {
            Text {
                anchors.centerIn: parent
                text: "scan: " + root.tab
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 18
            }
        }
    }
}
```

Then python-swap ALL placeholder tokens in this file (assert each count ≥ 1): `GLYPH_HEADPHONES → '\\uf025'`, `GLYPH_SPEAKER → '\\uf028'`, `GLYPH_GAMEPAD → '\\uf11b'`, `GLYPH_KEYBOARD → '\\uf11c'`, `GLYPH_MOUSE → '\\uf245'`, `GLYPH_MOBILE → '\\uf10b'`, `GLYPH_DESKTOP → '\\uf108'`, `GLYPH_BLUETOOTH → '\\uf293'`, `GLYPH_GLOBE → '\\uf0ac'`, `GLYPH_POWER → '\\uf011'`, `GLYPH_PLUG → '\\uf1e6'`, `GLYPH_WIFI → '\\uf1eb'`, `GLYPH_BROKEN → '\\uf127'`, `GLYPH_SITEMAP → '\\uf0e8'`, `GLYPH_TACHO → '\\uf0e4'`, `GLYPH_MICROCHIP → '\\uf2db'`, `GLYPH_BATTERY → '\\uf240'`, `GLYPH_TAG → '\\uf02b'`, `GLYPH_EMDASH → '—'` (plain em dash, not a PUA glyph). Byte-check after.

- [ ] **Step 4: Mount in ControlCenter**

Replace Task 1's placeholder `connectivityPage` Component body:

```qml
    Component {
        id: connectivityPage

        ConnectivityView {
            tab: root.connectivityTab
            onTabChanged: root.connectivityTab = tab
            onBackRequested: root.page = "root"
        }
    }
```

- [ ] **Step 5: Verify (dev instance)**

Restart dev instance (kill/relaunch recipe), then:

```bash
qs -p "$QSP" ipc call island connectivity internet && sleep 0.8
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c2-internet.png"
qs -p "$QSP" ipc call island connectivity bluetooth && sleep 0.8
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c2-bluetooth.png"
bluetoothctl power off && sleep 1
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c2-bt-off.png"
bluetoothctl power on
qs -p "$QSP" ipc call island collapse
```

Read all three. Expected: `c2-internet.png` = radial with plug icon, connection name, Interface/Link Speed/Address chips, squiggles + rings, `Internet` tab filled, power tinted per Wi-Fi radio; `c2-bluetooth.png` = JBL center (if connected — else adapter view) with MAC/Battery/Device-Type chips; `c2-bt-off.png` = dimmed adapter-off center, power button untinted — updated live. Log clean.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(island): radial connectivity view — Internet + Bluetooth tabs (#15)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: BtDeviceList + scan lifecycle

**Files:**
- Create: `modules/home/desktop/quickshell/island/BtDeviceList.qml`
- Modify: `modules/home/desktop/quickshell/island/ConnectivityView.qml` (scan Loader + lifecycle sync)

**Interfaces:**
- Consumes: Task 2's `ConnectivityView.subview` switching; `BluetoothDevice` API (`connected`, `paired`, `state`, `connect()`, `disconnect()`, `pair()`).
- Produces: `BtDeviceList` with `devices: var`, `signal deviceClicked(var device)`; ConnectivityView function `syncScanning()` (Task 4 extends it for Wi-Fi).

- [ ] **Step 1: Create BtDeviceList.qml**

```qml
import QtQuick
import QtQuick.Layouts
import qs.theme

// Bluetooth scan list: connected first, then paired, then discovered.
// Backend-free: devices in, deviceClicked(device) out.
Item {
    id: root

    property var devices: []
    property var typeGlyph: (ic) => ""
    property var batteryText: (d) => ""
    signal deviceClicked(var device)

    readonly property var sorted: [...devices].sort((a, b) =>
        (b.connected - a.connected) || (b.paired - a.paired)
        || (a.name < b.name ? -1 : 1))

    ListView {
        anchors.fill: parent
        model: root.sorted
        spacing: 4
        clip: true

        delegate: Rectangle {
            required property var modelData

            width: ListView.view.width
            height: 52
            radius: 10
            color: modelData.connected ? Qt.alpha(Theme.primary, 0.18)
                : rowMouse.containsMouse ? Qt.alpha(Theme.surface_container_highest, 0.5)
                : "transparent"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12

                Text {
                    text: root.typeGlyph(modelData.icon)
                    color: modelData.connected ? Theme.primary : Theme.on_surface
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 15
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        Layout.fillWidth: true
                        text: modelData.deviceName || modelData.name
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        font.weight: modelData.connected ? Font.Bold : Font.Medium
                        elide: Text.ElideRight
                    }

                    Text {
                        text: modelData.connected ? "Connected"
                            : modelData.paired ? "Paired" : "Discovered"
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }

                Text {
                    text: root.batteryText(modelData)
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                }
            }

            MouseArea {
                id: rowMouse

                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.deviceClicked(modelData)
            }
        }
    }
}
```

- [ ] **Step 2: Scan lifecycle + mount in ConnectivityView**

Add to `ConnectivityView.qml` (below the backend properties):

```qml
    // Scan lifecycle (spec hard rule): scanning is true ONLY while its
    // scan subview is visible. Imperative sync + belt-and-braces cleanup
    // on every exit path, destruction included.
    function syncScanning(): void {
        const btScan = visible && tab === "bluetooth" && subview === "scan";
        const wifiScan = visible && tab === "internet" && subview === "scan";
        if (btAdapter)
            btAdapter.discovering = btScan && btAdapter.enabled;
        if (wifiDevice)
            wifiDevice.scannerEnabled = wifiScan && Networking.wifiEnabled;
    }

    onSubviewChanged: syncScanning()
    onVisibleChanged: syncScanning()
    Component.onCompleted: syncScanning()

    Component.onDestruction: {
        if (btAdapter)
            btAdapter.discovering = false;
        if (wifiDevice)
            wifiDevice.scannerEnabled = false;
    }
```

(`onTabChanged` already resets `subview = "radial"`, which triggers `onSubviewChanged` → sync.) Replace the `scanPlaceholder` route for bluetooth in the subview Loader:

```qml
            sourceComponent: root.subview === "radial"
                ? (root.tab === "internet" ? internetRadial : bluetoothRadial)
                : (root.tab === "bluetooth" ? btScan : scanPlaceholder)
```

and add the Component:

```qml
    Component {
        id: btScan

        BtDeviceList {
            devices: root.btAdapter ? [...root.btAdapter.devices.values] : []
            typeGlyph: root.btTypeGlyph
            batteryText: root.batteryText
            onDeviceClicked: device => {
                if (device.connected)
                    device.disconnect();
                else if (device.paired)
                    device.connect();
                else
                    device.pair();
            }
        }
    }
```

- [ ] **Step 3: Verify (dev instance — the load-bearing scan assertions)**

Restart dev instance, then one batch:

```bash
qs -p "$QSP" ipc call island connectivity bluetooth && sleep 0.5
bluetoothctl show | grep Discovering        # expect: no (radial subview)
# Enter scan via IPC-driven UI? No click available — use the structural
# route: subview flips on actionClicked only. Add temporary check instead:
qs -p "$QSP" ipc call island collapse
```

Scan-entry has no scripted click, so extend IPC once (permanent, tiny): in `shell.qml` IpcHandler add

```qml
        function connectivitySub(sub: string): void {
            island.openConnectivitySub(sub);
        }
```

and in `Island.qml` below `openConnectivity`:

```qml
    function openConnectivitySub(sub: string): void {
        expandedContent.item.setConnectivitySubview(sub);
    }
```

and in `ControlCenter.qml`:

```qml
    function setConnectivitySubview(sub: string): void {
        if (page === "connectivity" && pageLoader.item)
            pageLoader.item.subview = sub;
    }
```

Then the real assertion batch:

```bash
qs -p "$QSP" ipc call island connectivity bluetooth && sleep 0.5
qs -p "$QSP" ipc call island connectivitySub scan && sleep 1.2
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c3-btscan.png"
bluetoothctl show | grep Discovering        # expect: yes
qs -p "$QSP" ipc call island connectivitySub radial && sleep 0.5
bluetoothctl show | grep Discovering        # expect: no
qs -p "$QSP" ipc call island connectivitySub scan && sleep 0.5
qs -p "$QSP" ipc call island collapse && sleep 0.5
bluetoothctl show | grep Discovering        # expect: no  ← collapse mid-scan
```

Read `c3-btscan.png`: device rows (JBL connected-first with battery, any discovered devices below). All three Discovering asserts must match.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(island): bluetooth device list + strict scan lifecycle (#15)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: WifiNetworkList + inline PSK

**Files:**
- Create: `modules/home/desktop/quickshell/island/WifiNetworkList.qml`
- Modify: `modules/home/desktop/quickshell/island/ConnectivityView.qml` (wifi scan route + connect/fail handling)

**Interfaces:**
- Consumes: Task 3's `syncScanning()` (already covers Wi-Fi), `connectivitySub` IPC; `WifiNetwork` API (`name`, `signalStrength`, `security`, `connected`, `known`, `connect()`, `connectWithPsk(psk)`, signal `connectionFailed(reason)`).
- Produces: `WifiNetworkList` with `networks: var`, `errorSsid: string`, signals `connectRequested(var network)`, `pskSubmitted(var network, string psk)`.

- [ ] **Step 1: Create WifiNetworkList.qml**

```qml
import QtQuick
import QtQuick.Layouts
import qs.theme

// Wi-Fi scan list: SSID + signal + lock; tap connects known/open
// networks or expands an inline PSK field for secured-unknown ones
// (spec: first-connect must work — no saved Wi-Fi profiles exist).
// Backend-free: networks in, connectRequested/pskSubmitted out.
Item {
    id: root

    property var networks: []
    property string errorSsid: ""
    property string expandedSsid: ""
    signal connectRequested(var network)
    signal pskSubmitted(var network, string psk)

    readonly property var sorted: [...networks].sort((a, b) =>
        (b.connected - a.connected) || (b.known - a.known)
        || (b.signalStrength - a.signalStrength))

    function signalAlpha(s: real): real {
        return s >= 0.7 ? 1 : s >= 0.4 ? 0.65 : 0.35;
    }

    ListView {
        anchors.fill: parent
        model: root.sorted
        spacing: 4
        clip: true

        delegate: Column {
            required property var modelData

            readonly property bool secured: modelData.security !== WifiSecurityType.Open
            readonly property bool needsPsk: secured && !modelData.known
            readonly property bool expanded: root.expandedSsid === modelData.name
            readonly property bool failed: root.errorSsid === modelData.name

            width: ListView.view.width
            spacing: 0

            Rectangle {
                width: parent.width
                height: 48
                radius: 10
                color: modelData.connected ? Qt.alpha(Theme.primary, 0.18)
                    : failed ? Qt.alpha(Theme.error, 0.15)
                    : rowMouse.containsMouse ? Qt.alpha(Theme.surface_container_highest, 0.5)
                    : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Text {
                        text: "GLYPH_SIGNAL"
                        opacity: root.signalAlpha(modelData.signalStrength)
                        color: modelData.connected ? Theme.primary : Theme.on_surface
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 14
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            color: Theme.on_surface
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: modelData.connected ? Font.Bold : Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            text: modelData.connected ? "Connected"
                                : failed ? "Wrong password?"
                                : modelData.known ? "Saved" : ""
                            color: failed ? Theme.error : Theme.on_surface_variant
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            visible: text !== ""
                        }
                    }

                    Text {
                        text: "GLYPH_LOCK"
                        visible: secured
                        color: Theme.on_surface_variant
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: rowMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        const net = modelData;
                        if (needsPsk)
                            root.expandedSsid = expanded ? "" : net.name;
                        else
                            root.connectRequested(net);
                    }
                }
            }

            // Inline PSK field (only for secured-unknown, when expanded).
            Rectangle {
                width: parent.width
                height: expanded ? 44 : 0
                visible: height > 0
                radius: 10
                color: Theme.surface_container_highest
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 160
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Text {
                        text: "GLYPH_LOCK"
                        color: Theme.on_surface_variant
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 12
                    }

                    TextInput {
                        id: pskInput

                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        focus: expanded
                        onAccepted: {
                            root.pskSubmitted(modelData, text);
                            text = "";
                        }
                    }

                    Text {
                        text: "Enter ↵"
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }
        }
    }
}
```

Python-swap `GLYPH_SIGNAL → '\\uf012'`, `GLYPH_LOCK → '\\uf023'` (lock appears twice — assert count 2); byte-check. Note `WifiSecurityType` needs `import Quickshell.Networking` in this file — add it to the imports (state-reading enum only; no API calls, stays within the CC subtree rule).

- [ ] **Step 2: Wire into ConnectivityView**

Subview Loader route becomes:

```qml
            sourceComponent: root.subview === "radial"
                ? (root.tab === "internet" ? internetRadial : bluetoothRadial)
                : (root.tab === "bluetooth" ? btScan : wifiScan)
```

Delete the `scanPlaceholder` Component. Add fail-tracking + the Component:

```qml
    // PSK failure surface: remember the SSID whose connect failed for the
    // wrong-password reasons (plan-time fact: NoSecrets | WifiAuthTimeout
    // | WifiClientFailed).
    property string wifiErrorSsid: ""
    property var pendingNetwork: null

    Connections {
        target: root.pendingNetwork

        function onConnectionFailed(reason) {
            if (reason === ConnectionFailReason.NoSecrets
                || reason === ConnectionFailReason.WifiAuthTimeout
                || reason === ConnectionFailReason.WifiClientFailed)
                root.wifiErrorSsid = root.pendingNetwork.name;
        }
    }

    Component {
        id: wifiScan

        WifiNetworkList {
            networks: root.wifiDevice ? [...root.wifiDevice.networks.values] : []
            errorSsid: root.wifiErrorSsid
            onConnectRequested: network => {
                root.wifiErrorSsid = "";
                root.pendingNetwork = network;
                network.connect();
            }
            onPskSubmitted: (network, psk) => {
                root.wifiErrorSsid = "";
                root.pendingNetwork = network;
                network.connectWithPsk(psk);
            }
        }
    }
```

(`WifiDevice.networks` — if runtime logs show it is a plain list rather than an ObjectModel, drop `.values`; check the dev log on first open.)

- [ ] **Step 3: Verify (dev instance)**

```bash
nmcli radio wifi on
qs -p "$QSP" ipc call island connectivity internet && sleep 0.5
qs -p "$QSP" ipc call island connectivitySub scan && sleep 3
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c4-wifiscan.png"
nmcli -f WIFI general                        # radio on; scanner active is internal —
qs -p "$QSP" ipc call island connectivitySub radial && sleep 0.5
qs -p "$QSP" ipc call island collapse
nmcli radio wifi off
```

Read `c4-wifiscan.png`: neighborhood SSIDs with signal-strength opacity + lock glyphs, sorted by strength. (PSK expansion + real join are jftx's live checklist — no scripted clicks.) Dev log: no errors; note whether `networks.values` needed the fallback.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(island): wifi network list with inline PSK entry (#15)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Regression, docs, rb gate, PR

**Files:**
- Modify: `docs/plans/quickshell-matugen-migration.md` (Track C control-center bullet)

- [ ] **Step 1: Scripted regression sweep (dev instance)**

```bash
SAVED=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
qs -p "$QSP" ipc call island toggle control && sleep 0.6
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c5-ccroot.png"
qs -p "$QSP" ipc call island collapse
qs -p "$QSP" ipc call island toggle launcher && sleep 0.6
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c5-launcher.png"
qs -p "$QSP" ipc call island collapse
qs -p "$QSP" ipc call island volumeUp && sleep 0.3
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c5-flash.png"
wpctl set-volume @DEFAULT_AUDIO_SINK@ ${SAVED##* }
qs -p "$QSP" ipc call island dnd true && notify-send probe x && sleep 0.6
WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x760" "$SCRATCH/c5-dnd.png"
qs -p "$QSP" ipc call island dnd false
```

Expected: CC root unchanged (tiles + sound card), launcher fine, flash fine, DND still silences. End dev session: `qs kill -p "$QSP" && systemctl --user start quickshell`.

- [ ] **Step 2: Master plan tick**

In the Track C control-center bullet (edited by CC v1's Task 4), change `Still to come as sections: network/BT device lists (inline expand), calendar/weather, media card + gated visualizer, notification history.` to:

```markdown
Sections landed: **connectivity view ✅ 2026-07-19** (#15 — radial Internet/Bluetooth page, split tiles, scan lists, inline Wi-Fi PSK; peek network slot still open). Still to come: calendar/weather, media card + gated visualizer, notification history, peek network indicator.
```

- [ ] **Step 3: Validate + commit docs**

```bash
git add -A && nix flake check && nixos-rebuild build --flake ~/nixos#blackgarden --sudo
git commit -m "docs: master plan tick — connectivity view (#15)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: rb gate (jftx) + live checklist**

Stop; ask jftx to `rb` + paste. Then batched asks: (1) SUPER+V → CC; tile **icons** still toggle radios; tile **labels** open the connectivity page on the right tab; (2) Escape chain: scan → radial → root → closed; (3) Bluetooth: JBL shows center w/ MAC + battery + Headset chips; Scan Devices lists it; tap disconnect/reconnect works; (4) Internet: ethernet radial correct (check what Address shows — MAC or IP — and confirm chip label reads fine either way); Wi-Fi Networks view: join his real network via inline PSK (first-time save), then confirm tap-reconnect works and a wrong password shows the error tint; (5) power buttons per tab; (6) regressions: slider drag, wheel, F10–F12, ALT+SPACE, ALT+SHIFT+W, peek, wallpaper recolor while the radial is open; (7) sizes on the ultrawide (chips/squiggles not cramped).

- [ ] **Step 5: PR**

```bash
git push -u origin feat/connectivity-view
gh pr create --title "Track C: connectivity view — radial Internet/Bluetooth page (#15)" --body "$(cat <<'EOF'
First CC section: a radial connectivity page inside the control center —
center device circle, orbiting info chips with hand-drawn squiggle
connectors, Internet | Bluetooth tabs, scan lists (Wi-Fi with inline PSK
entry for first-time joins), per-tab power toggle. CC tiles split: icon
toggles the radio, label opens the page. Scanning is strictly scoped to a
visible scan view (forced off on tab switch, back, and collapse). No
timers, no polling; native event-driven Networking/Bluetooth only.

Closes #15. Part of epic #7.

Spec: docs/superpowers/specs/2026-07-19-connectivity-view-design.md
Plan: docs/superpowers/plans/2026-07-19-connectivity-view.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

jftx merges after review.
