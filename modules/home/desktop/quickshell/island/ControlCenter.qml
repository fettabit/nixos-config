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
