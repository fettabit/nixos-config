# Island hover peek — design spec

**Date:** 2026-07-06 · **Branch:** `feat/quickshell-core` (Track B, issue #6) · **Status:** approved by jftx, pre-implementation
**Amends:** step 7 of `docs/plans/quickshell-matugen-migration.md` (island pill + morph engine, shipped `00bd7ba`/`e42ad30`)

## What changes and why

The collapsed pill currently shows the clock *and* the now-playing track title. jftx wants the pill quieter and the information richer: the pill shows **only the clock**, and **hovering it morphs the island open** into a "peek" — a wide stadium showing now-playing (album art, title, artist), a large clock with the date, and (later, Track C) network status. Reference aesthetic: iOS-style dynamic island status view (album art left, clock + date center, status icons right).

Two positioning fixes ride along: more air between the screen edge and the pill, and a tighter gap between the pill and the tiled windows below it.

## Decisions (from the 2026-07-06 interview)

| Question | Decision |
|---|---|
| Hover with nothing playing | **Always expand** — peek shows clock/date alone (narrower). The audio block appears only when media plays. |
| Architecture | **Third state** on the existing morph engine: pill / peek / expanded. Not a feature slot (would drag in focus-grab/keyboard machinery wrong for hover), not a second window (violates one-window-one-animation-system). |
| "2 notches up from the bottom" | Windows come up closer below the pill — shrink the exclusive-zone bottom pad. |
| Network in the peek | Later (Track C). The peek's right slot stays intentionally empty for it. |

## State machine (`island/Island.qml`)

```
pill      --hover in  (150 ms intent delay)-->  peek
peek      --hover out (250 ms grace)        -->  pill
any state --GlobalShortcut/IPC toggle       -->  expanded
expanded  --ESC / click-outside / toggle    -->  pill (peek re-engages if pointer still on island)
```

- New `property bool peeked`, driven by a `HoverHandler` on `islandRect` debounced through a `Timer` (150 ms in / 250 ms out — prevents flicker when the mouse grazes the screen top in passing; both tunable).
- Precedence: `expandedFeature !== ""` wins over `peeked`; hover does nothing while expanded.
- **Peek is display-only.** `HyprlandFocusGrab.active` and `WlrKeyboardFocus.OnDemand` remain tied to `expanded` only — hover must never steal keyboard focus. No click-outside logic for peek; leaving the rect collapses it.
- The input mask already tracks `islandRect` (`Region { item: islandRect }`), so hover detection and the growing hover target come for free as the rect animates.

## Peek content (new file `island/PeekView.qml`)

Row layout, content-driven size (`implicitWidth`/`implicitHeight`, like the placeholder panel):

- **Left — audio block, visible only while a player is `Playing`:** album art from `player.trackArtUrl` in a rounded `ClippingRectangle` (Quickshell.Widgets); if the URL is empty, a music-note glyph placeholder in the same box. Beside it a two-line stack: track title over artist (`trackArtist`), each width-capped and elided.
- **Center:** large clock (~30 px) over the date, `Qt.formatDateTime(clock.date, "ddd, MMM d")`, own `SystemClock` (Minutes precision).
- **Right:** empty, reserved for Track C network status.

The `Mpris.players` "first playing player" lookup moves out of `Pill.qml` into `PeekView.qml`.

## Pill slims down (`island/Pill.qml`)

Clock only. The music icon and track title are removed; the pill no longer changes width with playback.

## Geometry

| Value | Before | After |
|---|---|---|
| `margins.top` (screen edge → pill) | 12 | **20** |
| Exclusive-zone bottom pad (pill → tiled windows) | +10 | **+4** |
| Peek size (media playing) | — | ≈ 640 × 104, content-driven |
| Peek size (idle) | — | ≈ 300 × 104, content-driven |
| Peek radius | — | `height / 2` (stadium, per reference; expanded panel keeps 24) |

All sizes audited on-screen at 5120×1440; single-number tunes expected.

## Animation

Nothing new: the existing 320 ms `OutCubic` Behaviors on `islandRect` width/height/radius carry the pill↔peek morph. Pill, peek, and expanded contents cross-fade on opacity exactly as pill/placeholder do today.

## Verification (Claude self-drives)

1. `qs kill -c island` → wait for pgrep clear → `qs -c island -d -n` (0.3.0 has no QML hot-reload).
2. `hyprctl dispatch movecursor <pill-center>` → wait past debounce → full-screen `grim -o DP-3` → Read PNG: peek rendered, layout right.
3. Move cursor away → grim → pill restored, clock-only.
4. Expansion-beats-peek: IPC-toggle a feature while hovering — expanded panel shows, no fight.
5. Recolor during peek (`ALT+W` or wallpaper-random) — colors update live.
6. Geometry: windows tile 4 px below the pill, 20 px top margin. `nix flake check`.
7. jftx feel-test: morph smoothness, debounce timing, sizes.

## Plan-doc amendment

`docs/plans/quickshell-matugen-migration.md`: step-7 addendum noting the peek state, and "network status in the island peek's right slot" added to Track C.

## Out of scope

Network/Wi-Fi widget (Track C), battery (no battery on this desktop), any click action on the pill or peek, notification/launcher/volume work (steps 8–11 unchanged).
