# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project shape

Flutter app that's a collection of small offline party games for same-room play. **Two guest tiers**:

- **App-installed peers** — needed for proximity games (BLE), e.g. tag.
- **Browser-only guests** — connect via QR code to a host phone running an in-app `shelf` HTTP + WebSocket server. Used for social / card / trivia games where no BLE is needed.

The repo is **Dart source only**. The iOS/Android platform shells (`ios/`, `android/`) are intentionally not committed — generate them once after cloning:

```bash
flutter create . --project-name ubapp --org com.example --platforms=ios,android
flutter pub get
flutter run
```

Required tooling: Flutter ≥ 3.27, Dart ≥ 3.6.

## Layout at a glance

```
lib/
├── main.dart, menu/                    # MaterialApp entry + top-level menu
├── games/
│   ├── tag/                            # BLE proximity (5 variants) — app-installed peers only
│   ├── mafia/                          # browser-tier social
│   ├── imposter/                       # browser-tier social (Spyfall-style)
│   └── crazy_eights/                   # browser-tier card game
├── realtime/                           # single-device Flame demo (no network)
├── turnbased/                          # tic-tac-toe + minimax in compute()
└── social/
    ├── host_server.dart                # shelf HTTP + WebSocket, swappable HTML
    ├── transport.dart                  # interface stub for future BLE multiplex
    └── social_screen.dart              # placeholder
```

## Common commands

```bash
flutter pub get                  # install deps
flutter run                      # run on selected device/emulator
flutter analyze                  # static analysis (uses analysis_options.yaml + flutter_lints)
flutter test                     # tests (none yet)
flutter test test/foo_test.dart  # one test file
flutter clean                    # blow away build/ + .dart_tool/
```

Permissions to add to the generated platform shells (BLE for tag, local network for HostServer) are listed in `README.md`.

## Architecture in one paragraph

Each game lives in `lib/games/<name>/` with three layers: a **pure engine** (no Flutter, no I/O), a **session/server adapter** that connects the engine to a transport, and a **screen** that renders state and forwards user actions. Engines are deliberately deterministic state machines so any client (Flutter host, browser guest, future BLE peer) computes the same state from the same ordered events. The transport is hot-swappable via small interfaces — `ProximitySource` for BLE proximity, `HostServer` for WebSocket fan-out — so the same engine and UI work whether you're plumbing real Bluetooth or a manual test stream.

## Per-game wiring

### Tag (`lib/games/tag/`)
Proximity-based party game with five variants. Cross-device wiring has two seams:

**Proximity** — `ProximitySource`:
- `BleProximityRuntime` — combines `BleProximity` (central scan via `flutter_blue_plus`) with `BleAdvertiser` (native peripheral plugin in `lib/native/ble_advertiser.dart`). The lobby's "Use real BLE" toggle constructs this.
- `BleProximity` alone — central scan only, exposed for tests/debug.
- `ManualProximity` (test-only) so the game runs end-to-end on a single device — `tag_screen.dart` exposes "Touch player X" chips that push fake events.

The native side of the BLE advertiser lives in `tooling/ble_native/` (Kotlin for Android, Swift for iOS). It's not auto-installed because the repo doesn't commit platform shells — see `tooling/ble_native/README.md` for the post-`flutter create` copy/paste.

**Game-event transport** — `TagTransport` (`tag_transport.dart`):
- `HostTagTransport(HostServer)` — owns the existing `HostServer` and broadcasts `TagMessage`s to all connected app peers. Inbound `HelloMessage`s populate the host's lobby roster.
- `PeerTagTransport.connect(uri)` — opens one WebSocket to the host. Outbound messages go to the host; inbound stream is the host's broadcasts (so this peer sees its own events echoed back after the host applies them).
- `LoopbackTagTransport` — single-device dev fallback. Sends echo into the inbound stream.

`TagLobbyScreen` has Host and Join modes — host starts `HostServer` + sees peers join via `HelloMessage`; peers paste the host URL and connect. `TagSession.startHosting()` sends a `StartMessage` carrying both peerIds and peerNames, so peers' engines build the same roster from one round trip.

### Browser-tier social games

Three follow the same pattern: host phone runs the app; everyone else joins via QR in any browser.

- **Mafia** (`lib/games/mafia/`) — phases lobby → night → dayReveal → dayVote → repeat → gameOver. Roles: Mafia / Doctor / Villager.
- **Imposter** (`lib/games/imposter/`) — Spyfall-style. All townies see a secret word; the imposter sees only the category. Single vote, then reveal.
- **Crazy Eights** (`lib/games/crazy_eights/`) — classic card game. Standard 52-card deck, 8s wild, first to empty hand wins. Has a `card.dart` value type; screen file uses `import 'package:flutter/material.dart' hide Card; import 'package:flutter/material.dart' as m show Card;` to disambiguate from `material.Card`.

For all three:
- `<game>_engine.dart` — pure phase machine, no I/O. Trivially testable.
- `<game>_server.dart` — wraps `HostServer`, owns the engine, applies per-guest commands, fans out public state, and **sends private payloads** (roles / hands) via `HostServer.send(GuestId, payload)`. The Flutter host is a special player with id `<Server>.hostId == "host"` that doesn't connect over WebSocket.
- `<game>_browser.dart` — the **entire browser client** as a const HTML/CSS/JS string served at `/`. Vanilla JS, no build step. The browser bundle and the Flutter screen must stay in sync since they consume the same JSON from the server.

### Real-time (`lib/realtime/`)
Self-contained Flame demo. Player + four steering enemies, each driven by a small ECS (`Entity`/`Component`) and a `StateMachine` flipping between Wander and Chase. Single-player only; no network.

### Turn-based (`lib/turnbased/`)
Tic-tac-toe with a minimax AI invoked through `compute()` so the search runs in an isolate.

### Minimum players to start a round

| Game | Min | Max |
|---|---|---|
| Tag | 2 | — |
| Mafia | 4 | — |
| Imposter | 3 | — |
| Crazy Eights | 2 | 8 |

These are enforced by `*Engine.canStart`. Useful when seeding a test lobby — fewer players means `canStart` returns false and the host's "Start" button stays disabled.

## HostServer (`lib/social/host_server.dart`)

Spins up `shelf` HTTP + WebSocket on the device's Wi-Fi IP via `network_info_plus`. Default port is `7654`. Binds to `InternetAddress.anyIPv4` so any device on the same Wi-Fi can reach `http://<wifi-ip>:7654/`. The served HTML is **swappable** per-game — pass `HostServer(html: ...)` and that string is returned at `/`. Each connected WebSocket gets a stable `GuestId` for the lifetime of the connection; games use `send(GuestId, payload)` for private messages (e.g. role reveals) and `broadcast(payload)` for everything public.

The browser bundles all open `new WebSocket(\`ws://${location.host}/ws\`)`, which means **plain HTTP only** (no TLS). That's correct for LAN play but means the host phone can't tunnel through anything that requires HTTPS.

When adding a new browser-tier game, follow the Mafia pattern:
1. Game-specific HTML/JS as a `const String` — served at `/`.
2. A `*Server` class wrapping `HostServer`, mapping inbound JSON commands to engine calls and outbound state to private/broadcast sends.
3. A Flutter screen that displays the QR + acts as the host's player UI.

## Conventions worth keeping

- **No platform shells in git.** `.gitignore` excludes them; everyone runs `flutter create .` after cloning.
- **Engines never touch I/O.** No `Future`, no streams, no plugins inside `*_engine.dart`. This keeps games trivially testable and lets browsers (which can't use Flutter plugins) reuse the same JSON protocol the engine speaks.
- **JSON over the wire is line-oriented, dispatched on `type`.** See `mafia_server.dart`'s `_onMessage` and the browser bundle's `handle()` for the pattern. New message types = add a case on both sides.

## Pitfalls worth knowing

- **`Card` name collision in Crazy Eights.** `lib/games/crazy_eights/card.dart` defines a `Card` value type for a playing card. The screen file uses `import 'package:flutter/material.dart' hide Card; import 'package:flutter/material.dart' as m show Card;` so widget Cards are written `m.Card(...)` and game cards are written `Card(...)`. Don't drop the `hide`/`show` pair when editing.
- **iOS BLE peripheral isn't implemented.** `flutter_blue_plus` is central-only. To make tag actually work cross-device on iOS you need a `CBPeripheralManager` platform channel (Android can use a peripheral plugin). The `ProximitySource` interface is the seam — the rest of the tag stack stays unchanged.
- **Browser bundle ↔ Flutter screen are in an implicit contract.** Both consume the same JSON the server emits. When you add a message type, add a `case` on both sides or one side will silently drop events.
