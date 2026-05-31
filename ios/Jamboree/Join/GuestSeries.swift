import SwiftUI

/// Running series tally a guest sees; mirrors the Kotlin GuestSeriesState in
/// GuestChrome.kt. Parsed from the `series_state` wire message.
struct GuestSeriesState {
    var rounds = 0
    /// Sorted leader-first for a stable banner (JSON objects carry no order).
    var scores: [(key: String, value: Int)] = []

    var banner: String {
        rounds == 0 ? "" : "Series — " + scores.map { "\($0.key) \($0.value)" }.joined(separator: " · ")
    }

    mutating func apply(_ m: [String: Any]) {
        rounds = m["rounds"] as? Int ?? 0
        if let obj = m["scores"] as? [String: Any] {
            scores = obj.compactMap { key, value in (value as? Int).map { (key, $0) } }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        } else {
            scores = []
        }
    }
}

/// Compact "Series — town 2 · mafia 1" banner; renders nothing before round 1.
struct SeriesBanner: View {
    let state: GuestSeriesState
    var body: some View {
        if state.rounds > 0 {
            Text(state.banner).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
