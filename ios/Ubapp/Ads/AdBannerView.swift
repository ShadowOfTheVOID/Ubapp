import SwiftUI

/// Lobby / between-rounds banner slot.
/// Replace the placeholder body with GADBannerView once the AdMob SDK is integrated.
struct AdBannerView: View {
    @ObservedObject private var ads = AdManager.shared

    var body: some View {
        if !ads.isAdFree {
            HStack {
                Spacer()
                Text("Ad")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(UbappTheme.muted)
                Spacer()
            }
            .frame(height: 50)
            .background(UbappTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: UbappRadius.card, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: UbappRadius.card, style: .continuous))
        }
    }
}
