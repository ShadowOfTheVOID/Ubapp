import SwiftUI

/// Black + neon-magenta chrome for the menu and non-game shared screens
/// (Social, Join). Per-game views set their own palettes and are not
/// expected to inherit this — apply it on each non-game root, not on the
/// enclosing `NavigationStack`, so pushed game screens render normally.
enum UbappTheme {
    static let accent = Color(red: 1.0, green: 0.180, blue: 0.533) // #FF2E88
    static let background = Color.black
    static let foreground = Color.white
}

private struct UbappChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(UbappTheme.background.ignoresSafeArea())
            .tint(UbappTheme.accent)
            .foregroundStyle(UbappTheme.foreground)
            .toolbarBackground(UbappTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

extension View {
    func ubappChrome() -> some View { modifier(UbappChromeModifier()) }
}
