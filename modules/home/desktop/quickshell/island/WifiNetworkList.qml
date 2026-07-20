import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs.theme

// Wi-Fi scan list: SSID + signal + lock; tap connects known/open
// networks or expands an inline PSK field for secured-unknown ones
// (spec: first-connect must work — no saved Wi-Fi profiles exist).
// Backend-free (reads the WifiSecurityType enum only): networks in,
// connectRequested/pskSubmitted out.
Item {
    id: root

    property var networks: []
    property string errorSsid: ""
    property string expandedSsid: ""
    signal connectRequested(var network)
    signal pskSubmitted(var network, string psk)

    readonly property var sorted: [...networks].sort((a, b) =>
        (b.connected - a.connected) || (b.known - a.known)
        || (b.signalStrength - a.signalStrength))

    function signalAlpha(s: real): real {
        return s >= 0.7 ? 1 : s >= 0.4 ? 0.65 : 0.35;
    }

    ListView {
        anchors.fill: parent
        model: root.sorted
        spacing: 4
        clip: true

        delegate: Column {
            required property var modelData

            readonly property bool secured: modelData.security !== WifiSecurityType.Open
            readonly property bool needsPsk: secured && !modelData.known
            readonly property bool expanded: root.expandedSsid === modelData.name
            readonly property bool failed: root.errorSsid === modelData.name

            width: ListView.view.width
            spacing: 0

            Rectangle {
                width: parent.width
                height: 48
                radius: 10
                color: modelData.connected ? Qt.alpha(Theme.primary, 0.18)
                    : failed ? Qt.alpha(Theme.error, 0.15)
                    : rowMouse.containsMouse ? Qt.alpha(Theme.surface_container_highest, 0.5)
                    : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Text {
                        text: "\uf012"
                        opacity: root.signalAlpha(modelData.signalStrength)
                        color: modelData.connected ? Theme.primary : Theme.on_surface
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 14
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            color: Theme.on_surface
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            font.weight: modelData.connected ? Font.Bold : Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            text: modelData.connected ? "Connected"
                                : failed ? "Wrong password?"
                                : modelData.known ? "Saved" : ""
                            color: failed ? Theme.error : Theme.on_surface_variant
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            visible: text !== ""
                        }
                    }

                    Text {
                        text: "\uf023"
                        visible: secured
                        color: Theme.on_surface_variant
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 12
                    }
                }

                MouseArea {
                    id: rowMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        const net = modelData;
                        if (needsPsk)
                            root.expandedSsid = expanded ? "" : net.name;
                        else
                            root.connectRequested(net);
                    }
                }
            }

            // Inline PSK field (only for secured-unknown, when expanded).
            Rectangle {
                width: parent.width
                height: expanded ? 44 : 0
                visible: height > 0
                radius: 10
                color: Theme.surface_container_highest
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: 160
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 10

                    Text {
                        text: "\uf023"
                        color: Theme.on_surface_variant
                        font.family: Theme.iconFontFamily
                        font.pixelSize: 12
                    }

                    TextInput {
                        id: pskInput

                        Layout.fillWidth: true
                        echoMode: TextInput.Password
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        focus: expanded
                        onAccepted: {
                            root.pskSubmitted(modelData, text);
                            text = "";
                        }
                    }

                    Text {
                        text: "Enter ↵"
                        color: Theme.on_surface_variant
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                    }
                }
            }
        }
    }
}
