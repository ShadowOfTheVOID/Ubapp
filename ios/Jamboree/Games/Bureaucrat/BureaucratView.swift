import SwiftUI

/// Host screen for The Bureaucrat. The lobby is host-owned (QR, options,
/// Start); once a round begins the host plays on the *same* player screen
/// every guest sees (`BureaucratGuestView`) via an in-process loopback, plus a
/// control bar for the two orchestration steps the player screen lacks:
/// calling a round for the Bureaucrat and advancing to the next round.
struct BureaucratView: View {
    @StateObject private var model = BureaucratViewModel()

    var body: some View {
        Group {
            if model.phase == .lobby {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(alignment: .center, spacing: 16) {
                                // Updated lobby header with GlyphBureaucrat
                                HStack(spacing: 14) {
                                    GlyphBureaucrat(size: 56)
                                    VStack(alignment: .leading, spacing: 4) {
                                        MonoLabel("Hosting · The Bureaucrat", color: UbappTheme.accent)
                                        Text("Waiting for players")
                                            .font(.system(size: 24, weight: .heavy)).kerning(-0.6)
                                            .foregroundStyle(.white)
                                    }
                                }
                                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting, onStop: model.stop)
                                TutorialVoteCard(state: model.tutorialState, tutorial: GameTutorials.bureaucrat,
                                                 onCall: model.callTutorialVote, onVote: model.tutorialVote,
                                                 onDismiss: model.dismissTutorial)
                                lobbyView
                            }
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 480).frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: proxy.size.height).frame(maxWidth: .infinity)
                    }
                }
            } else if let ctx = model.loopbackCtx {
                VStack(spacing: 0) {
                    BureaucratGuestView(ctx: ctx)
                    if model.phase == .arguing {
                        Button("Bureaucrat survives the round") { model.survive() }
                            .buttonStyle(UbPrimaryButtonStyle()).padding(20)
                    } else if model.phase == .roundOver {
                        Button("Next round") { model.nextRound() }
                            .buttonStyle(UbPrimaryButtonStyle()).padding(20)
                    }
                }
            }
        }
        .ubappChrome()
        .navigationTitle("The Bureaucrat")
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var lobbyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Players · \(model.players.count)")
            VStack(spacing: 8) {
                ForEach(model.players, id: \.id) { p in
                    HStack(spacing: 12) {
                        Avatar(name: p.name, host: p.isHost, size: 30)
                        Text(p.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        if p.isHost { MonoLabel("host", size: 9, color: UbappTheme.faint) }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14).ubCard(radius: UbappRadius.row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Options")
            VStack(spacing: 12) {
                Stepper(value: Binding(
                    get: { model.options.targetScore },
                    set: { var o = model.options; o.targetScore = $0; model.setOptions(o) }),
                        in: 3...50) { Text("Target score: \(model.options.targetScore)") }
                Stepper(value: Binding(
                    get: { model.options.challengeTokens },
                    set: { var o = model.options; o.challengeTokens = $0; model.setOptions(o) }),
                        in: 1...9) { Text("Loopholes each: \(model.options.challengeTokens)") }
                Stepper(value: Binding(
                    get: { model.options.rebuttalSeconds },
                    set: { var o = model.options; o.rebuttalSeconds = $0; model.setOptions(o) }),
                        in: 5...120, step: 5) { Text("Rebuttal seconds: \(model.options.rebuttalSeconds)") }
                Toggle("AI rebuttal check (falls back to timer)", isOn: Binding(
                    get: { model.options.aiAssist },
                    set: { var o = model.options; o.aiAssist = $0; model.setOptions(o) }))
                HStack {
                    Text("Rebuttal mode")
                    Spacer()
                    Picker("Rebuttal mode", selection: Binding(
                        get: { model.options.rebuttalMode },
                        set: { var o = model.options; o.rebuttalMode = $0; model.setOptions(o) }
                    )) {
                        Text("Type").tag("type")
                        Text("Speak").tag("speak")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }
            }
            .font(.system(size: 15)).tint(UbappTheme.accent).padding(14).ubCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if model.canStart {
            Button("Start game · \(model.players.count) players") { model.start() }
                .buttonStyle(UbPrimaryButtonStyle())
        } else {
            Text("Need at least 3 players to start.")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
        }
    }

}

// MARK: - GlyphBureaucrat (shared atom — also used in BureaucratGuestView)

/// Square bureaucrat glyph icon — surfaceHi tile with a rotated document
/// outline and a solid accent bar inside.
struct GlyphBureaucrat: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(UbappTheme.surfaceHi)

            let rectW = size * 0.62
            let rectH = size * 0.42
            let strokeW: CGFloat = max(2, size * 0.045)

            ZStack {
                RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                    .stroke(UbappTheme.accent, lineWidth: strokeW)
                    .frame(width: rectW, height: rectH)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(UbappTheme.accent)
                    .frame(width: rectW * 0.64, height: max(2, rectH * 0.175))
            }
            .rotationEffect(.degrees(-9))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - BureaucratViewModel (unchanged)

@MainActor
final class BureaucratViewModel: ObservableObject {
    private let server = BureaucratServer(hostName: AppSettings.currentHostName)
    @Published var joinUrl: URL?
    @Published var phase: BureaucratPhase = .lobby
    @Published var players: [BureaucratPlayer] = []
    @Published var canStart = false
    @Published var options = BureaucratOptions()
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0, result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func setOptions(_ o: BureaucratOptions) { server.hostSetOptions(o) }

    func callTutorialVote() { server.hostCallTutorialVote() }
    func tutorialVote(_ yes: Bool) { server.hostTutorialVote(yes) }
    func dismissTutorial() { server.hostDismissTutorial() }

    func startHosting() {
        do {
            joinUrl = try server.start()
            let lb = server.makeLoopback()
            loopback = lb
            loopbackCtx = GuestContext(client: lb, game: "bureaucrat",
                                       yourId: BureaucratServer.hostId, yourName: server.hostName, replay: [])
        } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func start() { server.hostStart() }
    func survive() { server.hostSurvive() }
    func nextRound() { server.hostNextRound() }
    func stop() { server.stop(); joinUrl = nil; loopback = nil; loopbackCtx = nil }

    private func refresh() {
        let e = server.engine
        phase = e.phase
        players = e.players.values.sorted { $0.id < $1.id }
        canStart = e.canStart
        if options != e.options { options = e.options }
        let v = e.tutorialVote
        tutorialState = .init(isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
                              eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
