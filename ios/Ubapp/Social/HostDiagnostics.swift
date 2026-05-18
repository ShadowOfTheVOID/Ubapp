import SwiftUI

/// Temporary on-screen instrumentation for the "guest stuck on Connecting…"
/// investigation. `HostServer` writes lifecycle events here; `HostingChrome`
/// renders them so the host phone can be screen-recorded. Remove once the
/// cause is found.
@MainActor
final class HostDiagnostics: ObservableObject {
    static let shared = HostDiagnostics()
    @Published private(set) var lines: [String] = []
    private var start: Date?

    func reset() { start = Date(); lines = [] }

    nonisolated func log(_ s: String) {
        Task { @MainActor in
            if self.start == nil { self.start = Date() }
            let t = self.start.map { String(format: "%.1fs", Date().timeIntervalSince($0)) } ?? "—"
            self.lines.append("[\(t)] \(s)")
            if self.lines.count > 60 { self.lines.removeFirst(self.lines.count - 60) }
        }
    }
}
