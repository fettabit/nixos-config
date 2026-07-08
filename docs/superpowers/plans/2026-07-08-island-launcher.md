# Island Launcher Implementation Plan (Track B step 8)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ALT+SPACE morphs the island pill into an inverted-fzf app launcher (search bar at the bottom, fuzzy-ranked results stacking upward), replacing rofi drun.

**Architecture:** `Island.qml`'s placeholder expansion becomes a `Loader` keyed on `expandedFeature`; `Launcher.qml` is a plain Item whose `implicitWidth/Height` follow the result count — the island's existing 320 ms Behaviors animate all geometry ("breathing"). A pure-JS `fuzzy.js` ranks `DesktopEntries` per keystroke. The `GlobalShortcut { name: "launcher" }` in `shell.qml` already exists; only `binds.lua` changes on the Hyprland side.

**Tech Stack:** Quickshell 0.3.0 QML (DesktopEntries, IpcHandler), plain JS (node-testable), Hyprland Lua binds.

**Spec:** `docs/superpowers/specs/2026-07-08-island-launcher-design.md` — read it first; it holds the approved UX decisions and the values table.

## Global Constraints

- **Never run two quickshell instances** (duplicate GlobalShortcut appid:name can crash). Safe restart, exactly this recipe (`pkill -f` matches your own shell — never use it):
  ```bash
  qs kill -c island
  for i in $(seq 1 20); do pgrep -f '[b]in/quickshell -c island' >/dev/null || break; sleep 0.2; done
  WAYLAND_DISPLAY=wayland-1 qs -c island -d -n
  ```
  Capture the "Saving logs to <path>" line — grep that file for `WARN`/`ERROR` after every restart.
- Quickshell does **not** hot-reload QML: restart (recipe above) after every QML edit. No `rb` is needed for QML/JS edits (the config dir is an out-of-store symlink); only Task 4's `binds.lua` change needs jftx to run `rb` (his alias already includes `hyprctl reload`).
- **jftx runs every `rb` himself** — stop and ask, wait for pasted output. Claude may run `nix flake check` and `nixos-rebuild build` freely.
- Theme tokens are snake_case (`Theme.on_surface`); fonts only via `Theme.fontFamily` / `Theme.iconFontFamily`. `import qs.theme` resolves the singleton.
- Screenshots: `WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" <scratchpad>/<name>.png` covers the island area (panel is top-center of the 5120×1440 display). Cursor moves: `hyprctl dispatch 'hl.dsp.cursor.move({ x = X, y = Y })'`.
- Do not add windows or focus grabs: the single `HyprlandFocusGrab` in `Island.qml` must stay the only grab surface (step-7.5 `onCleared` invariant).
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: fuzzy.js scoring library (node-TDD)

**Files:**
- Create: `modules/home/desktop/quickshell/island/fuzzy.test.js`
- Create: `modules/home/desktop/quickshell/island/fuzzy.js`

**Interfaces:**
- Consumes: nothing.
- Produces: `Fuzzy.tier(query: string, name: string) -> int` — `0` empty-query match-all, `1` name-prefix, `2` word-start, `3` substring, `4` scattered subsequence, `-1` no match. Lower is better. Case-insensitive. Task 2 imports it as `import "fuzzy.js" as Fuzzy`.

Plain JS on purpose — **no `.pragma library`** (node cannot parse it, and the single QML consumer makes library sharing moot). The `typeof module` guard makes the same file loadable by both QML and node.

- [ ] **Step 1: Write the failing test**

Create `modules/home/desktop/quickshell/island/fuzzy.test.js`:

```js
// Node smoke test for fuzzy.js (not loaded by QML — nothing imports it).
// Run: node modules/home/desktop/quickshell/island/fuzzy.test.js
const assert = require("node:assert");
const { tier } = require("./fuzzy.js");

// Spec worked examples for query "co"
assert.strictEqual(tier("co", "Code"), 1, "prefix");
assert.strictEqual(tier("co", "VS Code"), 2, "word start");
assert.strictEqual(tier("co", "Discord"), 3, "substring");
assert.strictEqual(tier("co", "Calculator"), 4, "scattered subsequence");
assert.strictEqual(tier("co", "Kitty"), -1, "no match");

// Empty query matches everything at tier 0
assert.strictEqual(tier("", "Anything"), 0, "empty query");

// Case-insensitive both ways
assert.strictEqual(tier("FIRE", "firefox"), 1, "query case folded");
assert.strictEqual(tier("fire", "FIREFOX"), 1, "name case folded");

// Word boundaries: space, dash, underscore, dot
assert.strictEqual(tier("burn", "wallpaper-burn"), 2, "dash boundary");
assert.strictEqual(tier("view", "image_viewer"), 2, "underscore boundary");
assert.strictEqual(tier("org", "chromium.org"), 2, "dot boundary");

// Subsequence must respect letter order
assert.strictEqual(tier("xf", "Firefox"), -1, "subsequence respects order");

console.log("fuzzy.js: all assertions passed");
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node /home/jftx/nixos/modules/home/desktop/quickshell/island/fuzzy.test.js`
Expected: FAIL — `Cannot find module './fuzzy.js'`

- [ ] **Step 3: Write the implementation**

Create `modules/home/desktop/quickshell/island/fuzzy.js`:

```js
// Fuzzy ranking for the island launcher. Plain JS, no `.pragma library`:
// node must parse this file for fuzzy.test.js, and the single QML
// consumer makes library sharing moot.
// Spec: docs/superpowers/specs/2026-07-08-island-launcher-design.md
//
// tier(query, name) -> 0 empty-query match-all; 1 prefix; 2 word start;
// 3 substring; 4 scattered subsequence; -1 no match. Lower is better;
// ties break alphabetically at the call site. Case-insensitive.
function tier(query, name) {
    var q = query.toLowerCase();
    var n = name.toLowerCase();
    if (q.length === 0)
        return 0;
    if (n.indexOf(q) === 0)
        return 1;
    var words = n.split(/[\s\-_.]+/);
    for (var i = 1; i < words.length; i++) {
        if (words[i].indexOf(q) === 0)
            return 2;
    }
    if (n.indexOf(q) !== -1)
        return 3;
    var pos = 0;
    for (var j = 0; j < q.length; j++) {
        pos = n.indexOf(q.charAt(j), pos);
        if (pos === -1)
            return -1;
        pos += 1;
    }
    return 4;
}

// node hook for fuzzy.test.js; inert under QML.
if (typeof module !== "undefined")
    module.exports = { tier: tier };
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node /home/jftx/nixos/modules/home/desktop/quickshell/island/fuzzy.test.js`
Expected: `fuzzy.js: all assertions passed`

- [ ] **Step 5: Commit**

```bash
git add modules/home/desktop/quickshell/island/fuzzy.js modules/home/desktop/quickshell/island/fuzzy.test.js
git commit -m "feature: fuzzy tier ranking for island launcher

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Launcher core + Loader wiring + IPC search hook

**Files:**
- Create: `modules/home/desktop/quickshell/island/Launcher.qml`
- Modify: `modules/home/desktop/quickshell/island/Island.qml` (the `expandedContent` Item block, currently lines ~163–194, and new `search()` function next to `collapse()`)
- Modify: `modules/home/desktop/quickshell/shell.qml` (IpcHandler)

**Interfaces:**
- Consumes: `Fuzzy.tier(query, name) -> int` from Task 1; `Theme.*` tokens; `DesktopEntries.applications` (Quickshell base module).
- Produces:
  - `Launcher { signal dismissRequested(); function setQuery(text: string) }` with content-driven `implicitWidth/Height`.
  - `Island.search(text: string)` — opens the launcher and sets its query.
  - IPC: `qs -c island ipc call island search <text>` (scripted verification for this task and Task 3).

Functional core, plain visuals (Task 3 adds the signature bits): bottom search bar, `BottomToTop` list, fuzzy filter via clear+rebuild, keyboard nav, launch, ESC, breathing implicit size.

- [ ] **Step 1: Create Launcher.qml**

Create `modules/home/desktop/quickshell/island/Launcher.qml`:

```qml
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
```

- [ ] **Step 2: Swap Island.qml's placeholder for the Loader**

In `modules/home/desktop/quickshell/island/Island.qml`, replace the entire `expandedContent` Item block (from `// Placeholder expansion panel; steps 8-11 replace this with a` through its closing brace — currently the last child of `islandRect`) with:

```qml
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
```

Then add the scripted-search entry point to the island root, directly below the existing `collapse()` function:

```qml
    // Scripted-verification path: open the launcher (if needed) and set
    // its query, so filtered states can be screenshotted without a real
    // keyboard. Reached via `qs -c island ipc call island search <text>`.
    function search(text: string): void {
        expandedFeature = "launcher";
        expandedContent.item.setQuery(text);
    }
```

Note: the `width`/`height` bindings on `islandRect` already read `expandedContent.implicitWidth/Height` — a `Loader`'s implicit size mirrors its item's, so they need no change. Assigning `expandedFeature = "launcher"` (not `toggle()`) keeps an already-open launcher open; the synchronous Loader guarantees `item` is non-null on the next line.

- [ ] **Step 3: Add the IPC search function**

In `modules/home/desktop/quickshell/shell.qml`, inside the `IpcHandler { target: "island" }` block, add after the `collapse()` function:

```qml
        function search(text: string): void {
            island.search(text);
        }
```

- [ ] **Step 4: Restart quickshell and check the log**

Run the safe-restart recipe (Global Constraints). Then grep the log path it printed:

```bash
grep -iE "warn|error" <logfile> | grep -v "libpng" | head
```

Expected: no QML errors referencing Launcher.qml, Island.qml, or shell.qml. (If `Quickshell.iconPath` is reported missing on 0.3.0, substitute `source: "image://icon/" + row.entry.icon` in the Image and re-restart.)

- [ ] **Step 5: Verify open, layout, filter, no-match breathing, ESC**

```bash
SP=<scratchpad>; export WAYLAND_DISPLAY=wayland-1
qs -c island ipc call island toggle launcher && sleep 0.8
grim -g "2100,0 920x700" $SP/l-open.png
qs -c island ipc call island search fire && sleep 0.8
grim -g "2100,0 920x700" $SP/l-fire.png
qs -c island ipc call island search zzzzz && sleep 0.8
grim -g "2100,0 920x700" $SP/l-nomatch.png
qs -c island ipc call island search "" && sleep 0.8
qs -c island ipc call island collapse && sleep 0.6
grim -g "2100,0 920x700" $SP/l-collapsed.png
```

Read each PNG. Expected: `l-open` = panel grown from the pill, search bar (magnifier + "Search…") at the BOTTOM, apps alphabetical with A-names at the bottom adjacent to the search bar, 6 rows, bottom row highlighted; `l-fire` = only fuzzy matches for "fire", panel shorter (breathing); `l-nomatch` = search bar alone; `l-collapsed` = clock pill restored. Confirm the pill→panel and panel→pill morphs replayed smoothly (no snap) by watching once via a repeat toggle if needed.

- [ ] **Step 6: Commit**

```bash
git add modules/home/desktop/quickshell/island/Launcher.qml modules/home/desktop/quickshell/island/Island.qml modules/home/desktop/quickshell/shell.qml
git commit -m "feature: island launcher core (inverted-fzf, breathing height)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Signature visuals — smart diff, transitions, morphing highlight, tinted tiles

**Files:**
- Modify: `modules/home/desktop/quickshell/island/Launcher.qml` (refilter, ListView internals, delegate)

**Interfaces:**
- Consumes: Task 2's `Launcher.qml` exactly as written above (function names `refilter`/`rankedMatches`/`launch`, ids `appModel`/`appList`/`row`/`rowMouse`/`iconImg`).
- Produces: no interface changes — visual/behavioral upgrade only. `setQuery`, `dismissRequested`, implicit sizing untouched.

- [ ] **Step 1: Replace the clear+rebuild with the smart diff**

In `Launcher.qml`, replace the whole `refilter()` function with (rankedMatches stays as is):

```qml
    // Smart diff (ported from the reference launcher): mutate appModel
    // into the new match order with remove/move/insert instead of a
    // clear+rebuild, so the ListView's add/remove/displaced transitions
    // animate filter changes instead of the list snapping.
    function refilter() {
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
```

- [ ] **Step 2: Add keyboard-nav tracking + list transitions + morphing highlight**

Add next to the `Timer` (focus) in the root Item — the morphing highlight only "lags" during keyboard nav; during filter diffs it must stick to the moving row:

```qml
    property bool keyboardNav: false

    Timer {
        id: keyboardNavReset

        interval: 500
        onTriggered: root.keyboardNav = false
    }
```

At the top of `refilter()`, insert as the first two lines:

```qml
        root.keyboardNav = false;
        keyboardNavReset.stop();
```

In both `Keys.onUpPressed` and `Keys.onDownPressed`, insert as the first two lines of the handler:

```qml
                    root.keyboardNav = true;
                    keyboardNavReset.restart();
```

In the ListView, delete these three lines from Task 2:

```qml
        // Task 3 replaces this stock bar with the morphing highlight.
        highlightMoveDuration: 0
        highlight: Rectangle {
            radius: 8
            color: Theme.primary
        }
```

and add in their place:

```qml
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
```

- [ ] **Step 3: Upgrade the delegate visuals**

In the delegate, set `z: 1` on the root `Item` (id: `row`, so rows render above the highlight), add `transformOrigin: Item.Center`, and add a hover wash as the FIRST child of the row Item (before the RowLayout):

```qml
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
```

Replace the icon-tile `Rectangle` from Task 2 with the tinted version (selection pop + tint overlay; `iconImg` and the fallback `Text` stay exactly as they were, now joined by the overlay as the tile's last child):

```qml
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
```

Replace the name `Text` with the selected-shift version:

```qml
                Text {
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
                        x: textShift
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
```

- [ ] **Step 4: Restart quickshell, check log, verify visual states**

Safe-restart recipe; grep the new log for `warn|error` (expected: none for our files). Then:

```bash
SP=<scratchpad>; export WAYLAND_DISPLAY=wayland-1
qs -c island ipc call island toggle launcher && sleep 1.2
grim -g "2100,0 920x700" $SP/v-open.png
qs -c island ipc call island search co && sleep 0.9
grim -g "2100,0 920x700" $SP/v-co.png
qs -c island ipc call island search "" && sleep 0.9
grim -g "2100,0 920x700" $SP/v-all.png
qs -c island ipc call island collapse
```

Read each PNG. Expected: `v-open` = tinted icon tiles (or first-letter fallbacks), bottom row on the `Theme.primary` highlight with `on_primary` bold text, 1.15-scaled tile, 4 px scrollbar sliver on the right; `v-co` = ranking per spec (prefix names at the BOTTOM, scattered matches toward the top — e.g. Code below Discord below Calculator when present); `v-all` = full list restored. Between `v-open`→`v-co`, non-matching rows animated out (cannot capture mid-flight reliably; confirm no QML errors and that final states are correct).

- [ ] **Step 5: Verify the keyboard-nav highlight morph does not error**

The stretchy highlight only runs on real key presses, which scripts cannot inject — verify statically that the log stays clean while toggling selection via a second filter round (`search fi` → `search fire` moves currentIndex), then leave the interactive feel to jftx's live test in Task 4.

```bash
qs -c island ipc call island toggle launcher && sleep 0.5
qs -c island ipc call island search fi && sleep 0.5
qs -c island ipc call island search fire && sleep 0.5
qs -c island ipc call island collapse
grep -iE "warn|error" <logfile> | grep -v "libpng" | head
```

Expected: no new warnings/errors.

- [ ] **Step 6: Commit**

```bash
git add modules/home/desktop/quickshell/island/Launcher.qml
git commit -m "feature: launcher signature visuals (morph highlight, transitions, tinted tiles)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: ALT+SPACE bind swap + rb gate + live test

**Files:**
- Modify: `modules/home/desktop/hypr/modules/binds.lua:7` (remove dead `menu` local) and `:25` (rebind)
- Modify: `docs/plans/quickshell-matugen-migration.md` (step-8 status note)

**Interfaces:**
- Consumes: `GlobalShortcut { name: "launcher" }` in `shell.qml` (already exists, untouched); `hl.dsp.global("quickshell:launcher")` — **verified live on this Hyprland 0.55.4 on 2026-07-08**: the Lua wrapper exists and fires the shortcut end-to-end (note: raw `hyprctl dispatch global x` does NOT work on this Lua-native build; the Lua form is required).
- Produces: ALT+SPACE toggles the launcher; rofi drun unbound (rofi files/package stay until step 12).

- [ ] **Step 1: Edit binds.lua**

Remove line 7 entirely:

```lua
local menu = "rofi -show drun"
```

Replace line 25 (`hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))`) with:

```lua
hl.bind(mainMod .. " + SPACE", hl.dsp.global("quickshell:launcher"))
```

- [ ] **Step 2: Validate evaluation**

Run: `nix flake check` (from `~/nixos`)
Expected: clean exit (Lua isn't evaluated by nix, but CLAUDE.md requires the check after edits).

- [ ] **Step 3: Update the master plan doc**

In `docs/plans/quickshell-matugen-migration.md`, step 8's line: append ` **✅ done 2026-07-08** (spec + plan in docs/superpowers/; launcher is inverted-fzf with breathing height per jftx's design).` after the existing step-8 sentence.

- [ ] **Step 4: Commit (bind swap + doc, one commit per master-plan constraint)**

```bash
git add modules/home/desktop/hypr/modules/binds.lua docs/plans/quickshell-matugen-migration.md
git commit -m "feature: ALT+SPACE opens island launcher (rofi drun bind removed)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: STOP — request rb from jftx**

Ask jftx to run `rb` (his alias includes `hyprctl reload`) and paste the output. Do not proceed on errors.

- [ ] **Step 6: jftx live test**

jftx: press ALT+SPACE → island morphs into the launcher, type a few queries (fuzzy feel, highlight morph on arrow keys), Enter launches, ESC/click-outside collapses, ALT+SPACE toggles closed. Confirm rofi no longer appears. Claude: confirm the bind registered via `hyprctl -j binds | grep -A2 -B8 '"key": "SPACE"'` (expect `"dispatcher": "__lua"` on the ALT+SPACE entry) and push:

```bash
git push
```

---

## Self-review notes (already applied)

- Spec coverage: layout/breathing (T2), fuzzy tiers (T1), signature visuals + diffing (T3), bind swap same-commit (T4), IPC verification hook (T2, spec's "scripted input where possible"), first-letter fallback (T2), peek invariants untouched (no new grabs/windows).
- `Quickshell.iconPath` has an inline fallback noted in T2 step 4 in case 0.3.0 lacks it.
- Type consistency: `tier` returns int (0/1/2/3/4/-1); `appModel` roles are `{name: string, entry: DesktopEntry}` in every task; ids `appList`/`appModel`/`row`/`rowMouse`/`iconImg`/`searchField` consistent across T2/T3.
