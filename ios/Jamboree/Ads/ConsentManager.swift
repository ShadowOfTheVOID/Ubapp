import GoogleMobileAds
import UserMessagingPlatform
import UIKit

/// Gathers GDPR/CCPA consent via Google's User Messaging Platform, requests
/// App Tracking Transparency, then starts the Mobile Ads SDK. Mirrors the
/// Android `ConsentManager`.
///
/// The Mobile Ads SDK is started only once the user can be served ads —
/// either consent is on file, or the user is outside a consent jurisdiction
/// (where UMP reports `canRequestAds == true` with no form). Call
/// `gatherThenStartAds()` once the first screen is visible: Apple requires the
/// app UI to be up before the ATT prompt, and UMP forms need a view controller
/// to present from.
@MainActor
enum ConsentManager {
    private static var adsStarted = false

    static func gatherThenStartAds() {
        let params = UMPRequestParameters()
        params.tagForUnderAgeOfConsent = false

        UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: params) { _ in
            // Whether or not the network update succeeded, present a form if
            // one is required for this region, then continue. On failure
            // (offline, etc.) `canRequestAds` governs whether ads still start.
            UMPConsentForm.loadAndPresentIfRequired(from: topViewController()) { _ in
                requestATTThenStart()
            }
        }

        // Fast-path: consent already on file from a previous session — don't
        // wait on the network round-trip to start ads.
        if UMPConsentInformation.sharedInstance.canRequestAds {
            requestATTThenStart()
        }
    }

    private static func requestATTThenStart() {
        // ATT is requested after the UMP form so the two prompts don't stack;
        // it is idempotent (only shown once per install).
        ATTManager.requestIfNeeded()
        guard UMPConsentInformation.sharedInstance.canRequestAds else { return }
        startAdsOnce()
    }

    private static func startAdsOnce() {
        guard !adsStarted else { return }
        adsStarted = true
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
