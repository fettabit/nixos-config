import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
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

    // Scripted-verification path: open the launcher (if needed) and set
    // its query, so filtered states can be screenshotted without a real
    // keyboard. Reached via `qs -c island ipc call island search <text>`.
    function search(text: string): void {
        expandedFeature = "launcher";
        expandedContent.item.setQuery(text);
    }

    // Flash: display-only volume OSD (priority: expanded > notifying >
    // flashing > peeked > pill). Restartable so key repeats hold it
    // open; suppressed while expanded (the panel already shows the
    // change live) and while a toast shows (toast wins the display —
    // the volume still changes underneath).
    property bool flashing: false

    // DND (spec 2026-07-19): total silence while on — enforced by the
    // gate in notify(). State is session-only; a fresh shell starts false.
    property bool dnd: false

    function flash(): void {
        if (expanded || notifying)
            return;
        flashing = true;
        flashOut.restart();
    }

    // Toast: display-only notification content, the 5th morph state.
    // Rendering uses fields COPIED at display time so the Notification
    // object can be expired/destroyed mid-fadeout without binding
    // errors; notifHandle is kept only for lifecycle (expire/closed).
    // Spec: docs/superpowers/specs/2026-07-12-island-notifications-design.md
    property bool notifying: false
    property var notifHandle: null
    property string notifSummary: ""
    property string notifBody: ""
    property string notifAppIcon: ""
    property string notifImage: ""
    property bool notifCritical: false
    // Deferred slot: the newest notification that arrived while
    // expanded, shown on collapse if still fresh (spec: 30 s).
    property var pending: null
    property double pendingAt: 0

    function notify(n): void {
        // DND (spec 2026-07-19): total silence — everything, critical
        // included, is dismissed unseen; nothing queues or replays.
        if (dnd) {
            n.dismiss();
            return;
        }
        n.tracked = true;
        if (expanded) {
            if (pending)
                pending.dismiss();
            pending = n;
            pendingAt = Date.now();
            return;
        }
        display(n);
    }

    function display(n): void {
        if (notifHandle)
            notifHandle.expire();
        flashOut.stop();
        flashing = false;
        notifSummary = n.summary;
        notifBody = n.body;
        notifAppIcon = n.appIcon;
        notifImage = n.image;
        notifCritical = n.urgency === NotificationUrgency.Critical;
        notifHandle = n;
        notifying = true;
        // expireTimeout is in MILLISECONDS (-1 = sender default) —
        // the 0.3.0 docs say seconds, but a notify-send -t probe on
        // this build proves ms. Spec: sender value capped at 15 s,
        // else 5 s normal / 10 s critical.
        notifOut.interval = n.expireTimeout > 0
            ? Math.min(n.expireTimeout, 15000)
            : notifCritical ? 10000 : 5000;
        notifOut.restart();
    }

    onExpandedChanged: {
        if (expanded) {
            flashOut.stop();
            flashing = false;
            // Expanding dismisses a showing toast (spec: no re-queue);
            // cleanup runs via the closed handler.
            if (notifHandle)
                notifHandle.expire();
        } else if (pending) {
            const p = pending;
            pending = null;
            if (Date.now() - pendingAt < 30000)
                display(p);
            else
                p.dismiss();
        }
    }

    // Hover peek: display-only third state (no focus grab, no keyboard).
    // Debounced so grazing the screen edge doesn't flicker the island.
    property bool peeked: false
    readonly property bool showPeek: peeked && !expanded && !flashing && !notifying

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

    // In the display-only states (flash, toast) the input region stays
    // pill-sized: clicks in the extra width pass through (spec).
    mask: Region {
        item: root.flashing || root.notifying ? pill : islandRect
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

    Timer {
        id: flashOut

        interval: 1000
        onTriggered: root.flashing = false
    }

    Timer {
        id: notifOut

        onTriggered: {
            if (root.notifHandle)
                root.notifHandle.expire();
        }
    }

    // Single cleanup path: our timer's expire(), an expand-dismissal,
    // and a sender-side close all land here via the closed signal.
    // Connections retargets when notifHandle changes, so a replaced
    // notification's late closed can never tear down the new toast.
    Connections {
        target: root.notifHandle

        function onClosed(reason) {
            notifOut.stop();
            root.notifying = false;
            root.notifHandle = null;
        }
    }

    // A pending notification withdrawn by its sender vacates the slot.
    Connections {
        target: root.pending

        function onClosed(reason) {
            root.pending = null;
        }
    }

    Rectangle {
        id: islandRect

        readonly property real pillHeight: 46
        readonly property real pillHPad: 22

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.expanded ? expandedContent.implicitWidth
             : root.notifying ? toastView.implicitWidth
             : root.flashing ? flashView.implicitWidth
             : root.showPeek ? peekView.implicitWidth
             : pill.implicitWidth + 2 * pillHPad
        height: root.expanded ? expandedContent.implicitHeight
              : root.notifying ? toastView.implicitHeight
              : root.flashing ? flashView.implicitHeight
              : root.showPeek ? peekView.implicitHeight
              : pillHeight
        // Collapsed pill stays a capsule; grown states (peek/expanded/
        // toast) square off to 18 (feel-tuned to jftx's reference notch).
        // pillHeight/2, not height/2: a constant morph target keeps the
        // Behavior from re-targeting every frame while height animates.
        radius: root.expanded || root.showPeek || root.notifying ? 18 : pillHeight / 2
        clip: true
        color: Theme.surface_container
        border.width: 1
        // Critical toasts tint the border as the whole urgency signal.
        border.color: root.notifying && root.notifCritical ? Theme.error : Theme.primary

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

        WheelHandler {
            // target: null — a WheelHandler's default target is its
            // parent, which it would try to transform.
            target: null
            enabled: !root.expanded
            onWheel: event => {
                Audio.step(event.angleDelta.y > 0 ? 1 : -1);
                root.flash();
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
            opacity: root.expanded || root.showPeek || root.flashing || root.notifying ? 0 : 1
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

        VolumeFlash {
            id: flashView

            anchors.centerIn: parent
            opacity: root.flashing ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        NotificationToast {
            id: toastView

            anchors.centerIn: parent
            summary: root.notifSummary
            body: root.notifBody
            appIcon: root.notifAppIcon
            image: root.notifImage
            opacity: root.notifying ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        // Feature expansions load on demand; the morph engine only sees
        // the Loader's implicit size. Steps 9-11 add their features to
        // the sourceComponent switch; unknown names keep the placeholder.
        // Content unloads instantly on collapse — the 320 ms shrink morph
        // covers it (revisit only if it reads harsh live).
        Loader {
            id: expandedContent

            anchors.fill: parent
            active: root.expanded
            focus: true
            sourceComponent: root.expandedFeature === "launcher" ? launcherPanel
                : root.expandedFeature === "control" ? controlPanel
                : root.expandedFeature === "wallpapers" ? wallpaperPanel
                : root.expanded ? placeholderPanel : null
            opacity: root.expanded ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }
        }

        Component {
            id: launcherPanel

            Launcher {
                onDismissRequested: root.collapse()
            }
        }

        Component {
            id: controlPanel

            ControlCenter {
                dnd: root.dnd
                onDndToggled: root.dnd = !root.dnd
                onDismissRequested: root.collapse()
            }
        }

        Component {
            id: wallpaperPanel

            WallpaperPicker {
                onDismissRequested: root.collapse()
            }
        }

        Component {
            id: placeholderPanel

            Item {
                implicitWidth: 560
                implicitHeight: 300
                focus: true

                Keys.onEscapePressed: root.collapse()

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
}
