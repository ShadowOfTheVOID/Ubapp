import SwiftUI

/// Host-local play statistics: per-game aggregate counts plus a recent-games
/// log. Reached from the main menu's "More" section.
struct StatBoardView: View {
    @ObservedObject private var store = StatsStore.shared
    @State private var showClearConfirm = false

    private var sortedGames: [(id: String, stat: GameStat)] {
        store.data.games
            .map { (id: $0.key, stat: $0.value) }
            .sorted { $0.stat.playCount > $1.stat.playCount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store.data.games.isEmpty && store.data.recent.isEmpty {
                    Text("No games recorded yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 60)
                } else {
                    byGameSection
                    recentSection
                }
            }
            .padding(20)
        }
        .jamboreeChrome()
        .navigationTitle("Stat board")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { showClearConfirm = true }
                    .disabled(store.data.games.isEmpty && store.data.recent.isEmpty)
            }
        }
        .alert("Clear all stats?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { store.clear() }
        } message: {
            Text("This permanently removes play counts and recent games on this device.")
        }
    }

    @ViewBuilder private var byGameSection: some View {
        if !sortedGames.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("By game")
                    .font(.title3.bold())
                    .foregroundStyle(JamboreeTheme.foreground)
                VStack(spacing: 8) {
                    ForEach(sortedGames, id: \.id) { item in
                        gameCard(item.id, item.stat)
                    }
                }
            }
        }
    }

    private func gameCard(_ id: String, _ stat: GameStat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(StatsCatalog.gameName(id))
                    .font(.headline)
                    .foregroundStyle(JamboreeTheme.foreground)
                Spacer()
                Text("\(stat.playCount) played")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JamboreeTheme.accent)
            }
            ForEach(stat.outcomes.sorted { $0.value > $1.value }, id: \.key) { entry in
                HStack {
                    Text(StatsCatalog.outcomeLabel(entry.key))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(entry.value)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var recentSection: some View {
        if !store.data.recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent games")
                    .font(.title3.bold())
                    .foregroundStyle(JamboreeTheme.foreground)
                VStack(spacing: 8) {
                    ForEach(store.data.recent) { entry in
                        recentRow(entry)
                    }
                }
            }
        }
    }

    private func recentRow(_ e: RecentEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(StatsCatalog.gameName(e.gameId))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JamboreeTheme.foreground)
                Spacer()
                Text(relativeTime(e.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(StatsCatalog.outcomeLabel(e.outcome))
                .font(.caption.weight(.semibold))
                .foregroundStyle(JamboreeTheme.accent)
            if !e.players.isEmpty {
                Text(e.players.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func relativeTime(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .abbreviated
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}

#Preview { NavigationStack { StatBoardView() } }
