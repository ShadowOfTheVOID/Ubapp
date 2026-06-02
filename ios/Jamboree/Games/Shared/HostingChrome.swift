import SwiftUI
import UIKit

/// Reusable lobby chrome — "Start hosting" CTA + the QR card guests scan.
/// Used by every browser-tier host view.
struct HostingChrome: View {
    let joinUrl: URL?
    let onStart: () -> Void
    var onStop: (() -> Void)? = nil
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var diag = HostDiagnostics.shared
    @State private var copied = false

    var body: some View {
        if let url = joinUrl {
            VStack(spacing: 12) {
                qrCard(url: url)
                AdBannerView(placement: .lobby)
                if settings.diagnosticsEnabled && !diag.lines.isEmpty {
                    diagnostics
                }
                if let onStop {
                    Button(action: onStop) {
                        Label("Stop hosting", systemImage: "stop.circle")
                    }
                    .buttonStyle(UbSecondaryButtonStyle())
                    .tint(JamboreeTheme.accent)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            Button("Start hosting", action: onStart)
                .buttonStyle(UbPrimaryButtonStyle())
        }
    }

    private func qrCard(url: URL) -> some View {
        let code = url.host.flatMap { JoinCode.encode(ip: $0) }
        return VStack(spacing: 14) {
            QRCodeView(string: url.absoluteString, size: 210)

            if let code {
                HStack(spacing: 10) {
                    MonoLabel("Code", size: 11)
                    MonoValue(text: code, size: 26, weight: .bold, tracking: 3)
                    Button {
                        UIPasteboard.general.string = code
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 13))
                            .foregroundStyle(copied ? JamboreeTheme.online : JamboreeTheme.muted)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            MonoValue(text: url.host.map { "\($0):\(url.port ?? Int(JoinCode.defaultPort))" } ?? url.absoluteString,
                      size: 11, weight: .regular, color: JamboreeTheme.faint)

            Text("Browser guests scan the QR. App guests open “Join a game” and tap this host under “Nearby hosts” — or type the code.")
                .font(.system(size: 12))
                .foregroundStyle(JamboreeTheme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .ubCard(radius: JamboreeRadius.hero)
    }

    private var diagnostics: some View {
        ScrollView {
            Text(diag.lines.joined(separator: "\n"))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(JamboreeTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 200)
        .padding(14)
        .ubCard()
    }
}
