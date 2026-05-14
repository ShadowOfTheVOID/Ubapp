# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Project shape

Native-app collection of small offline party games for same-room play.
**Two platforms, no shared runtime**: iOS (SwiftUI) and Android
(Kotlin/Compose). Two guest tiers:

- **App-installed peers** — needed for proximity games (BLE), e.g. tag.
- **Browser-only guests** — connect via QR to a host phone running an in-app
  HTTP + WebSocket server. Used for social / card / trivia games.

This branch is mid-migration from a previous Flutter/Dart implementation;
see README.md "Migration status" for what's ported per game.

## Layout

```
ios/
├── Ubapp.xcodeproj/project.pbxproj     # hand-written, no xcodegen
└── Ubapp/
    ├── App/{UbappApp.swift,Info.plist}
    ├── Menu/MainMenuView.swift
    ├── Games/<Name>/                   # engine + view (+ server + browser for browser-tier)
    └── Social/HostServer.swift         # Network.framework HTTP + WebSocket

android/
├── settings.gradle.kts, build.gradle.kts, gradle.properties
└── app/
    ├── build.gradle.kts
    └── src/main/
        ├── AndroidManifest.xml
        ├── java/com/example/ubapp/
        │   ├── MainActivity.kt, menu/MainMenu.kt
        │   ├── games/<name>/           # engine + screen (+ server for browser-tier)
        │   └── social/HostServer.kt    # NanoHTTPD-WebSocket
        └── res/values/
```

## Common commands

### iOS
```
open ios/Ubapp.xcodeproj
xcodebuild -project ios/Ubapp.xcodeproj -scheme Ubapp -destination 'generic/platform=iOS Simulator' build
```

### Android
```
cd android
gradle wrapper --gradle-version=8.10   # one-time, if wrapper missing
./gradlew :app:assembleDebug
./gradlew :app:installDebug
./gradlew :app:testDebugUnitTest        # runs the engine tests under src/test/
```

## Architecture in one paragraph

Each game lives in `<platform>/.../games/<name>/` with three layers: a
**pure engine** (no UI, no I/O), a **session/server adapter** that connects
the engine to a transport, and a **view/screen** that renders state and
forwards user actions. Engines are deliberately deterministic state machines
so any client (Swift host, Kotlin host, browser guest, future BLE peer)
computes the same state from the same ordered events. The transport is
hot-swappable via small interfaces — `ProximitySource` for BLE proximity,
`HostServer` for WebSocket fan-out — so the same engine and UI work whether
you're plumbing real Bluetooth or a manual test stream.

## Per-game wiring

Same pattern on both platforms. Mafia is the reference: see
`ios/Ubapp/Games/Mafia/` (`MafiaEngine.swift`, `MafiaServer.swift`,
`MafiaBrowser.swift`, `MafiaView.swift`) and
`android/.../games/mafia/MafiaEngine.kt`.

For browser-tier games (Mafia, Werewolf, Imposter, Codenames, Crazy Eights):

1. Game-specific HTML/JS as a string constant — served at `/`. Same JSON the
   server emits is consumed by the host's native view, so both clients must
   stay in sync when message types change.
2. A `*Server` class wrapping `HostServer`, mapping inbound JSON commands to
   engine calls and outbound state to private/broadcast sends. The native
   host plays as a special player with id `host` that does not connect over
   WebSocket.
3. A native view (SwiftUI / Compose) that displays the QR + acts as the
   host's player UI.

For Tag (proximity): the engine consumes `ProximitySource` events (BLE
central scan results) and broadcasts `TagMessage`s to app peers over the
same `HostServer` transport.

## HostServer

- **iOS** (`Social/HostServer.swift`): `NWListener` + WebSocket protocol
  option. Binds default port `7654` to all IPv4 interfaces. Each connection
  gets a stable `GuestId` for its lifetime; games use `send(to:_:)` for
  private messages and `broadcast(_:)` for everything public. The served
  HTML is swappable per-game.
- **Android** (`social/HostServer.kt`): NanoHTTPD-WebSocket, same API. The
  served HTML is mutable on the instance before `startServer()`.

Browsers connect via `new WebSocket(\`ws://${location.host}/ws\`)` — plain
HTTP only, no TLS. Correct for LAN play but the host phone can't tunnel
through anything that requires HTTPS.

## Conventions worth keeping

- **Engines never touch I/O.** Pure Swift `struct`/`class` and Kotlin
  classes; no `Task`/`async`, no `CoroutineScope`, no system APIs inside
  `*Engine.swift` / `*Engine.kt`. This keeps games trivially testable.
- **JSON over the wire is line-oriented, dispatched on `type`.** When you
  add a message type, add a `case` / `when` on both sides (native server +
  browser bundle, or the second peer) or one side will silently drop events.
- **No platform shells are generated.** iOS uses a hand-written
  `project.pbxproj` (filesystem-synchronized root group → adding Swift
  files never requires editing the project). Android uses a plain Gradle
  project; the Gradle wrapper is the user's responsibility to generate.

## Pitfalls worth knowing

- **Browser bundle ↔ host view are in an implicit contract.** Both consume
  the same JSON the server emits. The bundles are loaded verbatim from
  `Resources/<name>_browser.html` (iOS) / `assets/<name>_browser.html`
  (Android); when adding a message type, also update the matching
  `.html` file or one side will silently drop events.
- **iOS BLE in background.** `CBPeripheralManager.startAdvertising` only
  honors the local-name field while the app is foreground — peripheral
  advertising drops to a service-UUID-only payload when backgrounded.
  Tag rounds assume foreground.
- **Tutorial vote** lives under `Tutorials/` (`TutorialVote` + `GameTutorials`)
  on both platforms. Each browser-tier server emits a `tutorial_vote_state`
  message with the title + sections payload once the vote passes; the
  browser bundle renders the tutorial card. Every native host view drops
  in `TutorialVoteCard` (SwiftUI) or `TutorialVoteCard` (Compose) and
  calls `host*TutorialVote` / `hostDismissTutorial` on its server.
- **Tag rounds keep the screen on.** iOS `TagLobbyView` sets
  `UIApplication.isIdleTimerDisabled = true` while hosting; Android adds
  `FLAG_KEEP_SCREEN_ON` to the activity window. `CBPeripheralManager` only
  honors the local-name field of an advert while foreground, and the same
  is true on Android — backgrounding drops to a service-UUID-only payload.
- **Android Tag permission prompt** is handled by `PermissionGate` in
  `TagLobbyScreen.kt` using Accompanist's `rememberMultiplePermissionsState`.
  The user must accept BLUETOOTH_SCAN + BLUETOOTH_ADVERTISE + BLUETOOTH_CONNECT
  before "Start hosting" is enabled.
