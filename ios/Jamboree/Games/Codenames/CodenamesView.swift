import SwiftUI

/// Host's player UI for Codenames. Lobby has team / spymaster pickers; play
/// phase has the 5×5 board, clue input (spymaster), end-turn (operatives).
/// Host screen. Lobby is host-owned (QR, team/spymaster, options, "Start
/// round"). Once the round starts the host plays on the same
/// `CodenamesGuestView` every guest sees, via an in-process loopback, plus a
/// "New game" control the player screen lacks.
struct CodenamesView: View {
    @StateObject private var model = CodenamesViewModel()

    var body: some View {
        Group {
            if model.phase == .lobby {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(alignment: .center, spacing: 16) {
                                VStack(spacing: 4) {
                                    MonoLabel("Hosting · Codenames", color: JamboreeTheme.accent)
                                    Text("Waiting for players")
                                        .font(.system(size: 24, weight: .heavy)).kerning(-0.6)
                                        .foregroundStyle(.white)
                                }
                                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                                              onStop: model.stop)
                                TutorialVoteCard(
                                    state: model.tutorialState, tutorial: GameTutorials.codenames,
                                    onCall: model.callTutorialVote, onVote: model.tutorialVote,
                                    onDismiss: model.dismissTutorial)
                                lobbyView
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: proxy.size.height)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else if let ctx = model.loopbackCtx {
                VStack(spacing: 0) {
                    CodenamesGuestView(ctx: ctx)
                    if model.phase == .gameOver {
                        Button("Rematch · swap teams") { model.newGame() }
                            .buttonStyle(UbPrimaryButtonStyle()).padding(20)
                    }
                }
            }
        }
        .jamboreeChrome()
        .navigationTitle("Codenames")
        .onDisappear { model.stop() }
    }

    private var cnRed: Color { Color(hex: 0xFF5A4A) }
    private var cnBlue: Color { Color(hex: 0x4F9EFF) }

    @ViewBuilder private var lobbyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Your team")
            HStack(spacing: 10) {
                teamButton("Join Red", team: .red, color: cnRed)
                teamButton("Join Blue", team: .blue, color: cnBlue)
            }
            Toggle("I'm spymaster ★", isOn: $model.hostIsSpymaster)
                .onChange(of: model.hostIsSpymaster) { _, on in model.setSpymaster(on) }
                .font(.system(size: 15)).tint(JamboreeTheme.accent)
                .padding(.horizontal, 14).padding(.vertical, 10).ubCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Players · \(model.players.count)")
            VStack(spacing: 8) {
                ForEach(model.players, id: \.id) { p in
                    HStack(spacing: 12) {
                        Avatar(name: p.name, host: p.isHost, size: 30)
                        Text(p.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        if p.isSpymaster {
                            MonoLabel("spy ★", size: 9,
                                      color: p.team == .red ? cnRed : p.team == .blue ? cnBlue : JamboreeTheme.faint)
                        }
                        Spacer()
                        if let t = p.team {
                            MonoLabel(t.name2, size: 9, color: t == .red ? cnRed : cnBlue)
                        }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14).ubCard(radius: JamboreeRadius.row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Options")
            VStack(spacing: 12) {
                Picker("Board size", selection: $model.boardSize) {
                    ForEach(CodenamesOptions.allowedSizes, id: \.self) { n in Text("\(n)").tag(n) }
                }.pickerStyle(.segmented)
                .onChange(of: model.boardSize) { _, v in
                    model.applyOptions(CodenamesOptions(boardSize: v, assassinCount: model.assassinCount))
                }
                Stepper(value: $model.assassinCount, in: 1...3) {
                    Text("Assassins: \(model.assassinCount)")
                }
                .onChange(of: model.assassinCount) { _, v in
                    model.applyOptions(CodenamesOptions(boardSize: model.boardSize, assassinCount: v))
                }
            }
            .font(.system(size: 15)).tint(JamboreeTheme.accent).padding(14).ubCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if model.canStart {
            Button("Start round") { model.start() }.buttonStyle(UbPrimaryButtonStyle())
        } else {
            Text("Need ≥2 per team with a spymaster on each side.")
                .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
        }
    }

    private func teamButton(_ title: String, team: Team, color: Color) -> some View {
        Button { model.joinTeam(team) } label: {
            Text(title)
                .font(.system(size: 15, weight: .bold)).foregroundStyle(color)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: JamboreeRadius.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: JamboreeRadius.button, style: .continuous)
                    .stroke(color.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
final class CodenamesViewModel: ObservableObject {
    private let server = CodenamesServer(hostName: AppSettings.currentHostName)
    @Published var joinUrl: URL?
    @Published var phase: CodenamesPhase = .lobby
    @Published var players: [CodenamesPlayer] = []
    @Published var canStart = false
    @Published var hostIsSpymaster = false
    @Published var boardSize: Int = 25
    @Published var assassinCount: Int = 1
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func startHosting() {
        do {
            joinUrl = try server.start()
            let lb = server.makeLoopback()
            loopback = lb
            loopbackCtx = GuestContext(client: lb, game: "codenames",
                                       yourId: CodenamesServer.hostId,
                                       yourName: server.hostName, replay: [])
        } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func joinTeam(_ t: Team) { server.hostJoinTeam(t) }
    func setSpymaster(_ on: Bool) { server.hostSetSpymaster(on) }
    func applyOptions(_ o: CodenamesOptions) { server.hostSetOptions(o) }
    func start() { server.hostStart() }
    func newGame() { server.hostNewGame() }
    func callTutorialVote() { server.hostCallTutorialVote() }
    func tutorialVote(_ yes: Bool) { server.hostTutorialVote(yes) }
    func dismissTutorial() { server.hostDismissTutorial() }
    func stop() {
        server.stop(); joinUrl = nil
        loopback = nil; loopbackCtx = nil
    }

    private func refresh() {
        let e = server.engine
        phase = e.phase
        players = Array(e.players.values).sorted { $0.id < $1.id }
        canStart = e.canStart
        hostIsSpymaster = e.players[CodenamesServer.hostId]?.isSpymaster ?? false
        if boardSize != e.options.boardSize { boardSize = e.options.boardSize }
        if assassinCount != e.options.assassinCount { assassinCount = e.options.assassinCount }
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
