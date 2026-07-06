import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.theme

// Collapsed island content: clock, plus the playing track's title when
// media is playing (Spotify etc. via Mpris).
Row {
    id: root

    // First actively playing player, or null. The binding re-evaluates
    // when the player list changes and when the playbackState of any
    // visited player notifies.
    readonly property var player: Mpris.players.values.find(p => p.playbackState === MprisPlaybackState.Playing) ?? null

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

    Text {
        visible: root.player !== null
        anchors.verticalCenter: parent.verticalCenter
        text: "" // nf-fa-music
        color: Theme.primary
        font.family: Theme.iconFontFamily
        font.pixelSize: 18
    }

    Text {
        visible: root.player !== null
        anchors.verticalCenter: parent.verticalCenter
        // implicitWidth is the full-text width and is unaffected by
        // width/elide, so this caps the pill without a binding loop.
        width: Math.min(implicitWidth, 420)
        elide: Text.ElideRight
        text: root.player?.trackTitle ?? ""
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 17
    }
}
