import QtQuick
import QtQuick.Layouts
import qs.theme

// Output-device radio rows. Deliberately Audio-free — devices/current in
// via properties, choice out via selected() — so the Track C control
// center can remount it unchanged.
Column {
    id: root

    property var devices: []
    property var current: null
    signal selected(var node)

    spacing: 2

    Repeater {
        model: root.devices

        delegate: Item {
            id: row

            required property var modelData
            readonly property bool isCurrent: root.current !== null
                && modelData.id === root.current.id

            width: root.width
            height: 44

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Theme.surface_container_high
                opacity: rowMouse.containsMouse && !row.isCurrent ? 0.4 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 18
                    Layout.preferredHeight: 18
                    radius: 9
                    color: "transparent"
                    border.width: 2
                    border.color: row.isCurrent ? Theme.primary : Theme.outline

                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        color: Theme.primary
                        visible: row.isCurrent
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: row.modelData.description || row.modelData.nickname || row.modelData.name
                    color: row.isCurrent ? Theme.primary : Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    font.weight: row.isCurrent ? Font.Bold : Font.Medium
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }

            MouseArea {
                id: rowMouse

                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.selected(row.modelData)
            }
        }
    }
}
