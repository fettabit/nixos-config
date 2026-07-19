import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.theme

// Display-only notification toast content (the island's 5th morph
// state). No input handlers — the toast never takes clicks or keys;
// Island.qml keeps the input mask pill-sized while it shows. Renders
// from fields copied at display time, never the live Notification
// object, so the object can be expired/destroyed mid-fadeout.
// Spec: docs/superpowers/specs/2026-07-12-island-notifications-design.md
Item {
    id: root

    property string summary: ""
    property string body: ""
    property string appIcon: ""
    property string image: ""

    // Notification image (avatar/album art) wins over the app icon;
    // bell glyph when neither resolves. iconPath(_, true) returns ""
    // for names missing from the theme, falling through to the bell.
    readonly property string iconSource: image !== "" ? image
        : appIcon !== "" ? Quickshell.iconPath(appIcon, true) : ""

    implicitWidth: 400
    implicitHeight: 64

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 20
        spacing: 14

        Item {
            // Fixed cell (flash convention): icon presence must not
            // shift the text column.
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32

            ClippingRectangle {
                anchors.fill: parent
                radius: 8
                color: "transparent"
                visible: root.iconSource !== ""

                IconImage {
                    anchors.fill: parent
                    source: root.iconSource
                    asynchronous: true
                }
            }

            Text {
                // nf-fa-bell
                anchors.centerIn: parent
                text: "\uf0f3"
                color: Theme.primary
                font.family: Theme.iconFontFamily
                font.pixelSize: 18
                visible: root.iconSource === ""
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: root.summary
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.Medium
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            Text {
                Layout.fillWidth: true
                text: root.body
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
                textFormat: Text.PlainText
                // Empty body: collapse the row so the summary centers.
                visible: text !== ""
            }
        }
    }
}
