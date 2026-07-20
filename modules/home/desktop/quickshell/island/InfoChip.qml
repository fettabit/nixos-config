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
