# Ubapp

A collection of small offline party games for same-room play. **Native iOS
(SwiftUI) and native Android (Kotlin/Compose)** — no shared runtime, no
cross-platform framework.

Two guest tiers:

- **App-installed peers** — needed for proximity games (BLE), e.g. tag. App
  guests can also join any browser-tier game natively via the **Join a game**
  menu entry, typing the host's 7-character app code (or raw IP). The host's
  hosting card displays both the QR code (for browser guests) and the app code.
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

| Game           | Engine | Server | Browser bundle | Host view (iOS) | Host view (Android) |
|----------------|:------:|:------:|:--------------:|:---------------:|:-------------------:|
| Mafia          | done   | done   | done           | done            | done                |
| Werewolf       | done   | done   | done           | done            | done                |
| Imposter       | done   | done   | done           | done            | done                |
| Codenames      | done   | done   | done           | done            | done                |
| Crazy Eights   | done   | done   | done           | done            | done                |
| Cheat (Bluff)     | done   | done   | done           | done            | done                |
| President      | done   | done   | done           | done            | done                |
| Bluff Market   | done   | done   | done           | done            | done                |
| Secret Hitler  | done   | done   | done           | done            | done                |
| Tag (BLE)      | done   | n/a    | n/a            | done            | done                |
| Tic-Tac-Toe    | done   | n/a    | n/a            | done            | done                |
| Connect Four   | done   | n/a    | n/a            | done            | done                |
| Real-time      | done   | n/a    | n/a            | done            | done                |

The browser bundles are loaded from `Resources/<name>_browser.html` (iOS)
and `assets/<name>_browser.html` (Android) and are byte-identical to the
original Flutter files — no string-escaping needed. Every social-game host
view shares a `HostingChrome` (QR card) + `TutorialVoteCard` (lobby
tutorial opt-in) helper so adding a new game is mostly engine + adapter.
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
| Cheat (Bluff)    | 3   | 8   |
| President     | 4   | 7   |
| Bluff Market  | 3   | 6   |
| Secret Hitler | 5   | 10  |

Enforced by `*Engine.canStart`.
