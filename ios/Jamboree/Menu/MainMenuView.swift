import SwiftUI

struct MainMenuView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    joinCallout
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    section(title: "Host a game", trailing: "\(partyGames.count + cardGames.count) in library") {
                        ForEach(cardGames + partyGames) { tile($0) }
                    }

                    section(title: "On the move", topPadding: 24) {
                        ForEach(proximityGames) { tile($0) }
                    }

                    section(title: "Two-player", topPadding: 24) {
                        ForEach(twoPlayerGames) { tile($0) }
                    }

                    section(title: "More", topPadding: 24) {
                        ForEach(extras) { tile($0) }
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(JamboreeTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .tint(JamboreeTheme.accent)
            .onAppear { ConsentManager.gatherThenStartAds() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PipMark(size: 20)
                Wordmark(size: 17)
                Spacer()
                NavigationLink { SettingsView() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(JamboreeTheme.accent)
                }
            }
            Text("jamboree")
                .font(.system(size: 34, weight: .heavy))
                .kerning(-1.0)
                .foregroundStyle(.white)
            Text("Pass the QR — everyone plays in their browser.")
                .font(.system(size: 13))
                .foregroundStyle(JamboreeTheme.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private var joinCallout: some View {
        NavigationLink { JoinFlowView() } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(JamboreeTheme.accent.opacity(0.22))
                        .frame(width: 44, height: 44)
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(JamboreeTheme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Join a game")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Scan the host's QR or enter a code.")
                        .font(.system(size: 12))
                        .foregroundStyle(JamboreeTheme.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(JamboreeTheme.muted)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .ubAccentCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section + tile

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        trailing: String? = nil,
        topPadding: CGFloat = 0,
        @ViewBuilder content: () -> Content,
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            MonoLabel(title)
            Spacer()
            if let trailing { MonoLabel(trailing, size: 10, color: JamboreeTheme.faint) }
        }
        .padding(.horizontal, 20)
        .padding(.top, topPadding == 0 ? 0 : topPadding)
        .padding(.bottom, 8)

        VStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func tile(_ meta: GameMeta) -> some View {
        NavigationLink { meta.destination } label: {
            HStack(spacing: 14) {
                GameGlyphView(glyph: meta.glyph, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(meta.title)
                        .font(.system(size: 17, weight: .bold))
                        .kerning(-0.3)
                        .foregroundStyle(.white)
                    Text(meta.desc)
                        .font(.system(size: 12))
                        .foregroundStyle(JamboreeTheme.muted)
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        MonoLabel(meta.players, size: 9)
                        if let minutes = meta.minutes { MonoLabel(minutes, size: 9) }
                    }
                    .padding(.top, 3)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(JamboreeTheme.faint)
            }
            .padding(14)
            .ubCard()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Catalog

struct GameMeta: Identifiable {
    let id: String
    let title: String
    let desc: String
    let players: String
    let minutes: String?
    let glyph: GameGlyph
    let destination: AnyView

    init<D: View>(_ id: String, _ title: String, _ desc: String, players: String,
                  minutes: String? = nil, glyph: GameGlyph, @ViewBuilder destination: () -> D) {
        self.id = id
        self.title = title
        self.desc = desc
        self.players = players
        self.minutes = minutes
        self.glyph = glyph
        self.destination = AnyView(destination())
    }
}

private let cardGames: [GameMeta] = [
    GameMeta("crazy8s", "Crazy 8s", "Match suit or rank — eights are wild.",
             players: "2–7", minutes: "8–15 min", glyph: .crazy8s) { CrazyEightsView() },
    GameMeta("cheat", "Cheat", "Claim what you played; get called and take the pile.",
             players: "3–8", minutes: "10–20 min", glyph: .cheat) { CheatView() },
    GameMeta("president", "President", "Shed your hand to climb from Scum to President.",
             players: "4–7", minutes: "15–30 min", glyph: .president) { PresidentView() },
    GameMeta("bluffmarket", "Bluff Market", "Trade face-down. One bomb is worth −25.",
             players: "3–6", minutes: "6–12 min", glyph: .bluffMarket) { BluffMarketView() },
]

private let partyGames: [GameMeta] = [
    GameMeta("mafia", "Mafia", "Mafia kill by night; the town hangs by day.",
             players: "5–12", minutes: "15–30 min", glyph: .mafia) { MafiaView() },
    GameMeta("werewolf", "Werewolf", "Seer, Doctor, Hunter. Day vote, night kills.",
             players: "5–14", minutes: "20–40 min", glyph: .werewolf) { WerewolfView() },
    GameMeta("imposter", "Imposter", "Everyone shares a word — except one. Find the fake.",
             players: "4–10", minutes: "5–10 min", glyph: .imposter) { ImposterView() },
    GameMeta("codenames", "Code Words", "Word-association duel for two teams.",
             players: "4+", glyph: .symbol("square.grid.3x3.fill")) { CodenamesView() },
    GameMeta("secrethitler", "Hidden Agenda", "Politics, lies, and hidden roles.",
             players: "5–10", glyph: .symbol("person.crop.rectangle.stack.fill")) { SecretHitlerView() },
    GameMeta("bureaucrat", "The Bureaucrat", "Deny every request — until a citizen finds the loophole.",
             players: "3–10", minutes: "10–20 min", glyph: .symbol("doc.text.magnifyingglass")) { BureaucratView() },
]

private let proximityGames: [GameMeta] = [
    GameMeta("tag", "Tag", "BLE proximity tag in the room.",
             players: "2+", glyph: .symbol("antenna.radiowaves.left.and.right")) { TagLobbyView() },
    GameMeta("realtime", "Real-time", "Sandbox realtime networking demo.",
             players: "2+", glyph: .symbol("bolt.fill")) { RealtimeView() },
]

private let twoPlayerGames: [GameMeta] = [
    GameMeta("tictactoe", "Tic-Tac-Toe", "Three in a row.",
             players: "2", glyph: .symbol("number")) { TicTacToeView() },
    GameMeta("connectfour", "Four in a Row", "Four in a row, drop tokens.",
             players: "2", glyph: .symbol("circle.grid.3x3.fill")) { ConnectFourView() },
]

private let extras: [GameMeta] = [
    GameMeta("statboard", "Stat board", "Play counts and recent games.",
             players: "—", glyph: .symbol("chart.bar.fill")) { StatBoardView() },
]

#Preview { MainMenuView() }
