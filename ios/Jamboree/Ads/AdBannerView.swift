import SwiftUI
import GoogleMobileAds

enum AdBannerPlacement {
    case lobby
    case betweenRounds

    var adUnitID: String {
        #if DEBUG
        // Google's sample banner unit. Debug/QA builds must never request live
        // ads — loading or clicking your own production ads is an AdMob policy
        // violation. Release builds use the real units below.
        return "ca-app-pub-3940256099942544/2934735716"
        #else
        switch self {
        case .lobby:         return "ca-app-pub-8315138960777125/2156576421"
        case .betweenRounds: return "ca-app-pub-8315138960777125/4183973964"
        }
        #endif
    }
}

struct AdBannerView: View {
    let placement: AdBannerPlacement
    @ObservedObject private var ads = AdManager.shared

    var body: some View {
        if !ads.isAdFree {
            GADBannerRepresentable(adUnitID: placement.adUnitID)
                .frame(height: 50)
        }
    }
}

private struct GADBannerRepresentable: UIViewRepresentable {
    let adUnitID: String

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: GADAdSizeBanner)
        banner.adUnitID = adUnitID
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
