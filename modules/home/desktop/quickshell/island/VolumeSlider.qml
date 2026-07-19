import QtQuick
import qs.theme

// Thin-track slider (flash-matched vocabulary: 4 px track, small knob).
// Deliberately Audio-free — value in via property, changes out via
// moved() — so the Track C control center can remount it unchanged.
Item {
    id: root

    property real value: 0
    signal moved(real newValue)

    implicitHeight: 24

    function emitFromX(x: real): void {
        moved(Math.max(0, Math.min(1, x / track.width)));
    }

    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        height: 4
        radius: 2
        color: Theme.surface_container_highest

        Rectangle {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * root.value
            height: parent.height
            radius: 2
            color: Theme.primary
        }
    }

    Rectangle {
        id: knob

        x: Math.max(0, Math.min(track.width - width, root.value * track.width - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        radius: 7
        color: Theme.primary
        scale: mouse.pressed ? 1.25 : 1

        Behavior on scale {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutBack
            }
        }
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        onPressed: event => root.emitFromX(event.x)
        onPositionChanged: event => {
            if (pressed)
                root.emitFromX(event.x);
        }
    }

    WheelHandler {
        target: null
        onWheel: event => root.moved(
            Math.max(0, Math.min(1, root.value + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
