# Ubapp

Cross-platform 2D / party game app built with **Flutter + Flame**, designed for offline same-room play. Two guest tiers:

- **App-installed peers** → BLE-based proximity games (tag), plus all card / social / trivia games
- **Browser-only guests** → join the host's local WebSocket server via QR code, play card / social / trivia games (no BLE needed)

## What's in here

```
lib/
├── main.dart                          # MaterialApp entry
├── menu/main_menu_screen.dart         # top-level mode picker
├── games/
│   └── tag/                           # offline party tag with 5 variants
│       ├── tag_variant.dart           # Classic / Freeze / Zombie / Hot potato / Bomb
│       ├── tag_protocol.dart          # sealed JSON message types
│       ├── proximity.dart             # ProximitySource + sliding-window detector
│       ├── ble_proximity.dart         # flutter_blue_plus central scan
│       ├── tag_engine.dart            # deterministic state machine
│       ├── tag_session.dart           # engine + proximity + transport glue
│       ├── tag_lobby_screen.dart      # variant picker, host toggle, peer list
│       └── tag_screen.dart            # full-screen role UI + countdown
├── realtime/                          # Flame demo (player vs steering enemies)
├── turnbased/                         # tic-tac-toe + minimax
└── social/
    ├── host_server.dart               # shelf HTTP + WebSocket, one-tap start
    ├── social_screen.dart             # placeholder until card games land
    └── transport.dart                 # interface for future BLE/WebSocket fan-out
```

## Run

This repo is Dart source + `pubspec.yaml`. Generate the platform shells once:

```bash
flutter create . --project-name ubapp --org com.example --platforms=ios,android
flutter pub get
flutter run
```

For running on a physical Android or iOS phone — toolchain prerequisites, signing setup, permissions, and how to host a multi-device session — see [`docs/mobile-setup.md`](docs/mobile-setup.md).

## Tag — what works, what's TODO

**Working (tested in single-device dev mode):**

- All 5 variants (Classic / Freeze / Zombie / Hot potato / Bomb) — pure game logic in `TagEngine`, deterministic, swap variants live.
- Polished full-screen role UI: red "YOU'RE IT", blue "FROZEN", green "RUN", grey "OUT", with vibration on role change.
- Variant-aware HUD: hides "it" identity for Bomb, shows unfreeze targets for Freeze tag, transfers role on contact.
- One-tap host: `HostServer` spins up shelf HTTP + WebSocket on the local Wi-Fi, displays a QR code with the join URL.
- Manual "touch player X" debug chips so the round is testable end-to-end without real BLE.

**Needs BLE on real devices to be a real game:**

1. **iOS BLE peripheral** — `flutter_blue_plus` is central-only. Add a small platform channel (~150 lines) wrapping `CBPeripheralManager` to advertise `serviceUuid + peerId payload`. Dock into `BleProximity` via the existing `ProximitySource` interface.
2. **Android BLE peripheral** — drop in `flutter_ble_peripheral` or similar; same interface.
3. **Cross-device transport** — wire `TagSession.broadcast` to send `TagMessage.encode()` over BLE GATT writes (or your WebSocket+BLE multiplex from `host_server.dart`).

Architecturally none of those changes touch UI or game logic — `ProximitySource` and the broadcast callback are the seams.

## Permissions to add after `flutter create`

**`ios/Runner/Info.plist`:**

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Used to find nearby phones for tag and other party games.</string>
<key>NSLocalNetworkUsageDescription</key>
<string>Used to host or join games on the local Wi-Fi.</string>
<key>NSBonjourServices</key>
<array><string>_ubapp._tcp</string></array>
```

**`android/app/src/main/AndroidManifest.xml`:**

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

## What's coming next

Priority order from your direction:

1. **Mafia / Imposter / Werewolf / Spyfall** — host runs the WebSocket server, browser guests join via QR. No BLE needed; all guests just need a phone with a browser.
2. **Crazy 8s / Uno-style card games** — same path; phone is your hand, host shows table.
3. **Connect Four** — drop-in to the existing `turnbased/` minimax.
4. **Capture the flag tag variant** — needs team management + flag state on top of the existing tag engine.
