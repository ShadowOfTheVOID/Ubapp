import SwiftUI

/// Host's player UI for Werewolf. Same shape as MafiaView, with the extra
/// hunter-shot phase wired in. The browser-side bundle drives every guest;
/// this view is what the host sees on their own phone.
/// Host screen. Lobby is host-owned (QR, options, "Start round"); once the
/// round starts the host plays on the same `WerewolfGuestView` every guest
/// sees, via an in-process loopback, plus a control bar to advance past the
/// night reveal.
struct WerewolfView: View {
    @StateObject private var model = WerewolfViewModel()

    var body: some View {
        Group {
            if model.phase == .lobby {
                GeometryReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            VStack(alignment: .center, spacing: 16) {
                                VStack(spacing: 4) {
                                    MonoLabel("Hosting · Werewolf", color: UbappTheme.accent)
                                    Text("Waiting for players")
                                        .font(.system(size: 24, weight: .heavy)).kerning(-0.6)
                                        .foregroundStyle(.white)
                                }
                                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                                              onStop: model.stop)
                                TutorialVoteCard(
                                    state: model.tutorialState, tutorial: GameTutorials.werewolf,
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
                    WerewolfGuestView(ctx: ctx)
                    if model.phase == .dayReveal {
                        Button("Continue to day vote") { model.advanceFromReveal() }
                            .buttonStyle(UbPrimaryButtonStyle())
                            .padding(20)
                    }
                }
            }
        }
        .ubappChrome()
        .navigationTitle("Werewolf")
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
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: UbappRadius.row)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Options")
            VStack(spacing: 12) {
            Toggle("Auto-balance wolf count", isOn: $model.autoWolfCount)
                .onChange(of: model.autoWolfCount) { _, on in
                    model.applyOptions(WerewolfOptions(
                        wolfCount: on ? nil : model.wolfCountValue,
                        seerEnabled: model.options.seerEnabled,
                        hunterEnabled: model.options.hunterEnabled))
                }
            if !model.autoWolfCount {
                Stepper(value: $model.wolfCountValue,
                        in: 1...max(1, model.maxWolfCount)) {
                    Text("Wolves: \(model.wolfCountValue)")
                }
                .onChange(of: model.wolfCountValue) { _, v in
                    model.applyOptions(WerewolfOptions(
                        wolfCount: v,
                        seerEnabled: model.options.seerEnabled,
                        hunterEnabled: model.options.hunterEnabled))
                }
            }
            Toggle("Seer", isOn: Binding(
                get: { model.options.seerEnabled },
                set: { model.applyOptions(WerewolfOptions(
                    wolfCount: model.autoWolfCount ? nil : model.wolfCountValue,
                    seerEnabled: $0,
                    hunterEnabled: model.options.hunterEnabled)) }))
            Toggle("Hunter (6+ players)", isOn: Binding(
                get: { model.options.hunterEnabled },
                set: { model.applyOptions(WerewolfOptions(
                    wolfCount: model.autoWolfCount ? nil : model.wolfCountValue,
                    seerEnabled: model.options.seerEnabled,
                    hunterEnabled: $0)) }))
            }
            .font(.system(size: 15))
            .tint(UbappTheme.accent)
            .padding(14)
            .ubCard()
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if model.canStart {
            Button("Start round · \(model.players.count) players") { model.start() }
                .buttonStyle(UbPrimaryButtonStyle())
        } else {
            Text("Need at least 5 players to start.")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
        }
    }

}

@MainActor
final class WerewolfViewModel: ObservableObject {
    private let server = WerewolfServer(hostName: AppSettings.currentHostName)
    @Published var joinUrl: URL?
    @Published var phase: WerewolfPhase = .lobby
    @Published var players: [WerewolfPlayer] = []
    @Published var canStart = false
    @Published var options = WerewolfOptions()
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
    @Published var autoWolfCount = true
    @Published var wolfCountValue = 1
    @Published var maxWolfCount = 1
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func applyOptions(_ o: WerewolfOptions) { server.hostSetOptions(o) }

    func startHosting() {
        do {
            joinUrl = try server.start()
            let lb = server.makeLoopback()
            loopback = lb
            loopbackCtx = GuestContext(client: lb, game: "werewolf",
                                       yourId: WerewolfServer.hostId,
                                       yourName: server.hostName, replay: [])
        } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func start() { server.hostStart() }
    func advanceFromReveal() { server.advanceFromReveal() }
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
        autoWolfCount = e.options.wolfCount == nil
        maxWolfCount = e.maxWolfCount
        if let c = e.options.wolfCount, wolfCountValue != c { wolfCountValue = c }
        else if e.options.wolfCount == nil && wolfCountValue == 1 {
            wolfCountValue = max(1, min(e.players.count - 3, e.players.count / 5))
        }
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
