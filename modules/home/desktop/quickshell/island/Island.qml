import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.theme

// The dynamic island: a fixed, invisible top-center strip window whose
// input mask tracks the animated island rectangle inside it. Morphing
// animates the rectangle, never the wayland surface, so expansion stays
// smooth and everything outside the island is click-through.
PanelWindow {
    id: root

    // "" = collapsed pill. Feature content is loaded by name in steps
    // 8-11; until then any name expands the placeholder panel.
    property string expandedFeature: ""
    readonly property bool expanded: expandedFeature !== ""

    function toggle(feature: string): void {
        expandedFeature = expandedFeature === feature ? "" : feature;
    }

    function collapse(): void {
        expandedFeature = "";
    }

    // Hover peek: display-only third state (no focus grab, no keyboard).
    // Debounced so grazing the screen edge doesn't flicker the island.
    property bool peeked: false
    readonly property bool showPeek: peeked && !expanded

    anchors.top: true
    margins.top: 15
    // Strip must fit the largest expansion (launcher, step 8).
    implicitWidth: 1200
    implicitHeight: 640
    color: "transparent"
    // Reserve only the collapsed pill strip so windows tile below it;
    // expansions overlay the window area instead of reflowing it.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: margins.top + islandRect.pillHeight + 1
    WlrLayershell.namespace: "quickshell-island"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        item: islandRect
    }

    // Click anywhere outside the island: collapse.
    HyprlandFocusGrab {
        windows: [root]
        active: root.expanded
        onCleared: {
            peekIn.stop();
            peekOut.stop();
            root.peeked = false;
            root.collapse();
        }
    }

    Timer {
        id: peekIn

        interval: 150
        onTriggered: root.peeked = true
    }

    Timer {
        id: peekOut

        interval: 250
        onTriggered: root.peeked = false
    }

    Rectangle {
        id: islandRect

        readonly property real pillHeight: 46
        readonly property real pillHPad: 22

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expanded ? expandedContent.implicitWidth
             : root.showPeek ? peekView.implicitWidth
             : pill.implicitWidth + 2 * pillHPad
        height: root.expanded ? expandedContent.implicitHeight
              : root.showPeek ? peekView.implicitHeight
              : pillHeight
        // Collapsed pill stays a capsule; grown states (peek/expanded)
        // square off to 18 (feel-tuned to jftx's reference notch).
        // pillHeight/2, not height/2: a constant morph target keeps the
        // Behavior from re-targeting every frame while height animates.
        radius: root.expanded || root.showPeek ? 18 : pillHeight / 2
        clip: true
        color: Theme.surface_container
        border.width: 1
        border.color: Theme.primary

        HoverHandler {
            id: hover

            onHoveredChanged: {
                if (hovered) {
                    peekOut.stop();
                    peekIn.restart();
                } else {
                    peekIn.stop();
                    peekOut.restart();
                }
            }
        }

        Behavior on width {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
            }
        }

        Behavior on height {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
            }
        }

        Behavior on radius {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutCubic
            }
        }

        Pill {
            id: pill

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            height: islandRect.pillHeight
            opacity: root.expanded || root.showPeek ? 0 : 1
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        PeekView {
            id: peekView

            anchors.centerIn: parent
            opacity: root.showPeek ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        // Placeholder expansion panel; steps 8-11 replace this with a
        // Loader keyed on expandedFeature.
        Item {
            id: expandedContent

            anchors.fill: parent
            implicitWidth: 560
            implicitHeight: 300
            opacity: root.expanded ? 1 : 0
            visible: opacity > 0
            focus: root.expanded

            Keys.onEscapePressed: root.collapse()

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }

            Text {
                anchors.centerIn: parent
                text: root.expandedFeature
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 24
            }
        }
    }
}
