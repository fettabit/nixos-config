import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.theme

// Island wallpaper picker (Track B step 11): 4-column thumbnail grid
// over ~/wallpapers. Enter/click applies via wallpaper-set — the
// shell's only external call; queue file + wallpaper.service
// activation, which also resets the 10-min rotation countdown — and
// the grid STAYS OPEN so candidates can be hopped between while the
// retheme cascade recolors the island live. ESC closes. Thumbnails
// decode off-thread at cell resolution (sourceSize) so opening never
// janks the morph.
// Spec: docs/superpowers/specs/2026-07-15-wallpaper-picker-design.md
Item {
    id: root

    signal dismissRequested()

    readonly property int tileW: 272
    readonly property int tileH: 153
    readonly property int gap: 12
    readonly property int pad: 24
    readonly property int viewH: 560

    // WALLPAPER_DIR honored like the scripts. The grid lists top-level
    // only (spec: dir is flat; the random path's find still recurses).
    readonly property string wallDir: {
        const dir = Quickshell.env("WALLPAPER_DIR");
        return dir ? String(dir) : String(Quickshell.env("HOME")) + "/wallpapers";
    }

    // Marker source: the state file the apply path rewrites on every
    // change — watching it makes the dot hop to a pick only once the
    // service has actually applied it (implicit end-to-end check).
    readonly property string currentWallpaper: currentFile.text().trim()

    implicitWidth: 2 * pad + 4 * tileW + 3 * gap
    implicitHeight: 2 * pad + viewH

    function apply(path: string): void {
        Quickshell.execDetached(["wallpaper-set", path]);
    }

    FileView {
        id: currentFile

        path: {
            const s = Quickshell.env("XDG_STATE_HOME");
            return (s ? String(s) : String(Quickshell.env("HOME")) + "/.local/state")
                + "/wallpaper-current";
        }
        watchChanges: true
        onFileChanged: reload()
        // Missing file (no wallpaper ever set): no marker, nothing to do.
    }

    FolderListModel {
        id: wallModel

        folder: "file://" + root.wallDir
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.gif", "*.bmp"]
        showDirs: false
    }

    // The compositor's keyboard-focus grant can race the Loader; the
    // 50 ms retry mirrors the launcher's focus management.
    Timer {
        interval: 50
        running: true
        onTriggered: grid.forceActiveFocus()
    }

    Text {
        anchors.centerIn: parent
        visible: wallModel.status === FolderListModel.Ready && wallModel.count === 0
        text: "no wallpapers in " + root.wallDir
        color: Theme.on_surface_variant
        font.family: Theme.fontFamily
        font.pixelSize: 16
    }

    GridView {
        id: grid

        x: root.pad
        y: root.pad
        // Exactly 4 columns: floor(width / cellWidth) = 4.
        width: 4 * (root.tileW + root.gap)
        height: root.viewH
        clip: true
        focus: true
        cellWidth: root.tileW + root.gap
        cellHeight: root.tileH + root.gap
        model: wallModel
        keyNavigationWraps: true
        boundsBehavior: Flickable.StopAtBounds

        onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

        Keys.onReturnPressed: {
            if (currentItem)
                root.apply(currentItem.filePath);
        }
        Keys.onEnterPressed: {
            if (currentItem)
                root.apply(currentItem.filePath);
        }
        Keys.onEscapePressed: root.dismissRequested()

        delegate: Item {
            id: tile

            required property int index
            required property string fileName
            required property string filePath

            width: grid.cellWidth
            height: grid.cellHeight

            ClippingRectangle {
                width: root.tileW
                height: root.tileH
                radius: 12
                color: Theme.surface_container_high

                Image {
                    anchors.fill: parent
                    source: "file://" + tile.filePath
                    // Bounded decode: thumbnail resolution, off-thread.
                    sourceSize.width: root.tileW
                    sourceSize.height: root.tileH
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // Broken file: hide — the dim container tile shows.
                    visible: status !== Image.Error
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 24
                    color: Qt.alpha(Theme.surface_container, 0.85)

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        text: tile.fileName
                        color: Theme.on_surface
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        // ElideMiddle keeps numbered suffixes + extension.
                        elide: Text.ElideMiddle
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                // Currently-set wallpaper marker.
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    width: 8
                    height: 8
                    radius: 4
                    color: Theme.primary
                    visible: tile.filePath === root.currentWallpaper
                }
            }

            // Keyboard selection frame, over the clipped content.
            Rectangle {
                width: root.tileW
                height: root.tileH
                radius: 12
                color: "transparent"
                border.width: 2
                border.color: Theme.primary
                visible: tile.GridView.isCurrentItem
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    grid.currentIndex = tile.index;
                    root.apply(tile.filePath);
                }
            }
        }
    }
}
