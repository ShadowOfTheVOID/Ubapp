import SwiftUI

/// Cross-game social lobby placeholder. The Flutter app had this as a
/// reserved menu entry too — it's intentionally empty and waiting for a
/// future cross-game roster + matchmaker.
struct SocialView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3").font(.largeTitle).foregroundStyle(.secondary)
            Text("Social").font(.title2.bold())
            Text("Reserved for a future cross-game lobby.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ubappChrome()
        .navigationTitle("Social")
    }
}
