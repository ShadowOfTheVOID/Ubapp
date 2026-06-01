import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// Reusable brand atoms for the redesigned shared screens. Everything here
// reads from `JamboreeTheme` / `JamboreeRadius` — no literal colors or sizes.

// MARK: - Typography

/// Uppercase monospaced micro-label (codes, section headers, metadata).
/// Mirrors the `Mono` atom: 0.14em tracking, uppercase, 9–11px.
struct MonoLabel: View {
    let text: String
    var size: CGFloat = 11
    var color: Color = JamboreeTheme.muted

    init(_ text: String, size: CGFloat = 11, color: Color = JamboreeTheme.muted) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .medium, design: .monospaced))
            .tracking(size * 0.14)
            .foregroundStyle(color)
    }
}

/// Monospaced value text (room codes, IP, timestamps) — not uppercased.
struct MonoValue: View {
    let text: String
    var size: CGFloat = 13
    var weight: Font.Weight = .bold
    var tracking: CGFloat = 0
    var color: Color = JamboreeTheme.foreground

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .monospaced))
            .tracking(tracking)
            .foregroundStyle(color)
    }
}

// MARK: - Brand marks

/// 4-pip die-face mark; the chosen pip (default top-left) is magenta.
struct PipMark: View {
    var size: CGFloat = 24
    var color: Color = .white
    var accentIndex: Int = 0

    var body: some View {
        let r = size * 0.22
        let inset = size * 0.18
        let positions: [CGPoint] = [
            CGPoint(x: inset + r / 2, y: inset + r / 2),
            CGPoint(x: size - inset - r / 2, y: inset + r / 2),
            CGPoint(x: inset + r / 2, y: size - inset - r / 2),
            CGPoint(x: size - inset - r / 2, y: size - inset - r / 2),
        ]
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i == accentIndex ? JamboreeTheme.accent : color)
                    .frame(width: r, height: r)
                    .position(positions[i])
            }
        }
        .frame(width: size, height: size)
    }
}

/// `jamboree` wordmark with optional magenta dot.
struct Wordmark: View {
    var size: CGFloat = 22
    var color: Color = .white
    var dot: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: size * 0.04) {
            Text("jamboree")
                .font(.system(size: size, weight: .heavy))
                .kerning(-size * 0.04)
                .foregroundStyle(color)
            if dot {
                Circle()
                    .fill(JamboreeTheme.accent)
                    .frame(width: size * 0.16, height: size * 0.16)
                    .offset(y: -size * 0.02)
            }
        }
    }
}

/// Round guest/host avatar — host is solid magenta, guest is a faint chip.
struct Avatar: View {
    let name: String
    var host: Bool = false
    var size: CGFloat = 28

    var body: some View {
        Text(String(name.prefix(1)))
            .font(.system(size: size * 0.42, weight: .bold))
            .kerning(-size * 0.02)
            .foregroundStyle(host ? JamboreeTheme.onAccent : JamboreeTheme.foreground)
            .frame(width: size, height: size)
            .background(host ? JamboreeTheme.accent : Color.white.opacity(0.10))
            .clipShape(Circle())
            .overlay(host ? nil : Circle().stroke(JamboreeTheme.line, lineWidth: 1))
    }
}

// MARK: - Buttons

/// Filled magenta primary action.
struct UbPrimaryButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 16
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .bold))
            .kerning(-0.2)
            .foregroundStyle(JamboreeTheme.onAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(JamboreeTheme.accent.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(RoundedRectangle(cornerRadius: JamboreeRadius.button, style: .continuous))
    }
}

/// Outlined translucent secondary action.
struct UbSecondaryButtonStyle: ButtonStyle {
    var fontSize: CGFloat = 15
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(JamboreeTheme.foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: JamboreeRadius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: JamboreeRadius.button, style: .continuous)
                    .stroke(JamboreeTheme.line, lineWidth: 1),
            )
    }
}

// MARK: - Containers

extension View {
    /// Surface card with hairline border at the given radius.
    func ubCard(radius: CGFloat = JamboreeRadius.card,
                fill: Color = JamboreeTheme.surface,
                stroke: Color = JamboreeTheme.line) -> some View {
        self
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: 1),
            )
    }

    /// Accent-tinted hero/callout container (join CTA, suit picker).
    func ubAccentCard(radius: CGFloat = JamboreeRadius.card) -> some View {
        ubCard(radius: radius, fill: JamboreeTheme.accentSoft, stroke: JamboreeTheme.accentLine)
    }
}

// MARK: - QR

/// Renders a scannable QR for the given string using CoreImage. Falls back
/// to an empty surface if generation fails.
struct QRCodeView: View {
    let string: String
    var size: CGFloat = 200

    private static let context = CIContext()

    var body: some View {
        Group {
            if let image = qrImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
            }
        }
        .frame(width: size, height: size)
        .padding(size * 0.05)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var qrImage: UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cg = Self.context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
