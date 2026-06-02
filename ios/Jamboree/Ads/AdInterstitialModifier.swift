import SwiftUI
import GoogleMobileAds

extension View {
    /// Presents a real GADInterstitialAd when `isPresented` goes true.
    /// Falls back to a ≤10 s skippable overlay if the ad hasn't loaded
    /// (offline, no-fill, cold first session). No-op when ad-free.
    func adInterstitial(isPresented: Binding<Bool>) -> some View {
        modifier(AdInterstitialModifier(isPresented: isPresented))
    }
}

private struct AdInterstitialModifier: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject private var ads = AdManager.shared
    @StateObject private var loader = InterstitialLoader()

    func body(content: Content) -> some View {
        content
            .onAppear { loader.preload() }
            .onChange(of: isPresented) { _, show in
                guard show else { return }
                if ads.isAdFree {
                    isPresented = false; return
                }
                if loader.isReady {
                    loader.present { isPresented = false }
                }
                // else: fallback overlay is shown via the overlay modifier below
            }
            .overlay {
                if isPresented && !ads.isAdFree && !loader.isReady {
                    AdFallbackOverlay { isPresented = false }
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isPresented)
    }
}

// MARK: - Ad loader

@MainActor
private final class InterstitialLoader: NSObject, ObservableObject, @preconcurrency GADFullScreenContentDelegate {
    #if DEBUG
    // Google's sample interstitial unit — debug/QA must never load live ads.
    private static let adUnitID = "ca-app-pub-3940256099942544/4411468910"
    #else
    private static let adUnitID = "ca-app-pub-8315138960777125/4386164266"
    #endif

    private var ad: GADInterstitialAd?
    private var onDismiss: (() -> Void)?
    @Published private(set) var isReady = false

    func preload() {
        guard ad == nil else { return }
        GADInterstitialAd.load(withAdUnitID: Self.adUnitID, request: GADRequest()) { [weak self] ad, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.ad = ad
                self.ad?.fullScreenContentDelegate = self
                self.isReady = ad != nil
            }
        }
    }

    func present(onDismiss: @escaping () -> Void) {
        guard let ad else { onDismiss(); return }
        self.onDismiss = onDismiss
        guard let root = UIApplication.shared
            .connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController else { onDismiss(); return }
        ad.present(fromRootViewController: root)
    }

    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        self.ad = nil; isReady = false
        let cb = onDismiss; onDismiss = nil
        cb?()
        preload()
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        self.ad = nil; isReady = false
        let cb = onDismiss; onDismiss = nil
        cb?()
        preload()
    }
}

// MARK: - Fallback overlay (offline / no-fill / cold start)

private struct AdFallbackOverlay: View {
    let onDismiss: () -> Void
    @State private var remaining = 10

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                RoundedRectangle(cornerRadius: JamboreeRadius.card, style: .continuous)
                    .fill(JamboreeTheme.surface)
                    .frame(height: 240)
                    .overlay(
                        Text("Advertisement")
                            .font(.system(size: 15))
                            .foregroundStyle(JamboreeTheme.faint)
                    )
                    .padding(.horizontal, 20)
                Spacer()
                Button(action: onDismiss) {
                    HStack(spacing: 6) {
                        Text("Skip")
                        if remaining > 0 {
                            Text("(\(remaining))").foregroundStyle(JamboreeTheme.muted)
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(JamboreeTheme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .padding(.bottom, 40)
            }
        }
        .task { await countdown() }
    }

    private func countdown() async {
        for i in stride(from: 10, through: 1, by: -1) {
            remaining = i
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
        }
        remaining = 0
        onDismiss()
    }
}
