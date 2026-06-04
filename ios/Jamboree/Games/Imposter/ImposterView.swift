import SwiftUI

/// Host's player UI for Imposter. The category card / secret word reveal /
/// vote phase happen here; the rich animated UI lives in the browser bundle.
/// Host screen. Lobby is host-owned (QR, category, options, "Start round").
/// Once the round starts the host plays on the same `ImposterGuestView` every
/// guest sees, via an in-process loopback, plus a control bar for the
/// host-only orchestration the player screen lacks (call vote / new round).
struct ImposterView: View {
    @StateObject private var model = ImposterViewModel()

    var body: some View {
        Group {
            if model.phase == .lobby {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(alignment: .center, spacing: 16) {
                                VStack(spacing: 4) {
                                    MonoLabel("Hosting · Imposter", color: JamboreeTheme.accent)
                                    Text("Waiting for players")
                                        .font(.system(size: 24, weight: .heavy)).kerning(-0.6)
                                        .foregroundStyle(.white)
                                }
                                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                                              onStop: model.stop)
                                TutorialVoteCard(
                                    state: model.tutorialState, tutorial: GameTutorials.imposter,
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
                    ImposterGuestView(ctx: ctx)
                    if model.phase == .playing {
                        Button("Call vote") { model.beginVoting() }
                            .buttonStyle(UbPrimaryButtonStyle()).padding(20)
                    } else if model.phase == .result || model.phase == .gameOver {
                        Button("Next round · same room") { model.newRound() }
                            .buttonStyle(UbPrimaryButtonStyle()).padding(20)
                    }
                }
            }
        }
        .jamboreeChrome()
        .navigationTitle("Imposter")
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
                        if p.isHost { MonoLabel("host", size: 9, color: JamboreeTheme.faint) }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: JamboreeRadius.row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Category")
            Picker("Category", selection: $model.selectedCategory) {
                Text("Random").tag(Optional<String>.none)
                ForEach(model.availableCategories, id: \.self) { c in
                    Text(c).tag(Optional<String>.some(c))
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.options.mixedPool)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Options")
            VStack(spacing: 12) {
                Stepper(value: $model.options.imposterCount,
                        in: 1...max(1, model.maxImposterCount)) {
                    Text("Imposters: \(model.options.imposterCount)")
                }
                Toggle("Decoy word for imposters", isOn: $model.options.decoyWord)
                Toggle("Hide category from imposters", isOn: $model.options.hideCategory)
                Toggle("Mixed-category pool", isOn: $model.options.mixedPool)
            }
            .font(.system(size: 15))
            .tint(JamboreeTheme.accent)
            .padding(14)
            .ubCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: model.options) { _, new in model.applyOptions(new) }

        if model.canStart {
            Button("Start round · \(model.players.count) players") { model.start() }
                .buttonStyle(UbPrimaryButtonStyle())
        } else {
            Text("Need at least 3 players to start.")
                .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
        }
    }

}

@MainActor
final class ImposterViewModel: ObservableObject {
    private let server = ImposterServer(hostName: AppSettings.currentHostName)
    @Published var joinUrl: URL?
    @Published var phase: ImposterPhase = .lobby
    @Published var players: [ImposterPlayer] = []
    @Published var canStart = false
    @Published var availableCategories: [String] = []
    @Published var selectedCategory: String?
    @Published var options = ImposterOptions()
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
    @Published var maxImposterCount: Int = 1
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() {
        server.onStateChange = { [weak self] in self?.refresh() }
        server.onStopped = { [weak self] in self?.joinUrl = nil }
        availableCategories = server.engine.availableCategories.sorted()
    }

    func startHosting() {
        do {
            joinUrl = try server.start()
            let lb = server.makeLoopback()
            loopback = lb
            loopbackCtx = GuestContext(client: lb, game: "imposter",
                                       yourId: ImposterServer.hostId,
                                       yourName: server.hostName, replay: [])
        } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func applyOptions(_ o: ImposterOptions) { server.hostSetOptions(o) }
    func start() {
        server.hostStart(category: options.mixedPool ? nil : selectedCategory)
    }
    func beginVoting() { server.hostBeginVoting() }
    func newRound() { server.hostNewRound() }
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
        if options != e.options { options = e.options }
        maxImposterCount = e.maxImposterCount
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
