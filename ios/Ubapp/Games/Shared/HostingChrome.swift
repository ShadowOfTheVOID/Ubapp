import SwiftUI

/// Reusable lobby chrome — "Start hosting" CTA + the QR card guests scan.
/// Used by every browser-tier host view.
struct HostingChrome: View {
    let joinUrl: URL?
    let onStart: () -> Void

    var body: some View {
        if let url = joinUrl {
            GroupBox("Guests join here") {
                VStack(alignment: .leading) {
                    if let qr = QRCode.image(for: url.absoluteString) {
                        Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                            .frame(maxHeight: 200)
                    }
                    Text(url.absoluteString).font(.system(.caption, design: .monospaced))
                }
            }
        } else {
            Button("Start hosting", action: onStart).buttonStyle(.borderedProminent)
        }
    }
}
