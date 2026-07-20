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
    signal openRequested()

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

            MouseArea {
                anchors.fill: parent
                enabled: root.enabled
                onClicked: root.toggled()
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

    // Label zone (right of the icon circle): opens the detail page.
    MouseArea {
        anchors.fill: parent
        anchors.leftMargin: 44
        enabled: root.enabled
        onClicked: root.openRequested()
    }
}
