import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "fuzzy.js" as Fuzzy
import qs.theme

// Island app launcher (Track B step 8): inverted-fzf layout. The search
// bar sits on the panel's bottom edge; results stack upward
// (ListView.BottomToTop) so model index 0 renders at the bottom, next to
// the search bar, holding the best match. Breathing height: implicit
// size follows the result count — the island's width/height Behaviors
// animate the real geometry; this file never animates its own.
// Spec: docs/superpowers/specs/2026-07-08-island-launcher-design.md
Item {
    id: root

    signal dismissRequested()

    // Scripted-verification hook:
    // qs -c island ipc call island search <text>
    function setQuery(text: string): void {
        searchField.text = text;
    }

    readonly property int maxRows: 6
    readonly property int rowHeight: 56
    readonly property int listSpacing: 4
    readonly property int searchHeight: 64
    readonly property int listMargin: 10

    // All visible desktop entries, alphabetical; recomputes if .desktop
    // files change while open.
    readonly property var allApps: [...DesktopEntries.applications.values]
        .filter(entry => !entry.noDisplay)
        .sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" }))

    readonly property int shownRows: Math.min(appModel.count, maxRows)

    implicitWidth: 600
    implicitHeight: searchHeight + 1
        + (shownRows > 0
            ? 2 * listMargin + shownRows * rowHeight + (shownRows - 1) * listSpacing
            : 0)

    // Smart diff (ported from the reference launcher): mutate appModel
    // into the new match order with remove/move/insert instead of a
    // clear+rebuild, so the ListView's add/remove/displaced transitions
    // animate filter changes instead of the list snapping.
    function refilter() {
        root.keyboardNav = false;
        keyboardNavReset.stop();
        const matches = rankedMatches(searchField.text);

        for (let i = appModel.count - 1; i >= 0; i--) {
            const kept = matches.some(m => m.name === appModel.get(i).name);
            if (!kept)
                appModel.remove(i);
        }
        for (let i = 0; i < matches.length; i++) {
            const target = matches[i];
            if (i < appModel.count) {
                if (appModel.get(i).name !== target.name) {
                    let found = -1;
                    for (let j = i + 1; j < appModel.count; j++) {
                        if (appModel.get(j).name === target.name) {
                            found = j;
                            break;
                        }
                    }
                    if (found !== -1)
                        appModel.move(found, i, 1);
                    else
                        appModel.insert(i, { name: target.name, entry: target });
                }
            } else {
                appModel.append({ name: target.name, entry: target });
            }
        }
        appList.currentIndex = appModel.count > 0 ? 0 : -1;
    }

    function rankedMatches(query) {
        const scored = [];
        for (const entry of allApps) {
            const t = Fuzzy.tier(query, entry.name);
            if (t >= 0)
                scored.push({ tier: t, entry: entry });
        }
        scored.sort((a, b) => a.tier - b.tier
            || a.entry.name.localeCompare(b.entry.name, undefined, { sensitivity: "base" }));
        return scored.map(s => s.entry);
    }

    function launchCurrent() {
        if (appList.currentIndex >= 0 && appList.currentIndex < appModel.count)
            launch(appModel.get(appList.currentIndex).entry);
    }

    function launch(entry) {
        entry.execute();
        root.dismissRequested();
    }

    // DesktopEntries scans asynchronously: entries can land after this
    // instance is created, so re-rank whenever the app set changes (this
    // also covers .desktop edits while open). onCompleted covers the
    // already-scanned case on reopen.
    onAllAppsChanged: refilter()
    Component.onCompleted: refilter()

    // The compositor's keyboard-focus grant can race the Loader; the
    // 50 ms retry mirrors the reference launcher's focus management.
    Timer {
        interval: 50
        running: true
        onTriggered: searchField.forceActiveFocus()
    }

    // The morphing highlight only "lags" during keyboard nav; during
    // filter diffs it must stick to the moving current row instantly.
    property bool keyboardNav: false

    Timer {
        id: keyboardNavReset

        interval: 500
        onTriggered: root.keyboardNav = false
    }

    ListModel {
        id: appModel
    }

    ListView {
        id: appList

        anchors.top: parent.top
        anchors.bottom: separator.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.listMargin
        // Bottom-up: index 0 at the bottom, adjacent to the search bar.
        verticalLayoutDirection: ListView.BottomToTop
        clip: true
        model: appModel
        spacing: root.listSpacing
        currentIndex: 0
        boundsBehavior: Flickable.StopAtBounds

        onCurrentIndexChanged: {
            if (currentIndex >= 0)
                positionViewAtIndex(currentIndex, ListView.Contain);
        }

        highlightFollowsCurrentItem: false

        // The reference's stretchy two-edge highlight: the leading edge
        // arrives in 250 ms, the trailing edge catches up in 450 ms.
        highlight: Item {
            z: 0

            Rectangle {
                id: activeHighlight

                property int prevIdx: 0
                property int curIdx: appList.currentIndex
                property real targetTop: appList.currentItem ? appList.currentItem.y : 0
                property real targetBottom: appList.currentItem ? appList.currentItem.y + appList.currentItem.height : 0
                property real actualTop: targetTop
                property real actualBottom: targetBottom

                onCurIdxChanged: {
                    if (curIdx === -1)
                        return;
                    // BottomToTop: higher index = smaller y, so index-up
                    // leads with the TOP edge.
                    if (curIdx > prevIdx) {
                        topAnim.duration = 250;
                        bottomAnim.duration = 450;
                    } else if (curIdx < prevIdx) {
                        bottomAnim.duration = 250;
                        topAnim.duration = 450;
                    }
                    prevIdx = curIdx;
                }

                x: 0
                width: appList.width
                y: actualTop
                height: actualBottom - actualTop
                radius: 8
                color: Theme.primary
                scale: appList.currentItem ? appList.currentItem.scale : 1
                opacity: appList.count > 0 && appList.currentIndex >= 0 ? 1 : 0

                Behavior on actualTop {
                    enabled: root.keyboardNav
                    NumberAnimation {
                        id: topAnim

                        easing.type: Easing.OutExpo
                    }
                }

                Behavior on actualBottom {
                    enabled: root.keyboardNav
                    NumberAnimation {
                        id: bottomAnim

                        easing.type: Easing.OutExpo
                    }
                }

                Behavior on opacity {
                    NumberAnimation {
                        duration: 300
                    }
                }
            }
        }

        populate: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 550; easing.type: Easing.OutExpo }
                NumberAnimation { property: "scale"; from: 0.88; to: 1; duration: 600; easing.type: Easing.OutExpo }
            }
        }

        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 380; easing.type: Easing.OutExpo }
                NumberAnimation { property: "scale"; from: 0.88; to: 1; duration: 420; easing.type: Easing.OutExpo }
            }
        }

        remove: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; to: 0; duration: 280; easing.type: Easing.OutExpo }
                NumberAnimation { property: "scale"; to: 0.88; duration: 300; easing.type: Easing.OutExpo }
            }
        }

        displaced: Transition {
            NumberAnimation { properties: "x,y"; duration: 380; easing.type: Easing.OutExpo }
        }

        ScrollBar.vertical: ScrollBar {
            active: true
            policy: ScrollBar.AsNeeded

            contentItem: Rectangle {
                implicitWidth: 4
                radius: 2
                color: Theme.surface_container_highest
                opacity: 0.5
            }
        }

        delegate: Item {
            id: row

            required property int index
            required property string name
            required property var entry

            width: ListView.view.width
            height: root.rowHeight
            z: 1
            transformOrigin: Item.Center

            // Soft hover wash; the selection is keyboard-owned and never
            // follows the mouse.
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Theme.surface_container_high
                opacity: rowMouse.containsMouse && row.index !== appList.currentIndex ? 0.4 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutSine
                    }
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 15

                // Tinted icon tile with selection pop. First-letter
                // fallback mirrors PeekView's glyph-fallback pattern.
                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 12
                    color: row.index === appList.currentIndex ? Theme.surface_container_lowest : Theme.surface_container_high
                    clip: true
                    scale: row.index === appList.currentIndex ? 1.15 : 1

                    Behavior on scale {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.5
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 300
                            easing.type: Easing.OutExpo
                        }
                    }

                    Image {
                        id: iconImg

                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        visible: row.entry.icon !== "" && iconImg.status !== Image.Error
                        source: row.entry.icon !== "" ? Quickshell.iconPath(row.entry.icon) : ""
                        sourceSize: Qt.size(64, 64)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }

                    Text {
                        visible: row.entry.icon === "" || iconImg.status === Image.Error
                        anchors.centerIn: parent
                        text: row.name.charAt(0).toUpperCase()
                        color: Theme.primary
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                    }

                    // Matugen tint wash over the icon.
                    Rectangle {
                        anchors.fill: parent
                        radius: 12
                        color: Theme.primary
                        opacity: row.index === appList.currentIndex ? 0.25 : 0.08

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.OutExpo
                            }
                        }
                    }
                }

                Text {
                    id: nameText

                    Layout.fillWidth: true
                    text: row.name
                    color: row.index === appList.currentIndex ? Theme.on_primary : Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: row.index === appList.currentIndex ? Font.Bold : Font.Medium
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter

                    property real textShift: row.index === appList.currentIndex ? 6 : 0

                    transform: Translate {
                        x: nameText.textShift
                    }

                    Behavior on textShift {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.OutExpo
                        }
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 300
                            easing.type: Easing.OutExpo
                        }
                    }
                }
            }

            MouseArea {
                id: rowMouse

                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.launch(row.entry)
            }
        }
    }

    Rectangle {
        id: separator

        anchors.bottom: searchRow.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Qt.alpha(Theme.outline_variant, 0.5)
    }

    Item {
        id: searchRow

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.searchHeight

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 15

            Text {
                text: "\uf002" // nf-fa-search
                color: searchField.activeFocus ? Theme.primary : Theme.on_surface_variant
                font.family: Theme.iconFontFamily
                font.pixelSize: 18

                Behavior on color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }

            TextField {
                id: searchField

                Layout.fillWidth: true
                Layout.fillHeight: true
                background: null
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 16
                placeholderText: "Search…"
                placeholderTextColor: Theme.on_surface_variant
                verticalAlignment: TextInput.AlignVCenter
                focus: true

                onTextChanged: root.refilter()

                // BottomToTop: Up walks away from the search bar
                // (index+1), Down back toward the best match (index-1).
                Keys.onUpPressed: event => {
                    root.keyboardNav = true;
                    keyboardNavReset.restart();
                    if (appList.currentIndex < appModel.count - 1)
                        appList.currentIndex++;
                    event.accepted = true;
                }
                Keys.onDownPressed: event => {
                    root.keyboardNav = true;
                    keyboardNavReset.restart();
                    if (appList.currentIndex > 0)
                        appList.currentIndex--;
                    event.accepted = true;
                }
                Keys.onReturnPressed: root.launchCurrent()
                Keys.onEnterPressed: root.launchCurrent()
                Keys.onEscapePressed: root.dismissRequested()
            }
        }
    }
}
