import SwiftUI

/// Brand tokens for the Ubapp UI redesign — black canvas, neon-magenta
/// accent, system sans + monospaced labels. These are the single source of
/// truth used by every redesigned screen and atom (`UbappKit.swift`).
///
/// Per-game views may still set their own palettes, but the shared chrome
/// (menu, lobby, join, settings) and the new atoms read from here. Apply
/// `ubappChrome()` on each non-game root rather than the enclosing
/// `NavigationStack`, so pushed game screens still render normally.
enum UbappTheme {
    // Core brand
    static let accent = Color(hex: 0xFF2E88)        // primary action, host pip, focus
    static let onAccent = Color(hex: 0x2A0010)      // ink on magenta
    static let foreground = Color.white             // body text, guest pips

    // Backgrounds
    static let background = Color.black              // #000000 app bg
    static let canvas = Color(hex: 0x0A0A0A)         // screen canvas
    static let surface = Color(hex: 0x141416)        // card / list-row bg
    static let surfaceHi = Color(hex: 0x1C1C1F)      // hover / pressed / glyph tile

    // Lines & text tiers
    static let line = Color.white.opacity(0.08)         // hairline dividers
    static let lineStrong = Color.white.opacity(0.14)   // button outline
    static let muted = Color.white.opacity(0.58)        // secondary text
    static let faint = Color.white.opacity(0.38)        // tertiary / metadata

    // Accent fills
    static let accentSoft = Color(hex: 0xFF2E88).opacity(0.14)  // selected-row fill
    static let accentLine = Color(hex: 0xFF2E88).opacity(0.45)  // selected-row border

    // Status
    static let online = Color(hex: 0x3DDC84)         // connected pip
}

/// Corner radii from the spec: chips 8, buttons 12, rows 14, cards 16,
/// panels 18, hero blocks 22.
enum UbappRadius {
    static let chip: CGFloat = 8
    static let button: CGFloat = 12
    static let row: CGFloat = 14
    static let card: CGFloat = 16
    static let panel: CGFloat = 18
    static let hero: CGFloat = 22
}

extension Color {
    /// 0xRRGGBB literal initializer for brand tokens.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1,
        )
    }
}

private struct UbappChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(UbappTheme.canvas.ignoresSafeArea())
            .tint(UbappTheme.accent)
            .foregroundStyle(UbappTheme.foreground)
            .toolbarBackground(UbappTheme.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func ubappChrome() -> some View { modifier(UbappChromeModifier()) }
}
