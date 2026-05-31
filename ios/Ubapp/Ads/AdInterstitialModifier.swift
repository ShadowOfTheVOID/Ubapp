import SwiftUI

extension View {
    /// Shows a ≤10 s skippable interstitial overlay when `isPresented` is true.
    /// No-op when the user has the ad-free upgrade.
    func adInterstitial(isPresented: Binding<Bool>) -> some View {
        overlay {
            if isPresented.wrappedValue {
                AdInterstitialOverlay { isPresented.wrappedValue = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPresented.wrappedValue)
    }
}

private struct AdInterstitialOverlay: View {
    let onDismiss: () -> Void
    @ObservedObject private var ads = AdManager.shared
    @State private var remaining = 10

    var body: some View {
        if ads.isAdFree {
            Color.clear.onAppear(perform: onDismiss)
        } else {
            ZStack {
                Color.black.opacity(0.88).ignoresSafeArea()
                VStack(spacing: 24) {
                    Spacer()
                    VStack(spacing: 10) {
                        Text("Ad")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(UbappTheme.muted)
                        // Replace this rectangle with a GADInterstitialAd or
                        // a full-screen GADBannerView when AdMob is integrated.
                        RoundedRectangle(cornerRadius: UbappRadius.card, style: .continuous)
                            .fill(UbappTheme.surface)
                            .frame(height: 240)
                            .overlay(
                                Text("Advertisement")
                                    .font(.system(size: 15))
                                    .foregroundStyle(UbappTheme.faint)
                            )
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        HStack(spacing: 6) {
                            Text("Skip")
                            if remaining > 0 {
                                Text("(\(remaining))")
                                    .foregroundStyle(UbappTheme.muted)
                            }
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(UbappTheme.surface)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .padding(.bottom, 40)
                }
            }
            .task { await countdown() }
        }
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
