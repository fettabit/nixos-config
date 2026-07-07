import QtQuick
import Quickshell
import qs.theme

// Collapsed island content: clock only. Now-playing lives in the hover
// peek (PeekView.qml).
Row {
    id: root

    spacing: 14

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, "hh:mm")
        color: Theme.on_surface
        font.family: Theme.fontFamily
        font.pixelSize: 20
    }
}
