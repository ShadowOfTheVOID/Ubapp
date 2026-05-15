import SwiftUI

/// Reusable lobby chrome — "Start hosting" CTA + the QR card guests scan.
/// Used by every browser-tier host view.
struct HostingChrome: View {
    let joinUrl: URL?
    let onStart: () -> Void

    var body: some View {
        if let url = joinUrl {
            GroupBox("Guests join here") {
                VStack(alignment: .leading, spacing: 8) {
                    if let qr = QRCode.image(for: url.absoluteString) {
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                            .frame(maxHeight: 200)
                    }
                    Text(url.absoluteString).font(.system(.caption, design: .monospaced))
                    if let host = url.host, let code = JoinCode.encode(ip: host) {
                        HStack(spacing: 6) {
                            Text("App code:").font(.caption).foregroundStyle(.secondary)
                            Text(code).font(.system(.title3, design: .monospaced).bold())
                        }
                    }
                    Text("Browser guests scan the QR. App guests open \"Join a game\" and type the code or IP.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        } else {
            Button("Start hosting", action: onStart).buttonStyle(.borderedProminent)
        }
    }
}
