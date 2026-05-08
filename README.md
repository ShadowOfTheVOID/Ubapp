# Ubapp

Cross-platform 2D game scaffold built with **Flutter + Flame**, with three modes wired up:

- **Real-time** — `FlameGame` with a `Player` and four `Enemy` components. Player is tap-to-move with seek-style steering; enemies run a `StateMachine` that flips between `WanderState` and `ChaseState` driving the same steering helper.
- **Turn-based** — Tic-tac-toe with an unbeatable minimax AI. Search runs in a Flutter isolate via `compute()` so the UI stays smooth.
- **Social** — Placeholder screen + a `Transport` interface that the offline multiplayer layer plugs into.

## Layout

```
lib/
├── main.dart                       # MaterialApp entry
├── menu/main_menu_screen.dart      # 3 mode buttons
├── realtime/
│   ├── real_time_screen.dart       # hosts GameWidget
│   ├── real_time_game.dart         # FlameGame, spawns world
│   ├── player.dart                 # tap-to-move
│   ├── enemy.dart                  # circle + StateMachine
│   ├── state_machine.dart          # GameState + StateMachine
│   └── steering.dart               # seek() helper
├── turnbased/
│   ├── turn_based_screen.dart      # 3x3 grid + status
│   ├── tic_tac_toe_model.dart      # board logic
│   └── minimax.dart                # depth-tiebroken minimax
└── social/
    ├── social_screen.dart          # placeholder
    └── transport.dart              # interface for offline comms
```

## Run

This repo only contains the Dart source + `pubspec.yaml`. Generate the iOS/Android platform shells once after cloning:

```bash
flutter create . --project-name ubapp --org com.example --platforms=ios,android
flutter pub get
flutter run
```

Requires Flutter 3.19+, Dart 3.3+. Flame `^1.18`.

## Offline multiplayer (TBD)

`lib/social/transport.dart` defines the seam. Pick a Flutter plugin and implement `Transport`:

| Use case | Plugin | Notes |
|---|---|---|
| Low-bandwidth turn-based / chat | `flutter_blue_plus` | BLE GATT, cross-platform, ~7 peripherals per central |
| Higher-bandwidth real-time | `nearby_connections` (Android) | Mixes BLE + Wi-Fi hotspot |
| iOS-specific peer-to-peer | community MultipeerConnectivity plugin | Bridges BLE + AWDL automatically |
| Cross-platform same-room | `flutter_p2p_connection` or hotspot+mDNS | Wi-Fi Direct on Android; iOS needs the host to share a hotspot |

For low-intensity offline games (turn-based, board, casual) BLE is the safe default. Drop in the implementation, then `transport.broadcast(payload)` from the game screens.
