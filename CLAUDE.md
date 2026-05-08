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
Proximity-based party game with five variants. The seam between game and radio is `ProximitySource`:
- `BleProximity` (`flutter_blue_plus` central scan) for production.
- `ManualProximity` (test-only) so the game runs end-to-end on a single device — the lobby and `tag_screen.dart` expose "Touch player X" chips that push fake events.

The `broadcast` callback in `TagSession` is the seam for cross-device messaging; right now the lobby supplies `debugPrint` because BLE peripheral advertising on iOS isn't implemented (flutter_blue_plus is central-only — would need a `CBPeripheralManager` platform channel). Wiring real transport touches no game code.

### Mafia (`lib/games/mafia/`)
Browser-tier social game. The host phone runs the app; everyone else joins from any phone's browser by scanning a QR. Architecture:

- `MafiaEngine` — pure phase machine: lobby → night → dayReveal → dayVote → repeat → gameOver.
- `MafiaServer` — wraps `HostServer`, owns the engine, applies per-guest `join`/`night_action`/`vote` messages, fans out public phase updates, and **sends each player's role privately** via `HostServer.send(GuestId, payload)`. The Flutter host is a special player with id `MafiaServer.hostId` ("host") that doesn't go through WebSocket.
- `mafia_browser.dart` — the **entire browser client** as a const HTML/CSS/JS string served at `/`. Vanilla JS, no build step. When extending Mafia, the browser bundle and the Flutter `mafia_screen.dart` must stay in sync since they consume the same JSON from the server.

### Real-time (`lib/games/../realtime/`)
Self-contained Flame demo. Player + four steering enemies, each driven by a small ECS (`Entity`/`Component`) and a `StateMachine` flipping between Wander and Chase. Single-player only; no network.

### Turn-based (`lib/turnbased/`)
Tic-tac-toe with a minimax AI invoked through `compute()` so the search runs in an isolate.

## HostServer (`lib/social/host_server.dart`)

Spins up `shelf` HTTP + WebSocket on the device's Wi-Fi IP via `network_info_plus`. The served HTML is **swappable** per-game — pass `HostServer(html: ...)` and that string is returned at `/`. Each connected WebSocket gets a stable `GuestId` for the lifetime of the connection; games use `send(GuestId, payload)` for private messages (e.g. role reveals) and `broadcast(payload)` for everything public.

When adding a new browser-tier game, follow the Mafia pattern:
1. Game-specific HTML/JS as a `const String` — served at `/`.
2. A `*Server` class wrapping `HostServer`, mapping inbound JSON commands to engine calls and outbound state to private/broadcast sends.
3. A Flutter screen that displays the QR + acts as the host's player UI.

## Conventions worth keeping

- **No platform shells in git.** `.gitignore` excludes them; everyone runs `flutter create .` after cloning.
- **Engines never touch I/O.** No `Future`, no streams, no plugins inside `*_engine.dart`. This keeps games trivially testable and lets browsers (which can't use Flutter plugins) reuse the same JSON protocol the engine speaks.
- **JSON over the wire is line-oriented, dispatched on `type`.** See `mafia_server.dart`'s `_onMessage` and the browser bundle's `handle()` for the pattern. New message types = add a case on both sides.

## Push status

Active branch is `claude/add-gameplaykit-iphone-6UtKI`. The local git proxy denies pushes with 403, and the GitHub MCP integration in this environment lacks write access to `shadowofthevoid/ubapp` (also 403). To publish: pull the branch locally and push from a machine with credentials, or grant the GitHub App write access.
