# Island Wallpaper Picker Implementation Plan (Track B step 11)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ALT+SHIFT+W morphs the island into a 4-column thumbnail grid over `~/wallpapers`; Enter/click applies the wallpaper through a new `wallpaper-set` front door (grid stays open, full retheme cascade, 10-min rotation countdown reset), and the rofi picker survives as a keybind-less fallback.

**Architecture:** Manual picks route *through* `wallpaper.service`: `wallpaper-set <path>` writes a `wallpaper-next` queue file and starts the service; `wallpaper-random.sh` (ExecStart) consumes the queue (else picks random no-repeat) and holds the repo's **only** apply block. Service activation resets `OnUnitActiveSec=10min` for free — never restart `wallpaper.timer` (`OnActiveSec=5s` would fire a random pick 5 s later). QML side: `WallpaperPicker.qml` (GridView + FolderListModel + async bounded-decode thumbnails) as a new island expansion; its single external call is `Quickshell.execDetached(["wallpaper-set", path])`.

**Tech Stack:** bash (`writeShellApplication`), Nix (Home Manager), Quickshell 0.3.0 QML (`Qt.labs.folderlistmodel`, `Quickshell.Io.FileView`, `Quickshell.Widgets.ClippingRectangle`), Hyprland Lua binds.

**Spec:** `docs/superpowers/specs/2026-07-15-wallpaper-picker-design.md` — read it first; it holds the approved UX decisions and the values table.

**Plan-time facts (verified on-disk 2026-07-15, spec impl-verifies retired):**
- `Qt/labs/folderlistmodel` ships in `qtdeclarative-6.11.1` (`/nix/store/dxpl…-qtdeclarative-6.11.1/lib/qt-6/qml/Qt/labs/folderlistmodel`) — the same store path that already serves the shell's working `QtQuick.Controls` import, so `import Qt.labs.folderlistmodel` resolves. The Process-fed-ListModel fallback is NOT needed. `FolderListModel` has `folder`, `nameFilters`, `showDirs`, `count`, and `status` (enum `Null/Ready/Loading`); delegate roles include `fileName` and `filePath`.
- `Quickshell.execDetached(command: list<string>)` and `Quickshell.env(variable)` confirmed in `quickshell-core.qmltypes` (0.3.0).
- `FileView.text()` is reactive: the internal `__text` property has a `textChanged` notify signal, so a binding through `text()` re-evaluates on reload (Theme.qml's `watchChanges` + `onFileChanged: reload()` pattern).
- The island is **currently not running** (post-reboot state); Task 2's restart recipe brings it up.
- Pre-rb, `wallpaper-set` is not on PATH and `wallpaper.service` ExecStart still points at the OLD store-path `wallpaper-random` (queue file ignored) — the pipeline halves verify separately (Task 1 build-gate + Task 3 post-rb battery). Post-rb needs NO island restart for PATH: `execDetached` resolves through the per-user profile bin dir, which is already on the inherited PATH and gains the new binary in place.
- `~/wallpapers` is flat: 26 images (all .jpg) + README.md (filtered out by `nameFilters`).

## Global Constraints

- **Never run two quickshell instances** (duplicate GlobalShortcut appid:name can crash). Safe restart, exactly this recipe (`pkill -f` matches your own shell — never use it):
  ```bash
  pkill swaync 2>/dev/null; qs kill -c island
  for i in $(seq 1 20); do pgrep -f '[b]in/quickshell -c island' >/dev/null || break; sleep 0.2; done
  WAYLAND_DISPLAY=wayland-1 qs -c island -d -n
  ```
  The `pkill swaync` matters until step 12: swaync has a D-Bus activation file — if a notification fires while nobody owns `org.freedesktop.Notifications`, D-Bus resurrects it and the island's server then fails name acquisition. Capture the "Saving logs to <path>" line — grep that file for `WARN`/`ERROR` after every restart.
- Quickshell does **not** hot-reload QML: restart (recipe above) after every QML edit. No `rb` is needed for QML edits pre-verification.
- **jftx runs every `rb` himself** — stop and ask, wait for pasted output. Claude may run `nix flake check` and `nixos-rebuild build` freely.
- Theme tokens are snake_case (`Theme.on_surface`); fonts only via `Theme.fontFamily`/`Theme.iconFontFamily`. Files in `island/` see each other without imports.
- **Nerd-font glyphs strip in Edit transit** — always write `\uf0XX` escapes in QML strings, never literal glyphs (this step's QML needs none — captions are plain filenames).
- Screenshots: `WAYLAND_DISPLAY=wayland-1 grim -g "1950,0 1250x700" <scratchpad>/<name>.png` (picker is 1172 wide, centered on the 5120×1440 monitor → x 1974–3146). Park the cursor at `(2560, 900)` when a test needs no-hover.
- Do not add windows or focus grabs: the single `HyprlandFocusGrab` in `Island.qml` stays the only grab surface. `Audio.qml` stays the only PipeWire writer.
- **Never restart `wallpaper.timer`** in any script or test — `OnActiveSec=5s` fires a random pick 5 s after timer (re)activation.
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: `wallpaper-set` front door + queue consumption + rofi shrink + Nix wiring + rebind (one commit)

**Files:**
- Create: `modules/home/services/scripts/wallpaper-set.sh`
- Modify: `modules/home/services/scripts/wallpaper-random.sh` (full rewrite below)
- Modify: `modules/home/services/scripts/wallpaper-picker.sh` (full rewrite below)
- Modify: `modules/home/services/wallpaper.nix` (add `wallpaper-set`, rewire `wallpaper-picker` inputs)
- Modify: `modules/home/desktop/hypr/modules/binds.lua:48` (rebind ALT+SHIFT+W)

**Interfaces:**
- Consumes: existing `wallpaper.service`/`wallpaper.timer` definitions (untouched), `matugen-reload` (untouched).
- Produces: `wallpaper-set <image-path>` on PATH (exit 1 + stderr message for a non-readable/non-file arg; queue file `${XDG_STATE_HOME:-~/.local/state}/wallpaper-next`; starts `wallpaper.service`). Task 2's QML calls exactly `["wallpaper-set", <abs path>]`.

- [ ] **Step 1: Create wallpaper-set.sh**

Create `modules/home/services/scripts/wallpaper-set.sh` (writeShellApplication adds `set -euo pipefail`; keep `$1` unreferenced until the arg-count check has passed):

```bash
# Front door for manual wallpaper picks (island QML grid, rofi fallback).
# Queues the pick and activates wallpaper.service — the service script
# (wallpaper-random.sh) consumes the queue and holds the repo's only
# apply block, and the activation resets the 10-min rotation countdown
# (OnUnitActiveSec counts from service activation). Never restart
# wallpaper.timer here: OnActiveSec=5s would fire a random pick 5 s
# later, replacing this one.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"

if [ "$#" -ne 1 ]; then
  echo "usage: wallpaper-set <image-path>" >&2
  exit 1
fi
if [ ! -f "$1" ] || [ ! -r "$1" ]; then
  echo "wallpaper-set: not a readable file: $1" >&2
  exit 1
fi

pick="$(realpath "$1")"
mkdir -p "$STATE_DIR"
printf '%s\n' "$pick" > "$STATE_DIR/wallpaper-next"
systemctl --user start wallpaper.service
```

- [ ] **Step 2: Rewrite wallpaper-random.sh — queue consumption + the sole apply block**

Replace the full contents of `modules/home/services/scripts/wallpaper-random.sh` with:

```bash
WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/wallpapers}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE="$STATE_DIR/wallpaper-current"
QUEUE="$STATE_DIR/wallpaper-next"

# A queued manual pick (wallpaper-set front door) beats random. The
# queue file is consumed unconditionally — a stale/vanished path must
# not wedge the next rotation — falling through to random if the image
# no longer exists. Runs before the empty-dir guard so a valid queued
# pick applies even when WALLPAPER_DIR is empty.
pick=""
if [ -f "$QUEUE" ]; then
  queued="$(cat "$QUEUE")"
  rm -f "$QUEUE"
  [ -f "$queued" ] && pick="$queued"
fi

if [ -z "$pick" ]; then
  mapfile -t images < <(find -L "$WALLPAPER_DIR" -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
       -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) | sort)

  n=${#images[@]}
  if [ "$n" -eq 0 ]; then
    echo "no images in $WALLPAPER_DIR" >&2
    exit 1
  fi

  # read last-set image to avoid picking it again back-to-back
  current=""
  [ -f "$STATE" ] && current="$(cat "$STATE")"

  pick="$current"
  if [ "$n" -gt 1 ]; then
    while [ "$pick" = "$current" ]; do
      pick="${images[RANDOM % n]}"
    done
  else
    pick="${images[0]}"
  fi
fi

# ---- apply: the repo's ONLY wallpaper apply path (manual + random) ----

# start the daemon if it is not already up (safety net; autostart normally handles it)
awww query >/dev/null 2>&1 || { awww-daemon >/dev/null 2>&1 & sleep 0.5; }

mkdir -p "$STATE_DIR"
printf '%s\n' "$pick" > "$STATE"

awww img "$pick" \
  --transition-type any \
  --transition-fps 60 \
  --transition-duration 1

# Regenerate the desktop palette from the new wallpaper. Matugen is the
# canonical color source; matugen-reload pushes it to running consumers.
# A matugen failure must not break wallpaper rotation.
matugen image "$pick" --mode dark --prefer saturation || echo "matugen failed for $pick" >&2
matugen-reload
```

- [ ] **Step 3: Rewrite wallpaper-picker.sh — menu only, apply via the front door**

Replace the full contents of `modules/home/services/scripts/wallpaper-picker.sh` with:

```bash
WALLPAPER_DIR="${WALLPAPER_DIR:-$HOME/wallpapers}"

mapfile -t images < <(find -L "$WALLPAPER_DIR" -type f \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
     -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) | sort)

if [ "${#images[@]}" -eq 0 ]; then
  echo "no images in $WALLPAPER_DIR" >&2
  exit 1
fi

# rofi extended dmenu rows: "<label>\0icon\x1f<path>" gives a thumbnail per entry
sel="$(
  for img in "${images[@]}"; do
    printf '%s\0icon\x1f%s\n' "$(basename "$img")" "$img"
  done | rofi -dmenu -i -p wallpaper -show-icons
)" || true

[ -z "$sel" ] && exit 0

for img in "${images[@]}"; do
  if [ "$(basename "$img")" = "$sel" ]; then
    # apply + rotation-countdown reset via the shared front door
    exec wallpaper-set "$img"
  fi
done
```

- [ ] **Step 4: Wire wallpaper-set into wallpaper.nix**

Replace the full contents of `modules/home/services/wallpaper.nix` with (service + timer blocks unchanged; `wallpaper-picker` drops awww/matugen inputs, gains `wallpaper-set`):

```nix
{pkgs, ...}: let
  matugen-reload = pkgs.writeShellApplication {
    name = "matugen-reload";
    runtimeInputs = [pkgs.coreutils pkgs.psmisc pkgs.glib pkgs.systemd pkgs.hyprland];
    text = builtins.readFile ./scripts/matugen-reload.sh;
  };

  # Manual-pick front door: queues the path and activates
  # wallpaper.service (resets the 10-min countdown). The apply block
  # lives in wallpaper-random.sh — the sole copy.
  wallpaper-set = pkgs.writeShellApplication {
    name = "wallpaper-set";
    runtimeInputs = [pkgs.coreutils pkgs.systemd];
    text = builtins.readFile ./scripts/wallpaper-set.sh;
  };

  wallpaper-random = pkgs.writeShellApplication {
    name = "wallpaper-random";
    runtimeInputs = [pkgs.awww pkgs.coreutils pkgs.findutils pkgs.matugen matugen-reload];
    text = builtins.readFile ./scripts/wallpaper-random.sh;
  };

  wallpaper-picker = pkgs.writeShellApplication {
    name = "wallpaper-picker";
    runtimeInputs = [pkgs.coreutils pkgs.findutils pkgs.rofi wallpaper-set];
    text = builtins.readFile ./scripts/wallpaper-picker.sh;
  };
in {
  home.packages = [wallpaper-random wallpaper-picker wallpaper-set matugen-reload];

  systemd.user.services.wallpaper = {
    Unit = {
      Description = "set a random wallpaper with awww";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${wallpaper-random}/bin/wallpaper-random";
    };
  };

  systemd.user.timers.wallpaper = {
    Unit = {
      Description = "set a random wallpaper every 10 minutes";
      PartOf = ["graphical-session.target"];
    };
    Timer = {
      # first run 5s after login, then 10 min after each activation of wallpaper.service.
      # a manual `systemctl --user start wallpaper.service` (the ALT + W bind) re-activates
      # the service, which resets the OnUnitActiveSec countdown to a fresh 10 min.
      # wallpaper-set rides the same mechanism: queue file + service start.
      OnActiveSec = "5s";
      OnUnitActiveSec = "10min";
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
```

- [ ] **Step 5: Rebind ALT+SHIFT+W in binds.lua**

In `modules/home/desktop/hypr/modules/binds.lua`, change line 48 from:

```lua
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("wallpaper-picker"))
```

to (pattern: the ALT+SPACE launcher bind on line 24):

```lua
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.global("quickshell:wallpapers"))
```

The rofi script stays installed as a terminal-run fallback; the running session keeps the old bind until Task 3's rb + hyprctl reload.

- [ ] **Step 6: Validate — flake check + build (shellcheck gate)**

```bash
cd ~/nixos && nix flake check
nixos-rebuild build --flake ~/nixos#blackgarden
```

Expected: both clean. `writeShellApplication` runs shellcheck at **build** time — `nix flake check` alone does not build the scripts, so the `nixos-rebuild build` is the real gate for Steps 1–3. Fix any shellcheck finding and re-run.

- [ ] **Step 7: Commit**

```bash
cd ~/nixos && git add modules/home/services/scripts/wallpaper-set.sh modules/home/services/scripts/wallpaper-random.sh modules/home/services/scripts/wallpaper-picker.sh modules/home/services/wallpaper.nix modules/home/desktop/hypr/modules/binds.lua
git commit -m "feature: wallpaper-set front door — manual picks reset the rotation countdown

Manual picks queue to wallpaper-next and activate wallpaper.service,
whose script consumes the queue (else random no-repeat) and holds the
repo's only apply block — rofi picker loses its duplicated copy and
gains the countdown reset for free. ALT+SHIFT+W rebound to the island
(quickshell:wallpapers); rofi script stays as terminal fallback.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: WallpaperPicker.qml + Island.qml expansion case (one commit)

**Files:**
- Create: `modules/home/desktop/quickshell/island/WallpaperPicker.qml`
- Modify: `modules/home/desktop/quickshell/island/Island.qml` (Loader `sourceComponent` switch ~line 357; new `Component` after `volumePanel` ~line 384)

**Interfaces:**
- Consumes: `wallpaper-set` on PATH (Task 1; dead-letters harmlessly pre-rb), `Theme` singleton tokens, `Island.qml` morph engine + `dismissRequested` convention, `FolderListModel`/`FileView`/`ClippingRectangle`/`execDetached` (plan-time facts).
- Produces: `WallpaperPicker { signal dismissRequested() }` — loaded by the existing `island.toggle("wallpapers")` path (shell.qml GlobalShortcut + IPC already exist; **shell.qml is untouched this step**).

- [ ] **Step 1: Create WallpaperPicker.qml**

Create `modules/home/desktop/quickshell/island/WallpaperPicker.qml`:

```qml
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
```

- [ ] **Step 2: Add the wallpapers case to Island.qml**

In `modules/home/desktop/quickshell/island/Island.qml`:

**(a)** Extend the Loader's `sourceComponent` switch (~line 357):

```qml
            sourceComponent: root.expandedFeature === "launcher" ? launcherPanel
                : root.expandedFeature === "volume" ? volumePanel
                : root.expandedFeature === "wallpapers" ? wallpaperPanel
                : root.expanded ? placeholderPanel : null
```

**(b)** After the `volumePanel` Component, add:

```qml
        Component {
            id: wallpaperPanel

            WallpaperPicker {
                onDismissRequested: root.collapse()
            }
        }
```

- [ ] **Step 3: Restart quickshell, sweep the log**

Restart recipe (Global Constraints; island is currently down, `qs kill` may report no instance):

```bash
pkill swaync 2>/dev/null; qs kill -c island
for i in $(seq 1 20); do pgrep -f '[b]in/quickshell -c island' >/dev/null || break; sleep 0.2; done
WAYLAND_DISPLAY=wayland-1 qs -c island -d -n
```

Capture the log path, then:

```bash
grep -iE "warn|error" <logfile> | head
```

Expected: no QML errors referencing WallpaperPicker.qml or Island.qml (an `import Qt.labs.folderlistmodel` failure would show here — plan-time fact says it won't).

- [ ] **Step 4: Grid render verification (grim)**

```bash
SP=<scratchpad>; export WAYLAND_DISPLAY=wayland-1
cat ~/.local/state/wallpaper-current        # note the current image name
qs -c island ipc call island toggle wallpapers && sleep 0.8
grim -g "1950,0 1250x700" $SP/w-grid.png
```

Read the PNG. Expected: 1172×608 rounded-18 panel, 4-column grid of 16:9 thumbnails with filename captions on bottom scrims, a partially visible 4th row at the bottom edge, a 2 px primary selection frame on the first tile, a small primary dot on the tile matching `wallpaper-current`, **no README.md tile**.

- [ ] **Step 5: Live recolor + marker hop with the grid open**

The running (pre-rb) service machinery still randomizes — perfect for testing FileView reactivity and Theme recolor with the grid up:

```bash
systemctl --user start wallpaper.service && sleep 2.5
grim -g "1950,0 1250x700" $SP/w-recolor.png
cat ~/.local/state/wallpaper-current
```

Read the PNG. Expected vs `w-grid.png`: panel/scrim/selection hues shifted to the new wallpaper's palette (Theme is event-driven), and the marker dot moved to the tile named by the new `wallpaper-current` — proving the FileView watch path end-to-end.

- [ ] **Step 6: Collapse + final log sweep**

```bash
qs -c island ipc call island toggle wallpapers && sleep 0.6
grim -g "1950,0 1250x700" $SP/w-collapsed.png
grep -iE "warn|error" <logfile> | head
```

Expected: pill restored (clock, capsule radius); no new warnings/errors from our files (notably none from FolderListModel or FileView).

- [ ] **Step 7: Commit**

```bash
cd ~/nixos && git add modules/home/desktop/quickshell/island/WallpaperPicker.qml modules/home/desktop/quickshell/island/Island.qml
git commit -m "feature: island wallpaper picker — thumbnail grid morph state

4-column GridView + FolderListModel over ~/wallpapers; arrows + Enter
or click apply via wallpaper-set and the grid stays open for the live
retheme; FileView on wallpaper-current drives the marker dot; ESC or
click-outside collapses. ALT+SHIFT+W lands here post-rb.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: rb gate + post-rb pipeline battery + jftx live test + done marker + push

**Files:**
- Modify: `docs/plans/quickshell-matugen-migration.md` (step-11 done marker)

**Interfaces:**
- Consumes: everything above; jftx's activation.
- Produces: step 11 durable; branch pushed.

- [ ] **Step 1: STOP — request rb from jftx**

Ask jftx to run `rb` and paste the output. Do not proceed on errors. His alias includes `hyprctl reload`, which re-registers binds — ALT+SHIFT+W flips from the rofi script to `global quickshell:wallpapers` at that moment. The already-running island needs **no restart**: the GlobalShortcut has existed since step 7, and `execDetached` finds `wallpaper-set` through the per-user profile bin dir already on PATH.

- [ ] **Step 2: Post-rb CLI battery (Claude self-drives)**

```bash
export WAYLAND_DISPLAY=wayland-1
S=~/.local/state
# invalid path: exit 1, no queue file left behind
wallpaper-set /nope.jpg; echo "exit=$?"; ls "$S/wallpaper-next" 2>&1
# valid pick: full pipeline
cat "$S/wallpaper-current"                       # note pre-pick value
wallpaper-set ~/wallpapers/moon.jpg && sleep 3
ls "$S/wallpaper-next" 2>&1                      # consumed — should NOT exist
cat "$S/wallpaper-current"                       # now the picked path
systemctl --user list-timers wallpaper.timer --no-pager
```

Expected: invalid run prints `wallpaper-set: not a readable file: /nope.jpg`, `exit=1`, no queue file; valid run changes the wallpaper (visible) + cascade fires (island recolors), `wallpaper-next` gone, `wallpaper-current` = `/home/jftx/wallpapers/moon.jpg`, and the timer's NEXT column reads ≈10 min from the pick (not from the last random rotation).

- [ ] **Step 3: jftx live test**

jftx checks, in order:

1. ALT+SHIFT+W → grid opens; arrows move the frame (wrapping), Enter applies — wallpaper + full retheme with the grid open, marker dot hops to the pick; grid stays open; a second pick works; ESC collapses; click-outside collapses.
2. Click a tile → same apply behavior.
3. ALT+W still randoms (no-repeat, never the just-picked image back-to-back).
4. `wallpaper-picker` from a terminal → rofi menu still applies end-to-end (now via the front door, countdown reset included).
5. Regression: ALT+SPACE launcher, SUPER+V volume, notifications unaffected.

- [ ] **Step 4: Master plan done marker**

In `docs/plans/quickshell-matugen-migration.md`, append to the end of the step-11 line: ` **✅ done 2026-07-15** (spec + plan in docs/superpowers/).`

```bash
cd ~/nixos && git add docs/plans/quickshell-matugen-migration.md
git commit -m "docs: step 11 done marker

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Push**

```bash
git push
```

---

## Self-review notes (already applied)

- Spec coverage: front door + queue semantics + no-timer-restart rationale (T1 S1-S2), sole apply block + queue-before-empty-guard (T1 S2), rofi shrink keeping the match loop (T1 S3), nix wiring with input diet (T1 S4), rebind (T1 S5), grid geometry/columns/sliver + bounded async decode + captions ElideMiddle + marker dot + selection frame + empty/broken states (T2 S1), Loader case (T2 S2), apply-and-stay-open + ESC/click-outside (T2 S1 + inherited grab), pre-rb vs post-rb verification split exactly as specced (T2 S3-S6 / T3 S2-S3), invalid-path check (T3 S2), timer NEXT check (T3 S2), rb gate + live test + push (T3). Values table honored: 272×153/12, 4 cols, 1124×560 viewport (grid width 1136 = cells incl. trailing gap; content right edge 1124), 1172×608 panel, 12 px captions, 2 px frame, 8 px dot, inherited 200/320 ms.
- Plan-time verification retired both spec impl-verifies (folderlistmodel present; execDetached/env/FileView-text reactivity pinned from qmltypes).
- Type consistency: `apply(path)` consumed by Keys handlers + MouseArea; delegate `filePath`/`fileName` required-property names match FolderListModel roles; `dismissRequested` matches Island.qml's Component wiring; `wallpaper-set` arg contract identical in QML (T2), rofi (T1 S3), and battery (T3 S2).
- No placeholders: every bash/nix/qml/lua block is complete and paste-ready; expected outputs specified per check.
