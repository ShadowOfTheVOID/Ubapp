import SwiftUI

/// User-facing app preferences, persisted in `UserDefaults`.
///
/// - `hostName` is the display name this device uses when it hosts a
///   browser-tier game (the player id is still `host`).
/// - `diagnosticsEnabled` is a developer toggle that reveals the on-screen
///   host connection log in the hosting screen.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    nonisolated static let hostNameKey = "jamboree.hostName"
    nonisolated static let diagnosticsKey = "jamboree.diagnosticsEnabled"

    @Published var hostName: String {
        didSet { UserDefaults.standard.set(hostName, forKey: Self.hostNameKey) }
    }

    @Published var diagnosticsEnabled: Bool {
        didSet { UserDefaults.standard.set(diagnosticsEnabled, forKey: Self.diagnosticsKey) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.hostNameKey) ?? ""
        hostName = stored.isEmpty ? "Host" : stored
        diagnosticsEnabled = UserDefaults.standard.bool(forKey: Self.diagnosticsKey)
    }

    /// Trimmed host name, never empty. Safe to read from any actor — used by
    /// game views when constructing their server.
    nonisolated static var currentHostName: String {
        let raw = UserDefaults.standard.string(forKey: hostNameKey) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Host" : trimmed
    }

    /// Whether the developer diagnostics log is enabled. Safe from any actor.
    nonisolated static var diagnosticsOn: Bool {
        UserDefaults.standard.bool(forKey: diagnosticsKey)
    }
}
