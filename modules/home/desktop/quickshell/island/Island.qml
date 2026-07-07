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

    anchors.top: true
    margins.top: 12
    // Strip must fit the largest expansion (launcher, step 8).
    implicitWidth: 1200
    implicitHeight: 640
    color: "transparent"
    // Reserve only the collapsed pill strip so windows tile below it;
    // expansions overlay the window area instead of reflowing it.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: margins.top + islandRect.pillHeight + 10
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
        onCleared: root.collapse()
    }

    Rectangle {
        id: islandRect

        readonly property real pillHeight: 46
        readonly property real pillHPad: 22

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expanded ? expandedContent.implicitWidth : pill.implicitWidth + 2 * pillHPad
        height: root.expanded ? expandedContent.implicitHeight : pillHeight
        radius: root.expanded ? 24 : height / 2
        clip: true
        color: Theme.surface_container
        border.width: 1
        border.color: Theme.primary

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
            height: islandRect.pillHeight
            opacity: root.expanded ? 0 : 1
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
