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

    // BlueZ aliases unnamed devices to their address (dashes for colons) —
    // hide those from the scan list (BLE noise), but never hide a paired
    // or connected device.
    readonly property var sorted: [...devices]
        .filter(d => d.connected || d.paired
            || (d.deviceName || d.name) !== d.address.replace(/:/g, "-"))
        .sort((a, b) =>
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
