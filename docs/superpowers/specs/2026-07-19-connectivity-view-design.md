# Island Connectivity View — Design (Track C section)

**Date:** 2026-07-19 · **Status:** approved by jftx · **Master plan:** `docs/plans/quickshell-matugen-migration.md` §Track C · **Epic:** #7 · **Issue:** #15 · **Builds on:** CC v1 (#13, PR #14, squash `3b21c02`)

The first control-center *section*: a radial/orbital connectivity page inside
the CC, from jftx's reference screenshot (2026-07-19 session) — a large
center circle for the connected device, satellite info chips joined by
hand-drawn-style squiggle connectors over faint concentric rings, a
Scan/Switch-View pill at top, an `Internet | Bluetooth` tab bar at the
bottom, and a round power button bottom-right. Themed end-to-end by matugen
like everything else in the island.

## Decisions (jftx, 2026-07-19)

| Question | Decision |
|---|---|
| Entry | **Split CC tiles**: the circular icon keeps toggling the radio; the label area opens the connectivity page on that tile's tab (Wi-Fi tile → Internet tab, BT tile → Bluetooth tab). |
| Integration | **Page inside the CC** — ControlCenter gains root ↔ connectivity page navigation; one island feature (`"control"`), one bind. Escape steps back: connectivity → root → closed. Future sections reuse the page pattern. |
| Tab naming | **"Internet"**, not Wi-Fi (jftx is hardwired; the tab is about connectivity, not one radio). |
| Internet tab | Center = **active connection** (ethernet normally). Chips: interface name, link speed, address, network name. Switch View → **Wi-Fi networks list**; power button toggles the **Wi-Fi radio only** — ethernet is never disconnectable from here. |
| Bluetooth tab | Center = connected device. Chips: MAC, battery % (hidden when the device reports none), **device type** from the BlueZ `icon` string (replaces the reference's Audio Profile chip — quickshell exposes no audio-profile property). Switch View → device list (paired + discovered, connected first). Power button toggles the adapter. |
| Wi-Fi PSK | **Inline password entry in v1** (load-bearing: `nmcli connection show` has zero saved Wi-Fi profiles, so first-time connect must work from the shell). Secured-unknown row expands an inline field; `connectionFailed` → error tint + retry. |
| Scan lifecycle | Scanning (`adapter.discovering` / `wifiDevice.scannerEnabled`, both natively writable) turns ON only while its scan view is visible and is forced OFF on view exit, tab switch, page back, and island collapse. |
| Resources | CC v1 hard rules carry over: no timers, no polling, everything under the expansion Loader, native event-driven modules only, imports confined to the CC subtree. Squiggles/rings are static paints (seeded per chip — they never animate). |
| Peek network slot | **Not this PR.** The hover-peek's reserved right-slot indicator is an always-visible surface with a different resource profile — its own follow-up. |

## Plan-time API facts (verified against installed 0.3.0 qmltypes, 2026-07-19)

- `BluetoothAdapter.discovering` — read/**write** (`setDiscovering`); `enabled` read/write (CC v1). `Bluetooth.defaultAdapter` nullable.
- `BluetoothDevice`: `address`, `name`, `deviceName`, `icon` (BlueZ type string), `state`, `connected`, `paired`, `bonded`, `trusted`, `battery: double` + `batteryAvailable`, methods `connect()/disconnect()/pair()/cancelPair()/forget()`. **No audio-profile property.**
- `Networking.wifiEnabled` read/write; `Networking.devices` is `UntypedObjectModel` → `[...devices.values]` idiom; `DeviceType` = `None | Wifi | Wired`.
- `WifiDevice`: `scannerEnabled` read/**write**, `networks`, `network` (active, nullable). `WifiNetwork`: `signalStrength: double`, `security`, `connected`, `known`, `state`, `connect()`, `connectWithPsk()/requestConnectWithPsk`, `forget()`; `ConnectionFailReason`/`connectionFailed` signal exists for the PSK error path.
- `WiredDevice`: `network`, `linkSpeed: uint`, `hasLink`; `NetworkDevice` base: `type`, `name`, `address: QString`, `connected`, `state`.
- **Impl-verify at plan/build time:** semantics of `NetworkDevice.address` (MAC vs IP — label the chip by what it actually holds); `battery` scale (0–1 vs 0–100); whether `connectionFailed` is a signal on `Network` or surfaced via `state`; BlueZ `icon` → human label mapping (small lookup map, fallback "Device").

## Architecture

Files (flat in `island/`, per convention). `ConnectivityView.qml` is the only
new file that touches backends; everything else is property-in/signal-out:

- **`ControlCenter.qml`** (edit) — gains `page: "root" | "connectivity"` +
  `connectivityTab: "internet" | "bluetooth"`; a Loader swaps root content
  for `ConnectivityView`. Escape on connectivity sets page = root (root
  keeps dismissing the island). Tile split: `ToggleTile` gains an
  `openRequested()` signal from the label area (icon MouseArea keeps
  `toggled()`).
- **`ToggleTile.qml`** (edit) — second MouseArea over the label column
  emitting `openRequested()`; icon circle unchanged.
- **`ConnectivityView.qml`** (new) — page shell: bottom tab bar, power
  button, per-tab view switching (radial ↔ scan), back signal, scan
  lifecycle enforcement (`onVisibleChanged`/`Component.onDestruction`
  force scanning off). Wires Networking/Bluetooth/nothing else.
- **`RadialDeviceView.qml`** (new, reusable) — the orbital composition:
  concentric rings (static Canvas), center circle (icon glyph, title,
  sub-label, soft `primary` radial gradient), chip model
  (`[{icon, value, label, anchor}]`) positioned around it, squiggle
  connectors (static Canvas, quadratic curves with small seeded wobble,
  `outline` color), top pill button (text + sub-text, `toggled` signal).
  Fully backend-free; both tabs mount it.
- **`InfoChip.qml`** (new) — rounded chip: glyph + value + grey sub-label.
- **`WifiNetworkList.qml`** (new) — scan list: SSID, signal glyph
  (strength-bucketed), lock glyph when secured, connected/known styling;
  tap → connect (known/open) or expand inline PSK field (secured unknown):
  password `TextInput` (echoMode Password), Enter submits
  `connectWithPsk`, failure → error tint + "Wrong password?" sub-label,
  field persists for retry. Emits `connectRequested(network, psk)`
  upward; the view shell calls the API.
- **`BtDeviceList.qml`** (new) — device rows: type glyph, name, battery
  when available, state; connected rows first; tap → connect/disconnect
  (pair() first when unpaired). Emits signals; shell calls API.

Sizing: connectivity page ≈ 640 wide × 600 tall; island strip
`implicitHeight` 640 → **760** (`Island.qml`), `implicitWidth` 1200
unchanged; exclusive zone (pill-based) untouched. All sizes re-audited
live on the 5120×1440 monitor.

Layout (reference translation):

```
┌──────────────────────────────────┐
│        [ Scan Devices  ]         │   top pill (Switch View)
│      ~~~~~╱                      │
│  ┌──────┐      ╭──────╮   ┌────┐ │
│  │ MAC  │~~~~ (  icon  )~~│ 90%│ │   chips + squiggles
│  └──────┘     (  name  )  └────┘ │
│               ( state  )         │
│      ~~~~╲    ╰──────╯           │
│      ┌─────────┐                 │
│      │ Headset │                 │   4th chip (BT: device type)
│      └─────────┘                 │
│                                  │
│   [ Internet ][ Bluetooth ] (⏻)  │   tab bar + power
└──────────────────────────────────┘
```

## Behavior

- Tab switch resets that tab to its **radial** view (scan state never
  survives a switch; scanning off).
- Internet radial with no active connection: muted "Disconnected" center;
  chips show placeholders (`—`). Bluetooth radial with nothing connected:
  center = adapter ("Bluetooth" / On|Off); Scan pill becomes the primary
  affordance. Adapter/Wi-Fi hardware absent → tab renders disabled center
  (same greyed language as CC tiles).
- Power button reflects + toggles: BT tab `adapter.enabled`; Internet tab
  `Networking.wifiEnabled` (icon tinted when on, like the reference).
- Multiple connected BT devices: center shows the first; the device list is
  the full picture (v1 keeps it simple).
- External changes (nmcli/bluetoothctl elsewhere) update everything live —
  event-driven bindings, no reopen needed.
- Wallpaper change while open recolors the whole page (Theme.qml watch).

## Verification (scripted-first)

1. Dev-instance (post-flip loop): IPC opens CC; scripted navigation needs
   no clicks — expose test IPC `page(name, tab)` on the island handler
   (permanent, mirrors CC v1's `dnd`); grim screenshots of: Internet
   radial (ethernet chips live), Bluetooth radial (JBL connected: MAC /
   battery / Headset chips), both scan lists, PSK field expanded, empty
   states (BT off).
2. Scan lifecycle: enter Wi-Fi scan → `nmcli -f WIFI g` + qmltypes state
   asserts scanning on; back out → scanning off; collapse island mid-scan
   → scanning off (the load-bearing resource assertion).
3. External flip: `bluetoothctl power off` while radial open → center
   swaps to adapter-off state, no reopen.
4. Regression: CC root unchanged (tiles toggle, sound card), launcher /
   wallpapers / flash / DND intact, Escape chain (connectivity → root →
   closed).
5. `nix flake check` + `trb` → jftx `rb` → live checklist: split-tile
   feel, real Wi-Fi join via PSK (his network, first-time save), JBL
   connect/disconnect from the list, drag/wheel regressions, sizes on the
   ultrawide.

## Out of scope (follow-ups)

Peek right-slot network indicator (own PR, always-visible surface);
Wi-Fi network forget/manage UI; BT pairing PIN/passkey dialogs (devices
requiring codes — v1 covers just-works pairing only); per-device BT
battery polling beyond what BlueZ pushes; connection editing (static IPs,
VPN). Calendar/weather, media card, notification history remain separate
section PRs.
