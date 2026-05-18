import SwiftUI

/// Reusable lobby chrome — "Start hosting" CTA + the QR card guests scan.
/// Used by every browser-tier host view.
///
/// `showJoinCard` is `true` for browser-tier games (guests join via QR or the
/// "Join a game" code). Tag is BLE-proximity / app-peers-only — it has no
/// working code-join path, so it sets `false` and shows its own guidance
/// instead, while still getting the Start/Stop control.
struct HostingChrome: View {
    let joinUrl: URL?
    let onStart: () -> Void
    var onStop: (() -> Void)? = nil
    var showJoinCard: Bool = true

    var body: some View {
        if let url = joinUrl {
            VStack(spacing: 12) {
                if showJoinCard {
                    GroupBox {
                        VStack(spacing: 12) {
                            Text("Guests join here")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .center)
                            if let qr = QRCode.image(for: url.absoluteString) {
                                Image(uiImage: qr)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 240, maxHeight: 240)
                                    .padding(8)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            if let host = url.host, let code = JoinCode.encode(ip: host) {
                                VStack(spacing: 2) {
                                    Text("App code")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(code)
                                        .font(.system(.title, design: .monospaced).bold())
                                        .tracking(2)
                                }
                            }
                            Text(url.absoluteString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Text("Browser guests scan the QR. App guests open \"Join a game\" and type the code or IP.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                if let onStop {
                    Button(role: .destructive, action: onStop) {
                        Label("Stop hosting", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Button(action: onStart) {
                Label("Start hosting", systemImage: "play.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
