import AppTrackingTransparency

enum ATTManager {
    /// Request ATT authorisation once per install. Call this after the first
    /// screen has appeared — Apple requires the app UI to be visible first.
    /// Safe to call multiple times; the system only shows the prompt once.
    static func requestIfNeeded() {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        ATTrackingManager.requestTrackingAuthorization(completionHandler: { _ in })
    }
}
