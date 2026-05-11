# BLE peripheral advertiser — one-time install

`flutter_blue_plus` does central-side scanning only. The two source files in this folder fill in the missing peripheral-side advertising on each platform. They expose the same `MethodChannel('ubapp/ble_advertiser')` API that `lib/native/ble_advertiser.dart` consumes — drop them into your platform shells after running `flutter create .` and tag's BLE toggle starts working.

## Android

```bash
# from repo root, after `flutter create . --platforms=android`:
mkdir -p android/app/src/main/kotlin/com/example/ubapp
cp tooling/ble_native/android/BleAdvertiserPlugin.kt \
   android/app/src/main/kotlin/com/example/ubapp/BleAdvertiserPlugin.kt
```

Then register the plugin in `android/app/src/main/kotlin/com/example/ubapp/MainActivity.kt`:

```kotlin
package com.example.ubapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(BleAdvertiserPlugin())
    }
}
```

Add to `android/app/src/main/AndroidManifest.xml` inside `<manifest>`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<!-- For API < 31 -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
```

Make sure the app's `compileSdk` ≥ 31. The `flutter_blue_plus` dependency in `pubspec.yaml` already targets that, so you generally don't need to change it. At runtime, `permission_handler` (already in `pubspec.yaml`) handles the dialog.

## iOS

```bash
# from repo root, after `flutter create . --platforms=ios`:
cp tooling/ble_native/ios/BleAdvertiserPlugin.swift \
   ios/Runner/BleAdvertiserPlugin.swift
```

Add a registration call in `ios/Runner/AppDelegate.swift` — inside `application(_:didFinishLaunchingWithOptions:)` after `GeneratedPluginRegistrant.register(with: self)`:

```swift
if let registrar = self.registrar(forPlugin: "BleAdvertiserPlugin") {
  BleAdvertiserPlugin.register(with: registrar)
}
```

Add to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Tag needs Bluetooth to detect nearby players.</string>
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-peripheral</string>
  <string>bluetooth-central</string>
</array>
```

The `UIBackgroundModes` keys aren't required for foreground-only play, but adding them now means the app can keep advertising if the user briefly switches away. iOS still significantly throttles background advertising — for active tag rounds, keep the app in the foreground.

## Verification

In the Tag lobby (`/tag` route), the "Proximity source" card should report `Use real BLE` as enabled once the plugin is installed and the device supports BLE peripheral mode. Toggle it on, hit Start, and watch the system log:

```
flutter: tag tx: {"type":"start", ...}
```

If you have two devices running, each phone should appear in the other's scan as a peer with its peer id readable from the local-name field. The `BleProximity` scanner emits `ProximityEvent(peerId, rssi)` events as the phones move close; the `ProximityDetector` averages the last 4 readings and fires a tag at `rssi ≥ -55 dBm`.

## What's still required for tag to be a real cross-device game

This unblocks **discovery and proximity**. The `broadcast` callback in `TagSession` is still a `debugPrint` — once two phones can see each other, the next step is to actually transmit `TagMessage.encode()` between them. The cleanest approach is: the host phone runs `HostServer` (already in `lib/social/host_server.dart`) and advertises its Wi-Fi IP in BLE service data; peer phones discover it via scan, then sync game state over the WebSocket. That's a small change to `TagSession.broadcast` plus a discovery handshake — left as a follow-up so this PR can land independently.
