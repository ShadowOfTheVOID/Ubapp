# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project shape

Native-app collection of small offline party games for same-room play.
**Two platforms, no shared runtime**: iOS (SwiftUI, iOS 17+) and Android
(Kotlin/Compose, minSdk 26 / targetSdk 35). Two guest tiers:

- **App-installed peers** — required for proximity games (BLE), e.g. Tag.
  App guests can *also* join any browser-tier game natively via the
  **Join a game** menu entry (see Join flow below).
- **Browser-only guests** — connect via QR to a host phone running an
  in-app HTTPS + WebSocket server. Used for social / card / trivia games.

Originally a Flutter/Dart codebase; the migration is finished for the games
listed in README.md "Migration status". Treat README.md's status table and
min/max-player table as the source of truth for game inventory.

## Layout

```
ios/
├── Jamboree.xcodeproj/project.pbxproj     # hand-written, filesystem-synchronized root group
└── Jamboree/
    ├── App/{JamboreeApp.swift,JamboreeTheme.swift,Info.plist}
    ├── Menu/MainMenuView.swift
    ├── Games/<Name>/                    # engine + view (+ server + guest view for browser-tier)
    ├── Games/Shared/HostingChrome.swift # shared QR + app-code host card
    ├── Join/                            # app-guest join flow (see below)
    ├── Social/HostServer.swift          # Network.framework HTTPS + WebSocket
    ├── Tutorials/                       # TutorialContent + TutorialVote + TutorialVoteCard
    └── Resources/                       # *_browser.html bundles + jamboree.p12 TLS identity

android/
├── settings.gradle.kts, build.gradle.kts, gradle.properties
└── app/src/main/
    ├── AndroidManifest.xml
    ├── assets/                          # *_browser.html bundles + jamboree.p12 TLS identity
    └── java/com/example/jamboree/
        ├── MainActivity.kt, menu/MainMenu.kt
        ├── games/<name>/                # engine + screen (+ server + guest screen for browser-tier)
        ├── shared/HostingChrome.kt
        ├── join/                        # app-guest join flow
        ├── social/HostServer.kt         # NanoHTTPD-WebSocket
        └── tutorials/
```

## Common commands

### iOS (no test target — engines are verified on the Android side)
```
open ios/Jamboree.xcodeproj
xcodebuild -project ios/Jamboree.xcodeproj -scheme Jamboree -destination 'generic/platform=iOS Simulator' build
```

### Android
```
cd android
gradle wrapper --gradle-version=8.10            # one-time, if wrapper missing
./gradlew :app:assembleDebug
./gradlew :app:installDebug
./gradlew :app:testDebugUnitTest                # all engine unit tests (src/test/)
./gradlew :app:testDebugUnitTest --tests "com.example.jamboree.EnginesTest"   # single test class
```

Engine unit tests live in `android/app/src/test/java/com/example/jamboree/`
(`EnginesTest`, `GameOptionsTest`, `MafiaEngineTest`, `SecretHitlerEngineTest`).
Because the Swift and Kotlin engines are deliberately identical state
machines, these tests are the practical regression net for **both**
platforms — port engine fixes to Kotlin and add/extend a test there even
when the bug was found in Swift.

## Architecture in one paragraph

Each game lives in `<platform>/.../games/<name>/` with three layers: a
**pure engine** (no UI, no I/O), a **session/server adapter** that connects
the engine to a transport, and a **view/screen** that renders state and
forwards actions. Engines are deterministic state machines so every client
(Swift host, Kotlin host, browser guest, BLE peer) computes the same state
from the same ordered events. Transports are hot-swappable via small
interfaces — `ProximitySource` for BLE, `HostServer` for WebSocket fan-out —
so the same engine and UI work against real Bluetooth or a manual test
stream. Local-only games (Tic-Tac-Toe, Connect Four, Real-time) skip the
adapter layer entirely: engine + view, no server.

## Per-game wiring (browser-tier: Mafia, Werewolf, Imposter, Codenames, Crazy Eights, Secret Hitler)

Mafia is the reference (`ios/Jamboree/Games/Mafia/`,
`android/.../games/mafia/`). Four pieces per game:

1. **Browser bundle** — `Resources/<name>_browser.html` (iOS) /
   `assets/<name>_browser.html` (Android), loaded verbatim and served at
   `/`. Consumes the same JSON the server emits.
2. **`*Server`** wrapping `HostServer` — maps inbound JSON commands to
   engine calls, sends private (`send(to:_:)`) and broadcast
   (`broadcast(_:)`) state.
3. **`*GuestView` / `*GuestScreen`** — the player UI a guest sees.
4. **`*View` / `*Screen`** (native host view) — embeds `HostingChrome`
   (QR + app code) **and the game's own `*GuestView`**, because the host
   plays as a real player. The host is player id `host`, driven through an
   **in-process loopback** rather than a WebSocket — it never connects over
   the network but goes through the same server/engine path as guests.

For Tag (proximity): `TagSession` owns a `TagEngine` plus a `TagTransport`
(`HostTagTransport` wraps the host's `HostServer` for fan-out; the peer
variant wraps a single outbound socket). Proximity events arrive via
`ProximitySource` (`BleProximity` for real BLE); `TagProtocol` defines the
wire `TagMessage`s. Host and every peer run engine mirrors fed the same
ordered events.

## Join flow (app guests → browser-tier host)

`ios/Jamboree/Join/` and `android/.../join/`. The host's `HostingChrome` card
shows a **7-character base-36 join code** (`JoinCode`) that encodes the
host's IPv4 (port fixed at `7654`); a raw IP is also accepted. `GuestClient`
(iOS, `URLSessionWebSocketTask`) / the Android equivalent opens a `wss://`
socket to the host and speaks the **same JSON wire format as the browser
bundle** behind the `GuestLink` interface, then renders the game's native
`*GuestView`.

## Transport & TLS

`HostServer` binds default port **7654** on all IPv4 interfaces.

- The server runs **HTTPS / WSS** using a bundled self-signed PKCS12
  identity: `Resources/jamboree.p12` (iOS) / `assets/jamboree.p12` (Android). If
  the cert can't load, both platforms fall back to plain HTTP/WS.
- Browser bundles connect with `new WebSocket(`wss://${location.host}/ws`)`.
  Browser guests must accept the self-signed-cert warning once.
- App guests **pin the bundled cert** (`GuestClient` trusts the bundled
  certificate manually, since the host is reached at a dynamic LAN IP that
  can never appear in the cert's SANs).
- Still LAN-only — the host phone cannot tunnel through anything requiring
  a publicly trusted chain.

When you change the `.p12`, replace it in **both** `Resources/` and
`assets/` or the two platforms will present mismatched certs.

## Conventions worth keeping

- **Engines never touch I/O.** Pure Swift `struct`/`class` and Kotlin
  classes; no `Task`/`async`, no `CoroutineScope`, no system APIs inside
  `*Engine.swift` / `*Engine.kt`.
- **JSON over the wire is line-oriented, dispatched on `type`.** A new
  message type needs a matching `case`/`when` in: the native `*Server`, the
  `*_browser.html` bundle, the native `*GuestView`/`*GuestScreen`, and (for
  Tag) the second peer — miss one and that side silently drops the event.
- **Host plays via loopback.** Don't special-case the host in engine
  logic; it's a normal player with id `host` whose transport is in-process.
- **No platform shells are generated.** iOS uses a hand-written
  `project.pbxproj` with a `PBXFileSystemSynchronizedRootGroup` (Xcode 16) —
  new Swift files under `ios/Jamboree/` are picked up without editing the
  project. Android is a plain Gradle project; the Gradle wrapper is the
  user's responsibility to generate.
- **Keep Swift and Kotlin engines in lockstep.** A fix to one engine almost
  always needs the same fix in the other; add the regression test on the
  Android side.

## Pitfalls worth knowing

- **Four-way contract for browser-tier messages.** Server + browser bundle +
  native guest view + (Tag) peer all consume the same JSON. The `.html`
  bundles are byte-identical to the original Flutter files and loaded
  verbatim — edit the `.html` too when adding a message type.
- **TLS asset must be in both trees.** `jamboree.p12` lives in `Resources/`
  (iOS) and `assets/` (Android); keep them identical.
- **iOS BLE in background.** `CBPeripheralManager.startAdvertising` only
  honors the local-name field while foregrounded — backgrounding drops to
  a service-UUID-only payload. Same on Android. Tag rounds assume
  foreground and keep the screen on (iOS `UIApplication.isIdleTimerDisabled
  = true` in `TagLobbyView`; Android `FLAG_KEEP_SCREEN_ON`).
- **Android Tag permission prompt** is handled by `PermissionGate` in
  `TagLobbyScreen.kt` (Accompanist `rememberMultiplePermissionsState`).
  BLUETOOTH_SCAN + BLUETOOTH_ADVERTISE + BLUETOOTH_CONNECT must be granted
  before "Start hosting" is enabled.
- **Tutorial vote.** Lives under `Tutorials/`. Copy is in `TutorialContent`
  (`GameTutorial` / `TutorialSection`). Each browser-tier server emits a
  `tutorial_vote_state` message once the vote passes; the browser bundle
  and `TutorialVoteCard` (SwiftUI / Compose) render the card. New games
  need both the `TutorialContent` entry and the vote wiring on the server.
</content>
