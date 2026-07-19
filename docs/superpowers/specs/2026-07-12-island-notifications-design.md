# Island Notifications — Design (Track B step 10)

**Date:** 2026-07-12 · **Status:** approved by jftx · **Master plan:** `docs/plans/quickshell-matugen-migration.md` §3.5 step 10

Incoming desktop notifications render as a **toast**: a 5th display-only
island morph state (app icon + summary + body) that auto-dismisses on a
timeout. The island becomes the session's notification daemon via
Quickshell's `NotificationServer`; the same commit removes swaync from
`autostart.lua` — the swap must be atomic because both claim
`org.freedesktop.Notifications` on the bus (swaync package + files stay
until step 12).

## Decisions (jftx, 2026-07-10 / 2026-07-12)

| Question | Decision |
|---|---|
| Interaction | **Display-only**, like the flash: no clicks, no actions, no keyboard. The input mask stays pill-sized while the toast shows — clicks in the toast's extra area pass through. |
| Bursts | **Newest replaces current** — no queue, no stacking. The replaced notification is expired so its sender gets a proper close. |
| Timeout | Sender's `expireTimeout` when > 0, **capped at 15 s**; otherwise 5 s normal / **10 s critical**. |
| Critical styling | `islandRect` border tints `Theme.error` (instead of `Theme.primary`) while a critical toast shows. Content otherwise identical. |
| While expanded | Toast is **deferred** into a single `pending` slot (newest wins) and shown on collapse if still **< 30 s old**; otherwise dropped. Expanding *during* a toast dismisses it (it does not re-queue). |
| Flash interplay | Toast wins the display; volume still changes underneath (Audio writes are independent). `flash()` no-ops while notifying; an in-flight flash is cleared when a toast lands. |
| Server capabilities | `actionsSupported: false`, `imageSupported: true`, `bodySupported: true`, `bodyMarkupSupported: false` — senders are told to send plain text; the body renders `Text.PlainText`. |
| Architecture | **Approach A**: all toast state lives in `Island.qml` (`notif*` fields, `notifying`, `notifOut` timer, `pending` slot); `shell.qml` only hosts the server and forwards. Morph priority `expanded > notifying > flashing > peeked > pill`. |
| Rendering source | The toast renders from **fields copied at display time** (summary, body, icon, critical), not the live `Notification` object — the object can be expired/destroyed mid-fadeout without binding errors. Lifecycle (`tracked`, `expire()`, `closed`) still uses the object. |
| swaync | `hl.exec_cmd("swaync")` (autostart.lua:7) removed in the same commit that adds the server. Package + config files remain until step 12. |
| Keybinds | **None** — nothing in binds.lua changes this step. |

## Architecture

New file in `modules/home/desktop/quickshell/island/` (flat, per
convention — supersedes the master plan's `notifications/NotificationView.qml`):

- **`NotificationToast.qml`** — toast content, `VolumeFlash.qml`'s sibling
  in every way: display-only Item, no input handlers, ~400×64. RowLayout of
  a fixed 32 px icon cell (rounded-clip 8) + a text column: summary
  (`on_surface`, 14 px, ElideRight) over body (`on_surface_variant`, 12 px,
  ElideRight, PlainText). Empty body ⇒ the column collapses and the summary
  centers alone. Icon fallback chain: notification `image` → `appIcon` via
  `Quickshell.iconPath()` → bell glyph `\uf0f3` (nf-fa-bell) in `Theme.primary`. Renders
  from copied-field properties passed in by Island.qml — no `Notification`
  object reference inside.

Changed files:

- **`Island.qml`** — new state: `notifying` bool, copied display fields
  (`notifSummary`, `notifBody`, `notifIcon`/`notifImage`, `notifCritical`),
  a live-object handle for lifecycle, `notifOut` Timer, `pending` +
  `pendingAt` for the deferred slot.
  - `notify(n)` public entry (called by shell.qml): expanded ⇒ stash in
    `pending` (newest wins) with timestamp; else display.
  - Display path: expire any currently-shown notification, clear any
    active flash, copy fields, `n.tracked = true`, `notifying = true`,
    `notifOut.interval = timeoutFor(n)`, restart.
  - `timeoutFor(n)`: `n.expireTimeout > 0 ? min(n.expireTimeout, 15000)
    : n.urgency === critical ? 10000 : 5000` — expireTimeout is in
    **milliseconds** on this build (0.3.0 docs claim seconds; a
    `notify-send -t` probe proved otherwise, 2026-07-12).
  - `notifOut` fires ⇒ `n.expire()`; the object's `closed` signal is the
    **single cleanup path** (`notifying = false`, handle released) whether
    closure came from our timer or from the sender. The handler must
    verify the closing object is still the displayed handle — on a burst
    the replaced notification's `closed` can arrive after the new toast
    is already up and must not tear it down. A `closed` on the pending
    notification drops the slot.
  - `onExpandedChanged`: expanding expires a showing toast (no re-queue);
    collapsing shows `pending` if `now − pendingAt < 30 s`, else drops it.
  - Morph chain gains `notifying` above `flashing` in width/height;
    `radius` joins the grown states (`expanded || showPeek || notifying ?
    18 : pillHeight/2`); `border.color` tints `Theme.error` when
    `notifying && notifCritical`; mask stays pill-sized (`flashing ||
    notifying ? pill : islandRect`); pill opacity hides during `notifying`;
    `showPeek` gains `&& !notifying`; `flash()` gains a `notifying` guard.
  - Toast view instance mirrors `flashView`: `anchors.centerIn`, 150 ms
    opacity crossfade, visible when opacity > 0.
- **`shell.qml`** — `NotificationServer` with the capability flags above;
  `onNotification: n => island.notify(n)`. No new shortcuts, no new IPC —
  `notify-send` is the external driver for all verification.
- **`autostart.lua`** — line 7 `hl.exec_cmd("swaync")` deleted.
- **Master plan** — step 10 line and the repo-layout
  `notifications/NotificationView.qml` line rewritten to match this spec
  (done in this commit).

## Interaction

- **Arrival (collapsed/peek/flash):** island morphs to the toast (320 ms
  existing Behaviors). Peek and flash yield — priority chain. Hovering
  during a toast does not peek; when the toast expires with the pointer on
  the island it settles into peek naturally (flash precedent).
- **Arrival (expanded):** panel/launcher stays; toast deferred to `pending`
  (newest wins). On collapse: shown if < 30 s old, dropped otherwise.
- **Burst:** each new toast replaces the current one (previous is expired),
  timer restarts with the new notification's own timeout.
- **Sender close:** apps that withdraw their notification (`closed` signal)
  take the toast down immediately.
- **Volume keys during a toast:** volume changes and is visible in
  `wpctl`; no flash appears; the toast keeps the display.
- **No user input:** clicks pass through (pill-sized mask), ESC does
  nothing (no keyboard focus in any display-only state).

## Visuals (Material tokens)

- Chrome inherited from `islandRect`: `surface_container`, 1 px border —
  `Theme.primary` normal, `Theme.error` critical.
- Toast is a **grown** state: radius 18 (peek/expanded vocabulary), not the
  pill capsule.
- Summary `Theme.on_surface` 14 px; body `Theme.on_surface_variant` 12 px;
  both single-line ElideRight, fixed cells so text never shifts.
- Icon cell fixed 32 px (flash's fixed-cell trick): image/appIcon
  rounded-clip radius 8; bell fallback glyph in `Theme.primary`, 18 px.

## Values (audit on 5120×1440; single-number tunes expected)

| Value | Initial |
|---|---|
| Toast size / radius | ~400 × 64 / 18 |
| Icon cell / clip radius / fallback glyph | 32 px / 8 / 18 px |
| Summary / body font | 14 px / 12 px |
| Timeouts (normal / critical / sender cap) | 5000 / 10000 / 15000 ms |
| Pending freshness window | 30 000 ms |
| Crossfade / morph | 150 / 320 ms (inherited) |

## Verification (Claude self-drives before requesting rb)

The island is currently **not running** — step 0 is the relaunch. All
steps are pre-rb; `notify-send` drives everything, no new IPC hooks.

0. `pkill swaync` (if running); relaunch:
   `WAYLAND_DISPLAY=wayland-1 qs -c island -d -n`.
1. `notify-send "Test" "body"` → grim shows toast (icon fallback, summary,
   body); grim again after ~5.5 s shows the pill restored.
2. `notify-send -u critical …` → error-tinted border (grim); still up at
   9 s, gone by ~10.5 s.
3. `notify-send -t 3000 …` → gone by 3.5 s; `-t 60000` → gone by ~15.5 s
   (cap).
4. Burst: two sends back-to-back → second grim shows the newer content
   only.
5. Defer: IPC-open the launcher → `notify-send` → no toast (grim, panel
   intact) → IPC collapse → toast appears. Repeat with a > 30 s wait
   before collapse → no toast.
6. Flash interplay: `notify-send` then IPC `volumeUp` mid-toast → toast
   still displayed (grim), `wpctl get-volume` moved.
7. Peek suppression: cursor onto the island mid-toast → no peek until
   expiry (grim pair; jftx's real mouse fights `hl.dsp.cursor.move` —
   retry once).
8. `nix flake check` passes; repo grep confirms the autostart swaync line
   is gone.
9. After jftx rb + reboot (may ride along with later steps): no swaync
   process in the session, `notify-send` still lands on the island,
   `journalctl --user` shows no bus-name conflict.

## Out of scope

Action buttons and inline reply (`actionsSupported: false` — revisit only
if missed), notification history / notification center and DND (Track C
control center absorbs both), toast grouping/stacking beyond
newest-replaces, notification sounds, live-updating a displayed toast on
`notify-send -r` replacement (copied fields render the arrival-time
content; acceptable edge), swaync package + config file removal and the
systemd service flip (step 12).
