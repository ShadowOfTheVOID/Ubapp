import SwiftUI

/// On-screen host instrumentation, gated behind the **Diagnostics**
/// developer toggle (`AppSettings`). `HostServer` writes connection
/// lifecycle events here; `HostingChrome` renders them when the toggle is
/// on so the host phone can be screen-recorded while debugging join issues.
@MainActor
final class HostDiagnostics: ObservableObject {
    static let shared = HostDiagnostics()
    @Published private(set) var lines: [String] = []
    private var start: Date?

    func reset() { start = Date(); lines = [] }

    nonisolated func log(_ s: String) {
        guard AppSettings.diagnosticsOn else { return }
        Task { @MainActor in
            if self.start == nil { self.start = Date() }
            let t = self.start.map { String(format: "%.1fs", Date().timeIntervalSince($0)) } ?? "—"
            self.lines.append("[\(t)] \(s)")
            if self.lines.count > 60 { self.lines.removeFirst(self.lines.count - 60) }
        }
    }
}
