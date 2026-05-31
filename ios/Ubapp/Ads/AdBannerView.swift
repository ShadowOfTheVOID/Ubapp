import SwiftUI
import GoogleMobileAds

struct AdBannerView: View {
    @ObservedObject private var ads = AdManager.shared

    var body: some View {
        if !ads.isAdFree {
            GADBannerRepresentable()
                .frame(height: 50)
        }
    }
}

private struct GADBannerRepresentable: UIViewRepresentable {
    // TODO: Replace with your live Banner ad unit ID from the AdMob dashboard.
    // Create two unit IDs (one per placement) under your iOS app in AdMob.
    private static let adUnitID = "ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX"

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = Self.adUnitID
        banner.rootViewController = UIApplication.shared
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        banner.load(GADRequest())
        return banner
    }

    func updateUIView(_ uiView: GADBannerView, context: Context) {}
}
