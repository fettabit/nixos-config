# Island Wallpaper Picker — Design (Track B step 11)

**Date:** 2026-07-15 · **Status:** approved by jftx · **Master plan:** `docs/plans/quickshell-matugen-migration.md` §3.5 step 11

`ALT+SHIFT+W` morphs the island into a **thumbnail grid** over
`~/wallpapers`. Clicking or Enter applies the wallpaper immediately —
full matugen retheme cascade, island recoloring live around the open
grid — and the grid **stays open** for comparison hopping. A manual
pick resets the 10-minute rotation countdown. The rofi picker script
survives as a fallback but loses its keybind and its duplicated apply
logic.

## Decisions (jftx, 2026-07-15)

| Question | Decision |
|---|---|
| Selection model | **Apply + stay open**: click/Enter applies instantly (awww + matugen + reload); grid remains for hopping between candidates; ESC or click-outside collapses. |
| Timer interplay | **Manual pick resets the 10-min countdown.** Mechanism: route picks *through* `wallpaper.service` (queue file + `systemctl --user start`), because `OnUnitActiveSec=10min` counts from service activation. **Never restart the timer**: `OnActiveSec=5s` would fire a random pick 5 s later, replacing the manual one. |
| Keyboard | **Arrows + Enter** (GridView built-in nav, wrap on), ESC closes. No type-to-filter — 26 images don't need search (launcher-parity filter explicitly rejected as YAGNI). |
| Approach | **A**: `FolderListModel` + `GridView` in QML; shell's single external call is `wallpaper-set <path>` via `Quickshell.execDetached`. (B: QML-native awww/matugen calls — rejected, third copy of apply logic. C: script-fed model — rejected, FolderListModel does it natively.) |
| `wallpaper-set` semantics | **Front door, not extracted apply** (revises master-plan wording): validates path → writes `wallpaper-next` queue file → starts `wallpaper.service`. The apply block stays in `wallpaper-random.sh` as the repo's **sole copy**. Same dedup goal, plus the timer guarantee the original wording lacked. |
| Placement | `island/WallpaperPicker.qml`, flat — follows where Launcher/VolumePanel actually landed (supersedes the master plan's `wallpapers/` dir). |
| Rofi fallback | `wallpaper-picker.sh` kept, shrunk to menu + `wallpaper-set "$img"` — its duplicated apply block deleted; gains the timer reset for free. ALT+SHIFT+W rebound to the island; script becomes terminal-only. |

## Architecture — shell machinery

- **`wallpaper-set.sh`** (NEW, `writeShellApplication`, runtime inputs
  `coreutils systemd`): arg = image path. Validate readable file (exit 1
  with message otherwise) → `printf` the absolute path to
  `${XDG_STATE_HOME:-~/.local/state}/wallpaper-next` → `systemctl --user
  start wallpaper.service`. No awww/matugen knowledge.
- **`wallpaper-random.sh`** (modified; stays `ExecStart`): before the
  random pick, consume the queue — if `wallpaper-next` exists, read it,
  **delete it immediately**, and use it if the file still exists on disk
  (else fall through to random). Random path unchanged (find over
  `WALLPAPER_DIR`, no-repeat via `wallpaper-current`). Apply block
  (state write → awww daemon safety net → `awww img` → matugen →
  matugen-reload) unchanged and now the only copy in the repo. Queue
  consumption precedes the empty-dir exit so a valid queued pick works
  even if `WALLPAPER_DIR` is empty.
- **`wallpaper-picker.sh`** (modified): rofi menu and the
  basename→path match loop unchanged; the duplicated apply block
  inside the loop becomes `exec wallpaper-set "$img"`. Needs
  `wallpaper-set` in runtime inputs; drops awww/matugen inputs.
- **`wallpaper.nix`**: add the `wallpaper-set` package + wire runtime
  inputs. Service and timer definitions **untouched**.
- **`binds.lua`**: `ALT+SHIFT+W` → `hl.dsp.global("quickshell:wallpapers")`
  (pattern: the ALT+SPACE launcher bind). `ALT+W` untouched.

No-repeat integrity: apply always rewrites `wallpaper-current`, so the
timer's next random pick can't repeat a manual pick, regardless of entry
point.

## Architecture — QML

- **`island/WallpaperPicker.qml`** (NEW): Item with fixed implicit size
  (fits the 1200×640 strip). Inside: `GridView` fed by a
  `FolderListModel` over `~/wallpapers` (`nameFilters` = the scripts'
  six extensions: png/jpg/jpeg/webp/gif/bmp — README.md drops out;
  top-level only, dir is flat). Delegate: `Image` `asynchronous: true`,
  `sourceSize` clamped to cell (bounded off-thread decode — the open
  morph never janks), `PreserveAspectCrop`, rounded clip, filename
  caption on a bottom scrim. Enter/click →
  `Quickshell.execDetached(["wallpaper-set", filePath])`; grid stays
  open. ESC → `dismissRequested` signal (launcher/volume pattern).
  Empty or missing dir → centered "no wallpapers in ~/wallpapers".
  Broken image (`Image.status === Error`) → dimmed tile.
  - **Current-wallpaper marker**: `FileView` (`watchChanges`) on
    `wallpaper-current`; the matching tile gets a corner dot. After a
    pick the marker hops to the new tile when the service writes the
    state file — implicit end-to-end confirmation in the UI.
  - impl-verify: `Qt.labs.folderlistmodel` import availability under
    packaged quickshell; fallback = `Process`-fed `ListModel`
    (approach C machinery, model only — apply path unaffected).
- **`Island.qml`**: `"wallpapers"` case in the Loader switch → new
  `Component` wrapping `WallpaperPicker { onDismissRequested:
  root.collapse() }`. Nothing else — morph engine, focus grab,
  click-outside collapse all inherited.
- **`shell.qml`**: **no change** — the `wallpapers` GlobalShortcut and
  generic IPC `toggle` already exist (step 7 stubs).

## Interaction

- **Open:** ALT+SHIFT+W (or `qs -c island ipc call island toggle
  wallpapers`) → island morphs to the grid (320 ms inherited
  Behaviors); keyboard focus on the GridView (OnDemand focus while
  expanded, as with the launcher).
- **Navigate:** arrows move the highlight (wraps at edges); scroll
  wheel / drag scrolls; a partially visible 4th row advertises scrollability.
- **Pick:** Enter or click applies. Retheme cascade recolors the open
  grid live (`Theme.qml` is already event-driven — zero new code);
  marker dot hops to the picked tile. Grid stays open; repeat picks
  allowed. Rapid double-pick edge: systemd merges a `start` issued
  while the service is still activating, so the second pick may only
  land queued — it applies on the *next* activation (worst case the
  10-min timer, which then applies the queued pick instead of random).
  Accepted; self-heals toward the user's choice.
- **Close:** ESC, ALT+SHIFT+W again (toggle), or click outside
  (HyprlandFocusGrab). Toast/flash interplay: inherited — expanded
  wins the morph; notifications defer to the pending slot (step 10).

## Visuals (Material tokens)

- Chrome inherited from `islandRect` (surface_container, 1 px primary
  border, radius 18 grown state).
- Tiles: 16:9 `PreserveAspectCrop`, clip radius 12; caption scrim
  along the tile bottom (surface_container ≈85 % alpha), filename
  `on_surface` 12 px, ElideMiddle (keeps `pixel2` vs `pixel3` suffixes
  and the extension legible).
- Selection: 2 px `Theme.primary` border on the current-index tile
  (launcher's selected-tile language).
- Current-wallpaper marker: 8 px `Theme.primary` dot, tile top-right.
- Unselected tiles borderless; hover does not move selection (click
  does).

## Values (audit on 5120×1440; single-number tunes expected)

| Value | Initial |
|---|---|
| Tile / clip radius | 272 × 153 (16:9) / 12 |
| Grid | 4 columns, 12 px spacing, wraps on key nav |
| Grid viewport | 1124 × 560 (3 rows + ~65 px sliver of row 4) |
| Panel (24 px padding) | 1172 × 608 (strip max 1200 × 640) |
| Caption / scrim | 12 px on_surface / surface_container ≈85 % |
| Selection border / marker dot | 2 px primary / 8 px primary |
| Crossfade / morph | 200 / 320 ms (inherited) |

## Verification

Pre-rb the new `wallpaper-set` is not on PATH and `ExecStart` still
points at the old store-path `wallpaper-random` (queue file would be
ignored) — so the pipeline halves verify separately:

**Pre-rb (QML, dev symlink hot-reload):**
1. `nix flake check` passes.
2. `qs -c island ipc call island toggle wallpapers` → grim: grid
   renders, thumbnails populate async, marker dot sits on the
   `wallpaper-current` tile, README.md absent.
3. IPC toggle again / `collapse` → clean morph back to pill.
4. Wallpaper change via ALT+W mid-open → grid recolors live (grim).

**Post-rb (pipeline; jftx drives keys, Claude drives CLI):**
5. `wallpaper-set ~/wallpapers/<img>` from a terminal → wallpaper +
   full cascade; `wallpaper-current` contains the path;
   `wallpaper-next` consumed (gone); `systemctl --user list-timers
   wallpaper.timer` shows NEXT ≈ 10 min out.
6. ALT+SHIFT+W → grid; arrows + Enter apply (jftx); marker hops; grid
   stays open; ESC collapses.
7. ALT+W still randoms with no-repeat (state file honored); rofi
   `wallpaper-picker` from a terminal still works end-to-end.
8. Invalid path: `wallpaper-set /nope.jpg` exits 1 with a message, no
   queue file left behind.

## Out of scope

Recursive subdirectory listing in the grid (FolderListModel is
top-level; `~/wallpapers` is flat — the random path's `find` still
recurses), type-to-filter, preview-then-confirm with revert, wallpaper
file management (delete/rename), per-monitor wallpapers, a
pause-rotation mode, video wallpapers (master-plan exclusion), control
center remount (Track C).
