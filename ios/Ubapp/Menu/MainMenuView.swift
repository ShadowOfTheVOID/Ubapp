import SwiftUI

struct MainMenuView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    joinCallout

                    MenuSection(title: "Party games", subtitle: "Pass the QR — guests play in their browser.") {
                        gameTile("Mafia", "Hidden roles, find the killer in the dark.") { MafiaView() }
                        gameTile("Werewolf", "Moonlight whodunit with a hunter twist.") { WerewolfView() }
                        gameTile("Imposter", "Bluff your way through a secret word.") { ImposterView() }
                        gameTile("Codenames", "Word association duel for two teams.") { CodenamesView() }
                        gameTile("Crazy Eights", "Race to empty your hand.") { CrazyEightsView() }
                        gameTile("Cheat", "Bluff your way out by claiming the right rank — or call BS.") { CheatView() }
                        gameTile("President", "Shed your hand, win social status, swap cards next round.") { PresidentView() }
                        gameTile("Bluff Market", "Trade face-down cards. Avoid the Bomb.") { BluffMarketView() }
                        gameTile("Secret Hitler", "Politics, lies, and hidden roles.") { SecretHitlerView() }
                    }

                    MenuSection(title: "On the move", subtitle: "Get up, walk around, use your phone's radios.") {
                        gameTile("Tag", "BLE proximity tag in the room.", systemImage: "antenna.radiowaves.left.and.right") { TagLobbyView() }
                        gameTile("Real-time", "Sandbox realtime networking demo.", systemImage: "bolt.fill") { RealtimeView() }
                    }

                    MenuSection(title: "Two-player", subtitle: "Quick turn-based classics for one phone.") {
                        gameTile("Tic-Tac-Toe", "Three in a row.") { TicTacToeView() }
                        gameTile("Connect Four", "Four in a row, drop tokens.") { ConnectFourView() }
                    }

                    MenuSection(title: "More", subtitle: nil) {
                        gameTile("Social", "Friends, chat, presence demo.", systemImage: "person.2.fill") { SocialView() }
                        gameTile("Stat board", "Play counts and recent games.", systemImage: "chart.bar.fill") { StatBoardView() }
                    }
                }
                .padding(20)
            }
            .ubappChrome()
            .navigationTitle("Ubapp")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
    }

    private var joinCallout: some View {
        NavigationLink { JoinFlowView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title)
                    .frame(width: 44, height: 44)
                    .background(UbappTheme.accent.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Join a game").font(.headline)
                    Text("Scan a QR or type an app code.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(14)
            .background(UbappTheme.accent.opacity(0.12))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(UbappTheme.accent.opacity(0.5), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func gameTile<Destination: View>(
        _ title: String,
        _ subtitle: String,
        systemImage: String? = nil,
        @ViewBuilder destination: @escaping () -> Destination,
    ) -> some View {
        NavigationLink(destination: destination) {
            GameTileRow(title: title, subtitle: subtitle, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct MenuSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(UbappTheme.foreground)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 8) {
                content
            }
        }
    }
}

private struct GameTileRow: View {
    let title: String
    let subtitle: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(UbappTheme.accent.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: systemImage ?? "gamecontroller.fill")
                    .foregroundStyle(UbappTheme.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(UbappTheme.foreground)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview { MainMenuView() }
