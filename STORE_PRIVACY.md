# Store privacy disclosures

Reference for the **Google Play Data safety** form and the **Apple App Privacy**
("nutrition label") questionnaire. These console answers are filled in by hand
and must stay consistent with what the binary declares:

- iOS: `ios/Jamboree/PrivacyInfo.xcprivacy`
- Android: AdMob's bundled data declarations + `AndroidManifest.xml` permissions

> The only SDK that collects user data is **Google AdMob** (with the Google
> **User Messaging Platform** for consent). Jamboree's own code stores settings
> and game stats **locally only** (`UserDefaults` / `SharedPreferences`) and
> never sends them off-device. Player display names travel **phone-to-phone over
> the local network** during a game; they are not collected by the developer or
> sent to any server.

When AdMob's own guidance changes, treat **AdMob's published Data Safety / App
Privacy guidance as the source of truth** and update this file plus the
manifests to match.

---

## Google Play — Data safety

### Does the app collect or share user data?
**Yes** — via the AdMob SDK.

### Data types

| Category | Data type | Collected | Shared | Processed ephemerally | Purpose | Optional? |
|---|---|---|---|---|---|---|
| Device or other IDs | Advertising ID | Yes | Yes (Google) | No | Advertising or marketing | Required for ads; user can limit via the consent form / system Ad ID reset |
| App activity | App interactions | Yes | Yes (Google) | No | Advertising or marketing; Analytics | No |
| App info & performance | Crash logs / diagnostics | Yes | Yes (Google) | No | Analytics | No |
| Location | Approximate location | Yes | Yes (Google) | No | Advertising or marketing | No |

> Approximate location is **inferred by AdMob from IP**, not from a device
> location permission. Jamboree requests **no** location permission, and the
> Bluetooth / Nearby-Wi-Fi permissions are flagged `neverForLocation`.

### Data **not** collected by Jamboree itself
- No account / sign-in, no name, email, or contacts.
- Game settings and local match stats stay on the device (`SharedPreferences`).
- Microphone / speech (The Bureaucrat) is processed **on-device** for the
  rebuttal feature and is **not** recorded, stored, or transmitted.

### Security practices
- **Data is encrypted in transit** — LAN play uses TLS/WSS; AdMob uses HTTPS.
- **No account, so no account-deletion flow.** Local data is removed by
  uninstalling. Ad personalization is controlled through the consent form and
  the system Advertising ID controls.
- Independent security review: optional; leave unchecked unless you have one.

---

## Apple — App Privacy

`PrivacyInfo.xcprivacy` declares `NSPrivacyTracking = true`, the AdMob tracking
domains, and the collected data types below. The App Store Connect answers
must mirror this.

### Data used to track you
*(linked to identity/device for cross-app/-site tracking — i.e. ATT applies)*

| Data type | Notes |
|---|---|
| **Device ID** (IDFA) | Collected by AdMob for third-party advertising. Gated behind the ATT prompt + UMP consent. |

### Data linked to you
None beyond the Device ID above. (Jamboree itself collects nothing tied to an
identity.)

### Data not linked to you
| Data type | Purpose |
|---|---|
| **Product Interaction** (usage data) | Analytics (AdMob) |

> If you later enable AdMob crash/diagnostics reporting, also declare
> **Crash Data** / **Performance Data** (Not Linked) and add the matching
> `NSPrivacyCollectedDataType` entries to `PrivacyInfo.xcprivacy`.

### Required-reason API
- `NSPrivacyAccessedAPICategoryUserDefaults`, reason **`CA92.1`** — reading and
  writing the app's own settings/stats. Already declared in the manifest.

### Export compliance
`Info.plist` sets `ITSAppUsesNonExemptEncryption = false` — the app uses only
standard TLS/HTTPS and OS-provided crypto, which is exempt. No CCATS/year-end
self-classification report is required.

---

## Permission usage strings (already in the binary)

For reviewer context — each prompt has a purpose string:

| Permission | iOS key | Android |
|---|---|---|
| Bluetooth (Tag proximity) | `NSBluetoothAlwaysUsageDescription`, `NSBluetoothPeripheralUsageDescription` | `BLUETOOTH_SCAN/ADVERTISE/CONNECT` (`neverForLocation`) |
| Local network (host server) | `NSLocalNetworkUsageDescription`, `NSBonjourServices` | `INTERNET`, `ACCESS_WIFI_STATE`, `NEARBY_WIFI_DEVICES` (`neverForLocation`) |
| Microphone + speech (Bureaucrat) | `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` | — |
| Tracking (ads) | `NSUserTrackingUsageDescription` | `com.google.android.gms.permission.AD_ID` |
