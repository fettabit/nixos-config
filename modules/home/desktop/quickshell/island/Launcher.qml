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

    // Recompute matches for the current query. Task 3 upgrades the
    // clear+rebuild into the smart diff that feeds list transitions.
    function refilter() {
        const matches = rankedMatches(searchField.text);
        appModel.clear();
        for (const m of matches)
            appModel.append({ name: m.name, entry: m });
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

        // Task 3 replaces this stock bar with the morphing highlight.
        highlightMoveDuration: 0
        highlight: Rectangle {
            radius: 8
            color: Theme.primary
        }

        delegate: Item {
            id: row

            required property int index
            required property string name
            required property var entry

            width: ListView.view.width
            height: root.rowHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 15

                // Icon tile; Task 3 adds tint/scale-pop. First-letter
                // fallback mirrors PeekView's glyph-fallback pattern.
                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 12
                    color: Theme.surface_container_high
                    clip: true

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
                }

                Text {
                    Layout.fillWidth: true
                    text: row.name
                    color: row.index === appList.currentIndex ? Theme.on_primary : Theme.on_surface
                    font.family: Theme.fontFamily
                    font.pixelSize: 15
                    font.weight: row.index === appList.currentIndex ? Font.Bold : Font.Medium
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
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
                    if (appList.currentIndex < appModel.count - 1)
                        appList.currentIndex++;
                    event.accepted = true;
                }
                Keys.onDownPressed: event => {
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
