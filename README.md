# Ubapp

Cross-platform 2D game scaffold with three modes — real-time, turn-based, and social — implemented twice: once on iOS (SpriteKit + GameplayKit) and once on Android (SurfaceView + a hand-rolled ECS).

## iOS — `Ubapp.xcodeproj`

Open in Xcode 15+, pick an iPhone simulator, run.

- **Real-time** — `GKEntity`/`GKComponent` world; tap-to-move via `GKBehavior` seek goal; enemies flip between Wander and Chase via `GKStateMachine` driving `GKAgent2D` steering.
- **Turn-based** — `GKGameModel` tic-tac-toe with `GKMinmaxStrategist` (depth 6) on a background queue.
- **Social** — Game Center sign-in (`GKLocalPlayer`), dashboard (`GKGameCenterViewController`), and `GKLeaderboard.submitScore`.

Default target: iOS 16, iPhone + iPad. Bundle id `com.example.Ubapp` (change under Signing & Capabilities).

## Android — `android/`

Open the `android/` folder in Android Studio Hedgehog+ and run on an API 24+ device or emulator.

- **Real-time** (`realtime/`) — `SurfaceView` + a 60 FPS game loop; small ECS (`Entity`/`Component`); `AgentComponent` does seek-style steering; `StateMachine` flips enemies between `WanderState` and `ChaseState`.
- **Turn-based** (`turnbased/`) — `TicTacToeModel` plus a Kotlin `Minimax` AI driven from `Dispatchers.Default` via `lifecycleScope`.
- **Social** (`social/`) — placeholder `SocialActivity` and a `Transport` interface that the offline multiplayer layer will plug into.

Application id `com.example.ubapp`. Run `gradle wrapper` once if `gradlew` isn't already generated locally.

## Offline multiplayer (TBD)

Both apps leave a `Transport` slot for the offline-comms layer. Likely candidates:

- **iOS**: `MultipeerConnectivity` (auto-selects BLE + AWDL).
- **Android**: Nearby Connections, or BLE for low-bandwidth turn-based, or Wi-Fi Direct for higher bandwidth.
- **Cross-platform**: BLE GATT with a custom packet format, or a shared Wi-Fi hotspot with mDNS/Bonjour.

Pick one per platform and implement against `Transport` (Android) / a parallel iOS protocol; the game activities don't need to change.
