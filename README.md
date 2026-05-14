# Ubapp

A collection of small offline party games for same-room play. **Native iOS
(SwiftUI) and native Android (Kotlin/Compose)** — no shared runtime, no
cross-platform framework.

Two guest tiers:

- **App-installed peers** — needed for proximity games (BLE), e.g. tag.
- **Browser-only guests** — connect via QR code to a host phone running an
  in-app HTTP + WebSocket server. Used for social / card / trivia games where
  no BLE is needed.

## Layout

```
ios/                                    # SwiftUI app (Xcode 16, no xcodegen)
├── Ubapp.xcodeproj/project.pbxproj     # hand-written, uses filesystem-synchronized group
└── Ubapp/
    ├── App/                            # UbappApp.swift, Info.plist
    ├── Menu/                           # MainMenuView
    ├── Games/<Name>/                   # one folder per game
    ├── Social/                         # HostServer (Network.framework)
    └── Tutorials/                      # tutorial copy + opt-in vote (TODO)

android/                                # Gradle/Kotlin DSL, Jetpack Compose
├── settings.gradle.kts, build.gradle.kts
└── app/
    └── src/main/
        ├── AndroidManifest.xml
        ├── java/com/example/ubapp/
        │   ├── MainActivity.kt
        │   ├── menu/                   # MainMenu
        │   ├── games/<name>/           # one package per game
        │   └── social/                 # HostServer (NanoHTTPD-WebSocket)
        └── res/
```

## Running

### iOS

Requires Xcode 16 (the project uses `PBXFileSystemSynchronizedRootGroup` so
new Swift files under `ios/Ubapp/` are picked up automatically — no need to
edit `project.pbxproj`).

```
open ios/Ubapp.xcodeproj
```

Build target: iOS 17+.

### Android

Requires Android Studio (Iguana or newer) with AGP 8.7 and Kotlin 2.0.

```
cd android
# Generate the Gradle wrapper once if missing:
gradle wrapper --gradle-version=8.10
./gradlew :app:installDebug
```

Min SDK: 26. Target SDK: 35.

## Architecture in one paragraph

Each game lives in `<platform>/.../games/<name>/` with three layers: a **pure
engine** (no UI, no I/O — just a deterministic state machine), a
**session/server adapter** that connects the engine to a transport, and a
**view/screen** that renders state and forwards user actions. Engines are
deliberately deterministic so any client (Swift host, Kotlin host, browser
guest, future BLE peer) computes the same state from the same ordered events.
The transport is hot-swappable via small interfaces — `ProximitySource` for
BLE proximity, `HostServer` for WebSocket fan-out — so the same engine and UI
work whether you're plumbing real Bluetooth or a manual test stream.

## Migration status (Flutter → native)

This branch began life as a Flutter/Dart codebase. The migration is in
progress; the table below tracks what's done per game.

| Game           | iOS engine | iOS view    | Android engine | Android view |
|----------------|:----------:|:-----------:|:--------------:|:------------:|
| Mafia          | done       | partial     | done           | placeholder  |
| Werewolf       | done       | placeholder | done           | placeholder  |
| Imposter       | done\*     | placeholder | done\*         | placeholder  |
| Codenames      | done\*     | placeholder | done\*         | placeholder  |
| Crazy Eights   | done       | placeholder | done           | placeholder  |
| Tag (BLE)      | done       | placeholder | done           | placeholder  |
| Tic-Tac-Toe    | done       | done        | done           | done         |
| Connect Four   | done       | placeholder | done           | placeholder  |

\* word/category banks are stubs — the original Flutter banks need
re-porting to `ImposterWords` and `CodenamesWords`.

### Still to port

- **Browser bundles**: the rich HTML/CSS/JS strings (Mafia ~580 lines,
  similar for each browser-tier game) that previously lived in
  `<game>_browser.dart`. The Mafia bundle has a working join+log stub; the
  others need the full lobby → game → reveal flow translated.
- **Phase-specific UIs** for each social/card screen — night targets, day
  votes, reveals, game-over, card layouts, etc.
- **BLE proximity** (`tag/`): on iOS, `CBCentralManager` for scan and
  `CBPeripheralManager` for advertise. On Android, the standard
  `android.bluetooth.le` APIs. The pure engine + protocol are ready.
- **Tutorial opt-in vote** (`tutorials/`): scaffolding only. Original lived
  in `lib/tutorials/`.
- **Real-time** (`realtime/`): SpriteKit on iOS, Compose Canvas on Android.
- **Connect Four AI**.

## Conventions worth keeping

- **Engines never touch I/O.** No async, no streams, no system APIs inside
  `*Engine.swift` / `*Engine.kt`. This keeps games trivially testable and
  lets browsers (which can't use platform plugins) reuse the same JSON
  protocol the engine speaks.
- **JSON over the wire is line-oriented, dispatched on `type`.** When you
  add a message type, add a handler on both sides (server adapter + browser
  bundle / other peers).
- **iOS uses a hand-written `project.pbxproj`** with a filesystem-synchronized
  root group (Xcode 16 feature). Adding new Swift files never requires
  editing the project file — just drop them under `ios/Ubapp/`.

## Permissions

- iOS: `Info.plist` declares Bluetooth (central + peripheral) and local
  network usage strings.
- Android: `AndroidManifest.xml` declares `BLUETOOTH_SCAN`,
  `BLUETOOTH_ADVERTISE`, `BLUETOOTH_CONNECT`, `INTERNET`,
  `ACCESS_WIFI_STATE`, `NEARBY_WIFI_DEVICES`.

## Minimum players per round

| Game          | Min | Max |
|---------------|----:|----:|
| Tag           | 2   | —   |
| Mafia         | 4   | —   |
| Werewolf      | 5   | —   |
| Imposter      | 3   | —   |
| Codenames     | 4   | —   |
| Crazy Eights  | 2   | 8   |

Enforced by `*Engine.canStart`.
