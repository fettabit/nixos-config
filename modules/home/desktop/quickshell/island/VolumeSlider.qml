import QtQuick
import qs.theme

// macOS-style capsule slider: thick rounded track, primary fill, speaker
// glyph embedded in the fill's left end (click = mute). Deliberately
// Audio-free — value/muted in via properties, moved()/muteToggled() out —
// so any panel can mount it.
// While pressed the slider renders its own drag position and ignores
// external value re-binds: the value → PipeWire → value round trip lags
// ~0.5 s and quantized drags into ~10 coarse steps (#10).
Item {
    id: root

    property real value: 0
    property bool muted: false
    signal moved(real newValue)
    signal muteToggled()

    readonly property real shown: drag.pressed ? drag.dragValue : value

    implicitHeight: 36

    function valueAt(x: real): real {
        return Math.max(0, Math.min(1, x / width));
    }

    Rectangle {
        id: track

        anchors.fill: parent
        radius: height / 2
        color: Theme.surface_container_highest
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(track.height, track.width * root.shown)
            radius: track.radius
            color: Theme.primary
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 13
        anchors.verticalCenter: parent.verticalCenter
        text: root.muted ? "\uf026" : "\uf028"
        color: Theme.on_primary
        font.family: Theme.iconFontFamily
        font.pixelSize: 16
    }

    MouseArea {
        id: drag

        property real dragValue: 0

        anchors.fill: parent
        onPressed: event => {
            dragValue = root.valueAt(event.x);
            root.moved(dragValue);
        }
        onPositionChanged: event => {
            if (pressed) {
                dragValue = root.valueAt(event.x);
                root.moved(dragValue);
            }
        }
    }

    // On top of the drag area: the glyph zone eats its own clicks for
    // mute; drags simply start to its right.
    MouseArea {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 40
        onClicked: root.muteToggled()
    }

    WheelHandler {
        target: null
        onWheel: event => root.moved(
            Math.max(0, Math.min(1, root.value + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
