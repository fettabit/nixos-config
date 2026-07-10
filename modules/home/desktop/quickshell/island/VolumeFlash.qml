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
