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
