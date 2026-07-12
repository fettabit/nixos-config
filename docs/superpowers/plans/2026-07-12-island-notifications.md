# Island Notifications Implementation Plan (Track B step 10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The island becomes the session's notification daemon: incoming notifications morph it into a display-only toast (icon + summary + body) that auto-dismisses, and swaync leaves autostart in the same commit.

**Architecture:** A `NotificationServer` in `shell.qml` forwards every notification to `Island.qml`, which owns all toast state (Approach A): copied display fields for rendering, a live object handle for lifecycle, a `notifOut` timer, and a single `pending` slot for arrivals while expanded. The toast is the 5th morph state with priority `expanded > notifying > flashing > peeked > pill`; the `closed` signal is the single cleanup path.

**Tech Stack:** Quickshell 0.3.0 QML (`Quickshell.Services.Notifications`, `Quickshell.Widgets`), Hyprland Lua autostart, `notify-send`/`gdbus` for verification.

**Spec:** `docs/superpowers/specs/2026-07-12-island-notifications-design.md` — read it first; it holds the approved UX decisions and the values table.

**Plan-time facts (verified on-disk/docs 2026-07-12, no impl-verify needed):**
- Installed 0.3.0 qmltypes confirm: `NotificationServer.{actionsSupported,imageSupported,bodySupported,bodyMarkupSupported,trackedNotifications}` + signal `notification(notification)`; `Notification.{id,tracked(rw),expireTimeout,appName,appIcon,summary,body,urgency,image,transient,hints}`, methods `expire()`/`dismiss()`, signal `closed(reason)`; singletons `NotificationUrgency.{Low,Normal,Critical}`, `NotificationCloseReason.{Expired,Dismissed,CloseRequested}`.
- **`Notification.expireTimeout` is a double in SECONDS** (docs: "Time in seconds the notification should be valid for"; wire ms are converted). `notify-send -t 3000` ⇒ `expireTimeout == 3`. No `-t` ⇒ `-1`. Timer intervals are ms: `min(expireTimeout, 15) * 1000`.
- Docs: setting `tracked = false` ≡ `dismiss()`; `expire()` destroys the notification and hints timeout to the sender. Both end in `closed`.
- `Quickshell.iconPath(icon: string, check: bool)` exists (returns `""` for missing icons when `check` is true). `IconImage` and `ClippingRectangle` exist as QML types in `Quickshell.Widgets` (qmldir-registered, not in the C++ qmltypes).
- **swaync ships a D-Bus activation file** (`org.erikreider.swaync.service`: `Name=org.freedesktop.Notifications`) that survives until step 12 removes the `swaynotificationcenter` package (`modules/system/packages.nix:33`). If a notification arrives while *nobody* owns the bus name, D-Bus resurrects swaync. Mitigation is ordering: kill swaync, then start the island (it acquires the name; activation can't fire on an owned name). Until step 12, the post-reboot relaunch recipe is `pkill swaync 2>/dev/null; WAYLAND_DISPLAY=wayland-1 qs -c island -d -n`.
- `grep -rn swaync modules/` today matches ONLY `hypr/modules/autostart.lua:7` (this step deletes it) and nothing else; the package is under its full name `swaynotificationcenter` in `modules/system/packages.nix:33` (stays).

## Global Constraints

- **Never run two quickshell instances** (duplicate GlobalShortcut appid:name can crash). Safe restart, exactly this recipe (`pkill -f` matches your own shell — never use it):
  ```bash
  qs kill -c island
  for i in $(seq 1 20); do pgrep -f '[b]in/quickshell -c island' >/dev/null || break; sleep 0.2; done
  WAYLAND_DISPLAY=wayland-1 qs -c island -d -n
  ```
  The island is **currently not running** — `qs kill` may report no instance; that's fine. Capture the "Saving logs to <path>" line — grep that file for `WARN`/`ERROR` after every restart.
- **swaync must die before the island starts** (D-Bus activation fact above). Never leave a gap where you fire `notify-send` with neither daemon up.
- Quickshell does **not** hot-reload QML: restart (recipe above) after every QML edit. No `rb` is needed for QML or Lua edits pre-verification; Task 3's rb makes it durable.
- **jftx runs every `rb` himself** — stop and ask, wait for pasted output. Claude may run `nix flake check` freely.
- Theme tokens are snake_case (`Theme.on_surface`); fonts only via `Theme.fontFamily`/`Theme.iconFontFamily`. Files in `island/` see each other without imports.
- **Nerd-font glyphs strip in Edit transit** — always write `\uf0XX` escapes in QML strings, never literal glyphs; use python for glyph-adjacent edits.
- Screenshots: `WAYLAND_DISPLAY=wayland-1 grim -g "2100,0 920x700" <scratchpad>/<name>.png`. Cursor moves: `hyprctl dispatch 'hl.dsp.cursor.move({ x = X, y = Y })'` (jftx's real mouse can fight scripted moves — retry once). Park the cursor at `(2560, 900)` when a test needs no-hover.
- **Volume etiquette** (flash-interplay test): record `wpctl get-volume @DEFAULT_AUDIO_SINK@` before, restore after.
- Do not add windows or focus grabs: the single `HyprlandFocusGrab` in `Island.qml` stays the only grab surface.
- `Audio.qml` stays the only PipeWire writer; this step adds no audio code.
- Commits end with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Toast state machine + NotificationToast.qml + NotificationServer + swaync autostart removal (one atomic commit)

**Files:**
- Create: `modules/home/desktop/quickshell/island/NotificationToast.qml`
- Modify: `modules/home/desktop/quickshell/island/Island.qml` (imports; flash comment/guard ~lines 35-46; `onExpandedChanged` ~48-53; `showPeek` ~58; `mask` ~76-78; new state block + Timer + Connections; `islandRect` width/height/radius/border ~121-137; `Pill` opacity ~191; new toast child after `flashView`)
- Modify: `modules/home/desktop/quickshell/shell.qml` (import + `NotificationServer` block)
- Modify: `modules/home/desktop/hypr/modules/autostart.lua` (delete line 7)

**Interfaces:**
- Consumes: `Quickshell.Services.Notifications` API (verified above); existing morph Behaviors, `pill`, `flashView`, `peekView`, `expandedContent` in `Island.qml`.
- Produces:
  - `Island.notify(n)` — the only entry point; called by shell.qml's server, handles defer-while-expanded internally.
  - `Island.notifying: bool` — read by Task 2's verification.
  - `NotificationToast { property string summary; property string body; property string appIcon; property string image }` — pure display, fields in via properties.

- [ ] **Step 1: Create NotificationToast.qml**

Create `modules/home/desktop/quickshell/island/NotificationToast.qml`:

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.theme

// Display-only notification toast content (the island's 5th morph
// state). No input handlers — the toast never takes clicks or keys;
// Island.qml keeps the input mask pill-sized while it shows. Renders
// from fields copied at display time, never the live Notification
// object, so the object can be expired/destroyed mid-fadeout.
// Spec: docs/superpowers/specs/2026-07-12-island-notifications-design.md
Item {
    id: root

    property string summary: ""
    property string body: ""
    property string appIcon: ""
    property string image: ""

    // Notification image (avatar/album art) wins over the app icon;
    // bell glyph when neither resolves. iconPath(_, true) returns ""
    // for names missing from the theme, falling through to the bell.
    readonly property string iconSource: image !== "" ? image
        : appIcon !== "" ? Quickshell.iconPath(appIcon, true) : ""

    implicitWidth: 400
    implicitHeight: 64

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 20
        spacing: 14

        Item {
            // Fixed cell (flash convention): icon presence must not
            // shift the text column.
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32

            ClippingRectangle {
                anchors.fill: parent
                radius: 8
                color: "transparent"
                visible: root.iconSource !== ""

                IconImage {
                    anchors.fill: parent
                    source: root.iconSource
                    asynchronous: true
                }
            }

            Text {
                // nf-fa-bell
                anchors.centerIn: parent
                text: "\uf0f3"
                color: Theme.primary
                font.family: Theme.iconFontFamily
                font.pixelSize: 18
                visible: root.iconSource === ""
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: root.summary
                color: Theme.on_surface
                font.family: Theme.fontFamily
                font.pixelSize: 14
                font.weight: Font.Medium
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            Text {
                Layout.fillWidth: true
                text: root.body
                color: Theme.on_surface_variant
                font.family: Theme.fontFamily
                font.pixelSize: 12
                elide: Text.ElideRight
                textFormat: Text.PlainText
                // Empty body: collapse the row so the summary centers.
                visible: text !== ""
            }
        }
    }
}
```

(The bell MUST be typed as the `\uf0f3` escape — Global Constraints.)

- [ ] **Step 2: Add the toast state machine to Island.qml**

In `modules/home/desktop/quickshell/island/Island.qml`:

**(a)** Add the import (needed for `NotificationUrgency`):

```qml
import Quickshell.Services.Notifications
```

**(b)** Update the flash block: the comment's priority list gains the toast, and `flash()` gains the notifying guard (toast wins the display; the volume change already happened at the caller):

```qml
    // Flash: display-only volume OSD (priority: expanded > notifying >
    // flashing > peeked > pill). Restartable so key repeats hold it
    // open; suppressed while expanded (the panel already shows the
    // change live) and while a toast shows (toast wins the display —
    // the volume still changes underneath).
    property bool flashing: false

    function flash(): void {
        if (expanded || notifying)
            return;
        flashing = true;
        flashOut.restart();
    }
```

**(c)** Below the flash block, add the toast state + functions:

```qml
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
        // expireTimeout is in SECONDS (double, -1 = sender default);
        // Timer.interval is ms. Spec: sender value capped at 15 s,
        // else 5 s normal / 10 s critical.
        notifOut.interval = n.expireTimeout > 0
            ? Math.min(n.expireTimeout, 15) * 1000
            : notifCritical ? 10000 : 5000;
        notifOut.restart();
    }
```

**(d)** Replace the existing `onExpandedChanged` handler (currently the flash-only version) with:

```qml
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
```

**(e)** Change the `showPeek` line to:

```qml
    readonly property bool showPeek: peeked && !expanded && !flashing && !notifying
```

**(f)** Change the `mask` block comment + condition to:

```qml
    // In the display-only states (flash, toast) the input region stays
    // pill-sized: clicks in the extra width pass through (spec).
    mask: Region {
        item: root.flashing || root.notifying ? pill : islandRect
    }
```

**(g)** Next to the `flashOut` Timer, add the toast timer and the two lifecycle connections:

```qml
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
```

(Copied display fields are deliberately NOT cleared on close — the 150 ms fade-out renders them.)

**(h)** In `islandRect`, extend the `width`/`height` chains — `notifying` slots directly under `expanded`:

```qml
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
```

**(i)** The toast is a grown state (64 tall) — change the `radius` line to:

```qml
        radius: root.expanded || root.showPeek || root.notifying ? 18 : pillHeight / 2
```

**(j)** Critical styling — change the `border.color` line to:

```qml
        border.color: root.notifying && root.notifCritical ? Theme.error : Theme.primary
```

**(k)** In the `Pill` child, change the opacity line to:

```qml
            opacity: root.expanded || root.showPeek || root.flashing || root.notifying ? 0 : 1
```

**(l)** After the `VolumeFlash` child, add:

```qml
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
```

- [ ] **Step 3: Add the NotificationServer to shell.qml**

In `modules/home/desktop/quickshell/shell.qml`, add the import:

```qml
import Quickshell.Services.Notifications
```

and, between the last `GlobalShortcut` and the `IpcHandler`, the server:

```qml
    // The island IS the session notification daemon (atomic swaync
    // replacement, spec). Capability flags: display-only toast — no
    // actions, no markup; images and body text render.
    NotificationServer {
        actionsSupported: false
        imageSupported: true
        bodySupported: true
        bodyMarkupSupported: false
        onNotification: n => island.notify(n)
    }
```

- [ ] **Step 4: Remove swaync from autostart.lua**

In `modules/home/desktop/hypr/modules/autostart.lua`, delete line 7 (`hl.exec_cmd("swaync")`). Resulting file:

```lua
-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
	hl.exec_cmd("waybar")
	hl.exec_cmd("awww-daemon")
end)
```

- [ ] **Step 5: Kill swaync, restart quickshell, check the log**

Order matters (D-Bus activation fact — never leave the name unowned when a notification could arrive):

```bash
pgrep -a swaync                      # note what's running (daemon likely up from session start)
pkill swaync || true
qs kill -c island                    # island is currently down — "no instances" is fine
for i in $(seq 1 20); do pgrep -f '[b]in/quickshell -c island' >/dev/null || break; sleep 0.2; done
WAYLAND_DISPLAY=wayland-1 qs -c island -d -n
```

Capture the log path, then:

```bash
grep -iE "warn|error" <logfile> | head
```

Expected: no QML errors referencing NotificationToast.qml, Island.qml, or shell.qml, and **no D-Bus name-acquisition failure** from the notification server (a name failure here means swaync survived the pkill or got reactivated — re-run the pkill + restart pair).

- [ ] **Step 6: Verify bus ownership moved to the island**

```bash
OWNER=$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
  --method org.freedesktop.DBus.GetNameOwner org.freedesktop.Notifications | sed "s/[(',)]//g")
gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
  --method org.freedesktop.DBus.GetConnectionUnixProcessID "$OWNER"
pgrep -f 'bin/quickshell -c island'
```

Expected: the pid from `GetConnectionUnixProcessID` equals the quickshell pid, and `pgrep -a swaync` stays empty.

- [ ] **Step 7: Basic toast verification (grim)**

```bash
SP=<scratchpad>; export WAYLAND_DISPLAY=wayland-1
notify-send "Island test" "hello from the notification server" && sleep 0.5
grim -g "2100,0 920x700" $SP/n-toast.png
sleep 5.5
grim -g "2100,0 920x700" $SP/n-expired.png
notify-send "Summary only" && sleep 0.5
grim -g "2100,0 920x700" $SP/n-nobody.png
sleep 5.5
```

Read each PNG. Expected: `n-toast` = rounded-18 toast (~400×64), bell glyph (notify-send sends no icon), "Island test" over the dimmer body line, primary border, no clock; `n-expired` = clock pill restored (default 5 s timeout elapsed); `n-nobody` = single summary line vertically centered, no body line.

- [ ] **Step 8: Commit (atomic swap)**

```bash
git add modules/home/desktop/quickshell/island/NotificationToast.qml modules/home/desktop/quickshell/island/Island.qml modules/home/desktop/quickshell/shell.qml modules/home/desktop/hypr/modules/autostart.lua
git commit -m "feature: island notification toasts — island is the notification daemon

NotificationServer (actions off, image/body on) + a 5th display-only
morph state; newest-replaces bursts, sender timeout capped 15 s,
critical error border, 30 s deferred slot while expanded. Same commit
drops swaync from autostart — the org.freedesktop.Notifications swap
must be atomic (package stays until step 12).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Behavior verification battery

**Files:** none expected — this task verifies Task 1 against the spec matrix. Any fix is its own small commit (`fix: <symptom>`), re-running the failed check after the restart recipe.

**Interfaces:**
- Consumes: `notify-send` (`-t`, `-u`, `-p`), `gdbus` (sender-side close), existing IPC (`toggle launcher`, `collapse`, `volumeUp`), `Island.notify()` path from Task 1.

- [ ] **Step 1: Timeout matrix**

```bash
SP=<scratchpad>; export WAYLAND_DISPLAY=wayland-1
notify-send -t 3000 "Short" "3 s requested" && sleep 3.5
grim -g "2100,0 920x700" $SP/n-t3-after.png          # pill: 3 s honored
notify-send -t 60000 "Long" "60 s requested, cap 15" && sleep 14
grim -g "2100,0 920x700" $SP/n-t60-at14.png          # toast still up at 14 s
sleep 1.7
grim -g "2100,0 920x700" $SP/n-t60-after.png         # pill: capped at 15 s
```

Expected: `n-t3-after` pill (sender timeout honored), `n-t60-at14` toast still showing, `n-t60-after` pill (cap). Default 5 s was proven in Task 1 Step 7.

- [ ] **Step 2: Critical urgency**

```bash
notify-send -u critical "Disk failing" "urgent body" && sleep 0.5
grim -g "2100,0 920x700" $SP/n-critical.png
sleep 8.5
grim -g "2100,0 920x700" $SP/n-critical-at9.png      # still up (10 s window)
sleep 2
grim -g "2100,0 920x700" $SP/n-critical-after.png    # pill
```

Expected: `n-critical` toast with the border tinted `Theme.error` (visibly different from the primary border in `n-toast`; matugen palette decides the exact hue — compare against `n-toast` from Task 1), still up at 9 s, gone by ~10.5 s.

- [ ] **Step 3: Burst — newest replaces**

```bash
notify-send "First" "should be replaced" && sleep 0.4
notify-send "Second" "should be showing" && sleep 0.5
grim -g "2100,0 920x700" $SP/n-burst.png
sleep 5.5
grim -g "2100,0 920x700" $SP/n-burst-after.png
```

Expected: `n-burst` shows "Second" only (no stacking, no "First" remnant); `n-burst-after` pill (the SECOND notification's full 5 s ran — the timer restarted on replacement). Check the quickshell log afterwards: no binding errors from the replaced notification's destruction (the copied-fields + Connections-retarget design makes this safe; an error here is a regression).

- [ ] **Step 4: Sender-side close**

```bash
ID=$(notify-send -p "Withdraw me" "sender closes this early")
sleep 1
gdbus call --session --dest org.freedesktop.Notifications \
  --object-path /org/freedesktop/Notifications \
  --method org.freedesktop.Notifications.CloseNotification "$ID"
sleep 0.6
grim -g "2100,0 920x700" $SP/n-withdrawn.png
```

Expected: `n-withdrawn` = pill, ~4 s before the 5 s timeout would have fired — the sender's close took the toast down via the `closed` handler.

- [ ] **Step 5: Defer while expanded — fresh and stale**

```bash
qs -c island ipc call island toggle launcher && sleep 0.6
notify-send "Deferred" "arrived while expanded" && sleep 0.5
grim -g "2100,0 920x700" $SP/n-defer-held.png        # launcher intact, NO toast
qs -c island ipc call island collapse && sleep 0.6
grim -g "2100,0 920x700" $SP/n-defer-shown.png       # toast appears on collapse
sleep 5.5
qs -c island ipc call island toggle launcher && sleep 0.6
notify-send "Stale" "will out-age the 30 s window" && sleep 31
qs -c island ipc call island collapse && sleep 0.6
grim -g "2100,0 920x700" $SP/n-defer-stale.png       # pill — dropped
```

Expected: `n-defer-held` = launcher panel, no toast anywhere; `n-defer-shown` = "Deferred" toast; `n-defer-stale` = plain pill (stale notification dismissed, not shown).

- [ ] **Step 6: Flash interplay (volume etiquette applies)**

```bash
V0=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print $2}')
notify-send "Toast holds" "volume changes silently" && sleep 0.4
qs -c island ipc call island volumeUp && sleep 0.4
grim -g "2100,0 920x700" $SP/n-flash-interplay.png
wpctl get-volume @DEFAULT_AUDIO_SINK@                 # moved +5%
sleep 5.5
wpctl set-volume @DEFAULT_AUDIO_SINK@ "$V0"
```

Expected: `n-flash-interplay` shows the TOAST (summary/body), not the volume track — and `wpctl` reports the +5%. The flash was suppressed, the write was not.

- [ ] **Step 7: Peek suppression during toast**

```bash
notify-send "Hover me" "peek must wait" && sleep 0.4
hyprctl dispatch 'hl.dsp.cursor.move({ x = 2560, y = 40 })' && sleep 0.5
grim -g "2100,0 920x700" $SP/n-hover-toast.png       # toast, NOT peek
sleep 5
grim -g "2100,0 920x700" $SP/n-hover-after.png       # peek settles in post-expiry
hyprctl dispatch 'hl.dsp.cursor.move({ x = 2560, y = 900 })'
```

Expected: `n-hover-toast` = toast; `n-hover-after` = peek view (pointer still on the island after expiry). Real-mouse gotcha: if the cursor didn't land, retry the move once.

- [ ] **Step 8: Log sweep**

```bash
grep -iE "warn|error" <logfile> | head -20
```

Expected: nothing new attributable to our files across the whole battery (notably: no `TypeError` from destroyed Notification objects).

---

### Task 3: Validation + master plan marker + rb gate + jftx live test + push

**Files:**
- Modify: `docs/plans/quickshell-matugen-migration.md` (step-10 done marker)

**Interfaces:**
- Consumes: everything above, verified.
- Produces: step 10 durable in the system config; branch pushed.

- [ ] **Step 1: Flake check + repo hygiene**

```bash
cd ~/nixos && nix flake check
grep -rn swaync modules/
```

Expected: flake check clean; the grep returns **only** `modules/system/packages.nix:33` (`swaynotificationcenter` — stays until step 12). The autostart.lua match is gone.

- [ ] **Step 2: Master plan done marker**

In `docs/plans/quickshell-matugen-migration.md`, append to the end of the step-10 line: ` **✅ done 2026-07-12** (spec + plan in docs/superpowers/).`

```bash
git add docs/plans/quickshell-matugen-migration.md
git commit -m "docs: step 10 done marker

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 3: STOP — request rb from jftx**

Ask jftx to run `rb` and paste the output. Do not proceed on errors. Nothing nix-visible changed except the Lua file materialization, so this should be a quiet activation; his alias includes `hyprctl reload`, which re-registers autostart (swaync line now gone — but the running session doesn't restart swaync anyway since `hyprland.start` already fired).

- [ ] **Step 4: jftx live test**

jftx checks, in order:

1. A real app notification (Discord/Telegram/browser — anything) → toast with the app's actual icon, correct summary/body.
2. `notify-send -u critical test` → error-tinted border.
3. Volume keys still flash normally when no toast is up (regression); volume keys DURING a toast change volume without stealing the display.
4. ALT+SPACE launcher and SUPER+V panel unaffected (regression); a notification while one is open appears after ESC.
5. Toast area is click-through: clicks beside/on the toast land on the window below.
6. **Until step 12:** after any reboot, relaunch order is `pkill swaync 2>/dev/null; WAYLAND_DISPLAY=wayland-1 qs -c island -d -n` — if a notification fires before the island is up, D-Bus resurrects swaync (activation file ships with the package until step 12 removes it).

- [ ] **Step 5: Push**

```bash
git push
```

---

## Self-review notes (already applied)

- Spec coverage: server + capability flags (T1 S3), state machine with copied fields / single cleanup path / Connections-retarget guard (T1 S2), toast layout + icon chain + empty-body collapse (T1 S1), morph priority/mask/radius/border/pill/peek-gate/flash-guard (T1 S2 e-l), atomic autostart removal (T1 S4+S8), timeout matrix incl. seconds-unit conversion (T2 S1), critical (T2 S2), burst (T2 S3), sender close (T2 S4), defer fresh+stale (T2 S5), flash interplay (T2 S6), peek suppression (T2 S7), bus-ownership proof (T1 S6), rb gate + live test + push (T3). Values table honored: 400×64/radius 18, 32 px icon cell/clip 8, 14/12 px fonts, 5/10/15 s, 30 s window, 150/320 ms inherited.
- Plan-time verification retired every spec impl-verify: full Notifications API grepped from installed qmltypes; expireTimeout units pinned to seconds from 0.3.0 docs; iconPath/IconImage/ClippingRectangle confirmed (qmldir); the swaync D-Bus activation hazard discovered and encoded as ordering constraints + the until-step-12 relaunch recipe.
- Type consistency: `notify(n)`/`display(n)` defined T1 S2c, consumed by server (T1 S3) and `onExpandedChanged` (S2d); `notifying` read by mask/width/height/radius/border/pill/showPeek/flash-guard (S2 b,e,f,h-k) and toastView opacity (S2l); `NotificationToast.{summary,body,appIcon,image}` (S1) match toastView bindings (S2l); `notifCritical` consumed only by islandRect border (S2j) — deliberately not a toast property.
- No placeholders: every QML/Lua/bash block is complete and paste-ready; expected grim content and exact sleeps specified per check.
