# Island Launcher — Design (Track B step 8)

**Date:** 2026-07-08 · **Status:** approved by jftx · **Master plan:** `docs/plans/quickshell-matugen-migration.md` §3.5 step 8

The app launcher renders as an expansion of the dynamic island: ALT+SPACE morphs
the clock pill in place (top-center, growing downward) into a search panel.
Native `Quickshell.DesktopEntries` supplies the apps — no Python fetcher, no
rofi. The reference launcher (ilyamiro `applauncher/appLauncher.qml`) is
consulted for its signature visuals only; its architecture is not ported.

## Decisions (jftx, 2026-07-08)

| Question | Decision |
|---|---|
| Visual flourish | Signature bits — morphing stretchy highlight, pop-in/displaced list transitions, tinted icon tiles. **No ambient orbit blobs.** |
| Matching | Ranked fuzzy (tiers below), not the reference's plain substring. |
| Empty query | Full app list, alphabetical. |
| Layout | **Inverted-fzf:** search bar at the panel's bottom edge, results stack upward (`ListView.BottomToTop`); best match adjacent to the search bar. |
| Visible rows | 6 before scrolling (tune within 5–7 on screen). |
| Height | **Breathing:** panel height follows result count; no fixed-size dead space. |

## Architecture

- `Island.qml`: the placeholder `expandedContent` Item becomes a **`Loader`
  keyed on `expandedFeature`** — `"launcher"` loads the launcher; steps 9–11
  add cases to the same switch; unknown names keep the current placeholder
  behavior until their step lands. The Loader's component is declared inline
  in `Island.qml` (`Component { Launcher { … } }`) so bindings can reach
  `root` for collapse wiring. Fresh instance per open — the query resets by
  construction.
- `island/Launcher.qml`: the panel. Plain Item exposing `implicitWidth` /
  `implicitHeight`; **the island's existing 320 ms width/height Behaviors do
  the breathing** — the launcher only recomputes its implicit size per
  keystroke and never animates its own geometry.
- `island/fuzzy.js`: pure, dependency-free scoring library (`.pragma library`)
  so it is smoke-testable with `node` outside Quickshell.
- `shell.qml`: unchanged — the `GlobalShortcut { name: "launcher" }` →
  `island.toggle("launcher")` wiring already exists.
- `binds.lua`: `ALT+SPACE` rebinds from `exec rofi -show drun` to
  `global, quickshell:launcher`; the rofi bind is removed **in the same
  commit** (master-plan constraint). Requires rb + `hyprctl reload` (hypr Lua
  is store-symlinked); all QML is verifiable before that via
  `qs ipc call island toggle launcher`.

## Data flow

`DesktopEntries.applications` → drop `noDisplay` entries → sort by name
(case-insensitive) → per keystroke: `fuzzy.js` scores every entry, non-matches
drop, survivors order by (tier, name) → **smart-diffed into the ListModel**
(the reference's remove/move/insert algorithm, ported) so QML's add/remove/
displaced transitions animate instead of the list snapping.

Launch: `entry.execute()` then collapse the island. Enter launches the
selection; click launches the clicked row.

## Fuzzy ranking (`fuzzy.js`)

Case-insensitive, matched against the entry **name only** (keywords/comment
deliberately out — predictability over recall; revisit in Track C if wanted).

| Tier | Rule | Example for `co` |
|---|---|---|
| 1 | name starts with query | **Co**de |
| 2 | any word starts with query (boundaries: space `-` `_` `.`) | VS **Co**de |
| 3 | query is a consecutive substring | Dis**co**rd |
| 4 | query is a scattered subsequence (letters appear in order, any gaps) | **C**alculat**o**r |
| — | otherwise | excluded |

Ties within a tier break alphabetically. Empty query = every entry, tier 0,
alphabetical.

## Interaction

- **Focus:** search `TextField` force-focused on load (retry timer if the
  compositor's keyboard-focus grant races the Loader, as in the reference).
  Island already sets `WlrKeyboardFocus.OnDemand` while expanded.
- **Keys:** with `BottomToTop`, model index 0 renders at the bottom. Selection
  defaults to index 0 (bottom, best match). **Up** = index+1 (visually up,
  away from search), **Down** = index−1 (back toward it). Enter launches the
  selection. Typing resets selection to index 0. ESC collapses (existing
  pattern — `Keys.onEscapePressed` moves from the placeholder into the
  launcher). Scroll reveals rows beyond the visible 6.
- **Mouse:** hover shows a soft row highlight (never moves the selection);
  click launches. Click-outside collapse stays with the existing single
  `HyprlandFocusGrab` — **no second grab surface is added**, so the
  `onCleared` peek-invariant holds untouched.
- **No matches:** list empties; panel breathes down to the search bar alone;
  Enter is a no-op.
- **Peek interplay (accepted):** the launcher is tall, so collapsing with the
  pointer parked low can ride expanded→peek→pill (documented step-7.5
  invariant #3). Accepted as-is; if it annoys, gate `peekIn` on
  `!root.expanded` as a deliberate spec change.

## Visuals (signature bits, Material tokens)

- Panel chrome: `Theme.surface_container`, 1 px `Theme.primary` border,
  radius 18 — all inherited from `islandRect`; the launcher draws no own
  background.
- Search row: magnifier nf glyph (`Theme.iconFontFamily`), glyph tints
  `Theme.primary` while the field has focus; placeholder "Search…" in
  `Theme.on_surface_variant`; text `Theme.on_surface`. Hairline separator
  (`Theme.outline_variant` at 50 %) between list and search row.
- Rows: tinted icon tile (40 px, radius 12; icon 24 px via `image://icon/`,
  `Theme.primary` tint overlay 8 % → 25 % when selected, scale-pop 1→1.15
  OutBack on selection; **first-letter fallback** in `Theme.primary` when an
  entry has no icon) + app name (`Theme.fontFamily`; selected row: bold +
  6 px x-shift, `on_primary`-on-`primary` inverted colors like the
  reference's crust-on-mauve).
- Morphing highlight: the reference's stretchy two-edge highlight
  (`Theme.primary`, radius 8; leading edge 250 ms / trailing 450 ms OutExpo)
  during keyboard nav; instant tracking during filter diffs.
- Transitions: pop-in opacity 0→1 + scale 0.88→1 OutExpo on add/populate,
  mirror on remove, x/y slide on displaced. Scrollbar: 4 px `Theme
  .surface_container_highest` sliver, as-needed.

## Values (audit on 5120×1440; single-number tunes expected)

| Value | Initial |
|---|---|
| Panel width | 600 |
| Row height / list spacing | 56 / 4 |
| Search row height | 64 |
| Visible rows max | 6 |
| Icon tile / icon / tile radius | 40 / 24 / 12 |
| Fonts: name / search / glyph | 15 / 16 / 18 px |
| List side margins | 10 |
| Panel max height | 64 + 1 + 6×56 + 5×4 + margins ≈ **425** (< 640 strip budget) |

## Verification (Claude self-drives before requesting rb)

1. `node` smoke-test on `fuzzy.js` tiers (prefix/word/substring/scattered/miss).
2. `qs kill -c island` → relaunch → `qs ipc call island toggle launcher` →
   grim: panel morphs from pill, all apps listed bottom-up, search focused.
3. Filter/launch/ESC/click-outside/no-match paths via grim after scripted
   input where possible; fuzzy *feel* and real typing are jftx's.
4. After jftx rb + `hyprctl reload`: ALT+SPACE toggles; rofi drun gone.

## Out of scope

Ambient blobs (rejected), recents/frecency (Track C candidate, needs
persisted state), keywords/comment matching (Track C candidate), terminal
`runInTerminal` entries beyond whatever `entry.execute()` natively does.
