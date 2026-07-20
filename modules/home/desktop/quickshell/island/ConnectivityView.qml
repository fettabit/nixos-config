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
            "audio-headset": "\uf025",
            "audio-headphones": "\uf025",
            "audio-card": "\uf028",
            "input-gaming": "\uf11b",
            "input-keyboard": "\uf11c",
            "input-mouse": "\uf245",
            "phone": "\uf10b",
            "computer": "\uf108"
        };
        return m[ic] ?? "\uf293";
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
            focus: true
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
                            { key: "internet", icon: "\uf0ac", label: "Internet" },
                            { key: "bluetooth", icon: "\uf293", label: "Bluetooth" }
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
                    text: "\uf011"
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

            icon: dev ? (dev.type === DeviceType.Wired ? "\uf1e6" : "\uf1eb") : "\uf127"
            title: dev ? (dev.network ? dev.network.name : dev.name) : "Disconnected"
            subtitle: dev ? "Connected" : ""
            dimmed: dev === null
            actionText: "Wi-Fi Networks"
            actionSubText: "Switch View"
            chips: dev ? [
                { icon: "\uf0e8", value: dev.name, label: "Interface" },
                { icon: "\uf0e4", value: dev.type === DeviceType.Wired ? dev.linkSpeed + " Mb/s" : "Wireless", label: dev.type === DeviceType.Wired ? "Link Speed" : "Medium" },
                { icon: "\uf2db", value: dev.address || "—", label: "Address" }
            ] : []
            onActionClicked: root.subview = "scan"
        }
    }

    Component {
        id: bluetoothRadial

        RadialDeviceView {
            readonly property var dev: root.btDevice
            readonly property bool adapterOn: root.btAdapter !== null && root.btAdapter.enabled

            icon: dev ? root.btTypeGlyph(dev.icon) : "\uf293"
            title: dev ? (dev.deviceName || dev.name) : "Bluetooth"
            subtitle: dev ? "Connected" : (adapterOn ? "On" : "Off")
            dimmed: dev === null
            actionText: "Scan Devices"
            actionSubText: "Switch View"
            chips: dev ? [
                { icon: "\uf2db", value: dev.address, label: "MAC Address" },
                { icon: "\uf240", value: root.batteryText(dev) || "—", label: "Battery" },
                { icon: "\uf02b", value: root.btTypeLabel(dev.icon), label: "Device Type" }
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
