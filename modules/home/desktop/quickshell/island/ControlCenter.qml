import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import Quickshell.Bluetooth
import qs.theme

// Island control center: macOS-CC-style hub (spec 2026-07-19). The only
// place CC backends get wired: the Networking/Bluetooth singletons
// (imported here, not shell.qml, so nothing exists until first open),
// Audio, and the island's dnd flag. Pages: root (tiles + sound) ↔
// connectivity (spec 2026-07-19-connectivity-view). No timers, no
// polling — everything here is event-driven and dies with the expansion
// Loader.
Item {
    id: root

    property bool dnd: false
    signal dndToggled()
    signal dismissRequested()

    // Page navigation (spec §Integration): root ↔ connectivity. Content
    // resets to root whenever the island collapses (the expansion Loader
    // recreates this whole component on reopen).
    property string page: "root"
    property string connectivityTab: "internet"

    function openConnectivity(tab: string): void {
        connectivityTab = tab;
        page = "connectivity";
    }

    // Root page keeps the CC's fixed design width (a ColumnLayout's
    // implicitWidth is layout-computed and can't be overridden); the
    // connectivity page brings its own implicit size.
    implicitWidth: root.page === "connectivity" && pageLoader.item
        ? pageLoader.item.implicitWidth + 36 : 440
    implicitHeight: pageLoader.item ? pageLoader.item.implicitHeight + 36 : 200

    focus: true
    Keys.onEscapePressed: root.dismissRequested()

    // First Wi-Fi-capable device; null on machines without one.
    readonly property var wifiDevice: [...Networking.devices.values]
        .find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var btAdapter: Bluetooth.defaultAdapter

    Loader {
        id: pageLoader

        anchors.fill: parent
        anchors.margins: 18
        focus: true
        sourceComponent: root.page === "connectivity" ? connectivityPage : rootPage
    }

    Component {
        id: rootPage

        ColumnLayout {
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
                            onOpenRequested: root.openConnectivity("internet")
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
                            onOpenRequested: root.openConnectivity("bluetooth")
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
}
