import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs.theme

// Hover peek content: now-playing block (only while something plays) +
// large clock/date. Display-only — no interaction, no focus. The row
// intentionally ends after the clock; Track C's network indicator takes
// the right slot (plan step-7 addendum).
Row {
    id: root

    // Same "first playing player" rule the pill used before the peek.
    readonly property var player: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing) ?? null
    readonly property string artUrl: root.player?.trackArtUrl ?? ""

    padding: 24
    spacing: 24

    ClippingRectangle {
        visible: root.player !== null
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: 56
        implicitHeight: 56
        radius: 14
        color: Theme.surface_container_high

        Image {
            anchors.fill: parent
            visible: root.artUrl !== ""
            source: root.artUrl
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(112, 112)
            asynchronous: true
        }

        // No art URL from the player: music-note glyph instead.
        Text {
            visible: root.artUrl === ""
            anchors.centerIn: parent
            text: "" // nf-fa-music
            color: Theme.primary
            font.family: Theme.iconFontFamily
            font.pixelSize: 22
        }
    }

    Column {
        visible: root.player !== null
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Text {
            // implicitWidth is the full-text width, unaffected by
            // width/elide — caps the column without a binding loop.
            width: Math.min(implicitWidth, 340)
            elide: Text.ElideRight
            text: root.player?.trackTitle ?? ""
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }

        Text {
            width: Math.min(implicitWidth, 340)
            elide: Text.ElideRight
            text: root.player?.trackArtist ?? ""
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 15
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        SystemClock {
            id: clock

            precision: SystemClock.Minutes
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "hh:mm")
            color: Theme.on_surface
            font.family: Theme.fontFamily
            font.pixelSize: 30
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "ddd, MMM d")
            color: Theme.on_surface_variant
            font.family: Theme.fontFamily
            font.pixelSize: 14
        }
    }
}
