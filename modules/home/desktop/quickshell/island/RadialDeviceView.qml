import QtQuick
import qs.theme

// The orbital composition from jftx's reference (spec 2026-07-19):
// concentric rings, center device circle, up to 3 satellite InfoChips
// joined by static hand-drawn-style squiggles, top action pill.
// Backend-free: everything in via properties, actionClicked() out.
Item {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool dimmed: false
    property string actionText: ""
    property string actionSubText: ""
    property var chips: []
    signal actionClicked()

    implicitWidth: 600
    implicitHeight: 500

    readonly property point center: Qt.point(300, 260)

    onChipsChanged: links.requestPaint()

    // Concentric rings.
    Canvas {
        id: rings

        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = Qt.alpha(Theme.outline, 0.18);
            ctx.lineWidth = 1;
            for (const r of [120, 175, 230]) {
                ctx.beginPath();
                ctx.arc(root.center.x, root.center.y, r, 0, 2 * Math.PI);
                ctx.stroke();
            }
        }

        Connections {
            target: Theme

            function onPrimaryChanged() {
                rings.requestPaint();
                links.requestPaint();
            }
        }
    }

    // Squiggle connectors: center edge → each chip's near edge, one
    // bezier with alternating perpendicular wobble seeded by chip index
    // (static — painted, never animated).
    Canvas {
        id: links

        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.strokeStyle = Qt.alpha(Theme.outline, 0.7);
            ctx.lineWidth = 1.4;
            for (let i = 0; i < chipRepeater.count; i++) {
                const item = chipRepeater.itemAt(i);
                if (!item)
                    continue;
                const tx = item.x + item.width / 2;
                const ty = item.y + item.height / 2;
                const dx = tx - root.center.x;
                const dy = ty - root.center.y;
                const len = Math.sqrt(dx * dx + dy * dy);
                const sx = root.center.x + dx / len * 92;
                const sy = root.center.y + dy / len * 92;
                const px = -dy / len;
                const py = dx / len;
                const w = (i % 2 === 0 ? 10 : -10);
                const mx1 = sx + dx * 0.33 + px * w;
                const my1 = sy + dy * 0.33 + py * w;
                const mx2 = sx + dx * 0.66 - px * w;
                const my2 = sy + dy * 0.66 - py * w;
                ctx.beginPath();
                ctx.moveTo(sx, sy);
                ctx.bezierCurveTo(mx1, my1, mx2, my2, tx - dx / len * (item.width / 2 + 6), ty - dy / len * (item.height / 2 + 6));
                ctx.stroke();
            }
        }
    }

    // Center circle: soft two-layer disc, icon + title + state.
    Rectangle {
        x: root.center.x - 92
        y: root.center.y - 92
        width: 184
        height: 184
        radius: 92
        color: Qt.alpha(Theme.primary, root.dimmed ? 0.08 : 0.22)

        Rectangle {
            anchors.centerIn: parent
            width: 168
            height: 168
            radius: 84
            color: root.dimmed ? Theme.surface_container_high : Theme.primary_container

            Column {
                anchors.centerIn: parent
                spacing: 4

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.icon
                    color: root.dimmed ? Theme.on_surface_variant : Theme.on_primary_container
                    font.family: Theme.iconFontFamily
                    font.pixelSize: 34
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.title
                    color: root.dimmed ? Theme.on_surface_variant : Theme.on_primary_container
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    width: 140
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.subtitle
                    color: root.dimmed ? Theme.on_surface_variant : Qt.alpha(Theme.on_primary_container, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }
    }

    // Chip slots: left-mid, right-mid, bottom-left (reference layout).
    Repeater {
        id: chipRepeater

        model: root.chips

        delegate: InfoChip {
            required property var modelData
            required property int index

            icon: modelData.icon
            value: modelData.value
            label: modelData.label
            x: index === 0 ? 30 : index === 1 ? 440 : 170
            y: index === 0 ? 205 : index === 1 ? 255 : 420
            onXChanged: links.requestPaint()
            Component.onCompleted: links.requestPaint()
        }
    }

    // Top action pill (Scan Devices / Switch View).
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 8
        width: actionCol.implicitWidth + 44
        height: 52
        radius: 14
        color: Theme.surface_container_high
        border.width: 1
        border.color: Theme.primary

        Row {
            anchors.centerIn: parent
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf002"
                color: Theme.on_surface
                font.family: Theme.iconFontFamily
                font.pixelSize: 14
            }

            Column {
                id: actionCol

                anchors.verticalCenter: parent.verticalCenter

                Text {
                    text: root.actionText
                    color: Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }

                Text {
                    text: root.actionSubText
                    color: Theme.on_surface_variant
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.actionClicked()
        }
    }
}
