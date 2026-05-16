import SwiftUI

/// Host's player UI for Werewolf. Same shape as MafiaView, with the extra
/// hunter-shot phase wired in. The browser-side bundle drives every guest;
/// this view is what the host sees on their own phone.
struct WerewolfView: View {
    @StateObject private var model = WerewolfViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                              onStop: model.stop)

                HStack {
                    Text(phaseLabel).font(.headline)
                    Spacer()
                    if model.day > 0 {
                        Text("Day \(model.day)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                switch model.phase {
                case .lobby:
                    TutorialVoteCard(
                        state: model.tutorialState, tutorial: GameTutorials.werewolf,
                        onCall: model.callTutorialVote, onVote: model.tutorialVote,
                        onDismiss: model.dismissTutorial)
                    lobbyView
                case .night: nightView
                case .dayReveal: dayRevealView
                case .dayVote: dayVoteView
                case .hunterShot: hunterShotView
                case .gameOver: gameOverView
                }
            }
            .padding()
        }
        .navigationTitle("Werewolf")
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var lobbyView: some View {
        GroupBox("Players (\(model.players.count))") {
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name)
                    if p.isHost { Text("(host)").foregroundStyle(.secondary).font(.caption) }
                }
            }
        }
        GroupBox("Options") {
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
        if model.canStart {
            Button("Start round") { model.start() }.buttonStyle(.borderedProminent)
        } else {
            Text("Need at least 5 players to start.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var nightView: some View {
        if let role = model.hostRole {
            GroupBox("Your role: \(role.displayName)") {
                Text(role.tagline).font(.callout).foregroundStyle(.secondary)
                if role == .werewolf, !model.fellowWolfNames.isEmpty {
                    Text("Pack: \(model.fellowWolfNames.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if let r = model.hostRole, r == .werewolf {
            picker("Wolves: pick a villager to kill",
                   targets: model.alive.filter { $0.role != .werewolf && $0.id != WerewolfServer.hostId },
                   action: model.submitNight)
        } else if let r = model.hostRole, r == .seer {
            picker("Seer: pick a player to investigate",
                   targets: model.alive.filter { $0.id != WerewolfServer.hostId },
                   action: model.submitNight)
            if let s = model.lastSeerResult {
                GroupBox("Seer findings") {
                    Text("\(model.name(s.targetId)) is \(s.isWerewolf ? "a WEREWOLF." : "not a werewolf.")")
                        .font(.callout)
                }
            }
        } else {
            Text("Waiting for wolves and the seer…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var dayRevealView: some View {
        GroupBox("Last night") {
            if let kid = model.lastKilledId {
                Text("\(model.name(kid)) was killed by the wolves.")
            } else {
                Text("A quiet night. No one died.")
            }
        }
        if !model.hunterShotsThisRound.isEmpty {
            GroupBox("Hunter shots this round") {
                ForEach(model.hunterShotsThisRound.indices, id: \.self) { i in
                    let s = model.hunterShotsThisRound[i]
                    Text("\(model.name(s.hunterId)) took \(model.name(s.targetId)) down.")
                }
            }
        }
        Button("Continue to day vote") { model.advanceFromReveal() }.buttonStyle(.borderedProminent)
    }

    @ViewBuilder private var dayVoteView: some View {
        picker("Vote to lynch", targets: model.alive.filter { $0.id != WerewolfServer.hostId },
               action: { model.submitVote(targetId: $0) },
               extra: ("Skip vote", { model.submitVote(targetId: nil) }))
    }

    @ViewBuilder private var hunterShotView: some View {
        if model.pendingHunterShooter == WerewolfServer.hostId {
            picker("You're the hunter — take one with you",
                   targets: model.alive.filter { $0.id != WerewolfServer.hostId },
                   action: model.submitHunterShot)
        } else if let h = model.pendingHunterShooter {
            Text("Waiting for \(model.name(h)) to fire…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var gameOverView: some View {
        GroupBox("Result") {
            Text(model.winnerLabel).font(.title2.bold())
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name); Spacer()
                    Text(p.role?.displayName ?? "—").foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func picker(_ prompt: String, targets: [WerewolfPlayer],
                        action: @escaping (String) -> Void,
                        extra: (String, () -> Void)? = nil) -> some View {
        GroupBox(prompt) {
            ForEach(targets, id: \.id) { p in
                Button { action(p.id) } label: {
                    HStack { Text(p.name); Spacer() }.padding(.vertical, 6)
                }
            }
            if let (label, run) = extra {
                Button(label, action: run)
            }
        }
    }

    private var phaseLabel: String {
        switch model.phase {
        case .lobby: "Lobby"; case .night: "Night"
        case .dayReveal: "Day reveal"; case .dayVote: "Day vote"
        case .hunterShot: "Hunter shot"; case .gameOver: "Game over"
        }
    }
}

@MainActor
final class WerewolfViewModel: ObservableObject {
    private let server = WerewolfServer(hostName: "Host")
    @Published var joinUrl: URL?
    @Published var phase: WerewolfPhase = .lobby
    @Published var players: [WerewolfPlayer] = []
    @Published var alive: [WerewolfPlayer] = []
    @Published var canStart = false
    @Published var day = 0
    @Published var lastKilledId: String?
    @Published var lastSeerResult: SeerResult?
    @Published var hunterShotsThisRound: [HunterShot] = []
    @Published var pendingHunterShooter: String?
    @Published var fellowWolfNames: [String] = []
    @Published var winnerLabel = ""
    @Published var options = WerewolfOptions()
    @Published var autoWolfCount = true
    @Published var wolfCountValue = 1
    @Published var maxWolfCount = 1
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func applyOptions(_ o: WerewolfOptions) { server.hostSetOptions(o) }

    var hostRole: WerewolfRole? { server.engine.players[WerewolfServer.hostId]?.role }

    func startHosting() {
        do { joinUrl = try server.start() } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func start() { server.hostStart() }
    func advanceFromReveal() { server.advanceFromReveal() }
    func submitNight(targetId: String) { server.hostNightAction(targetId: targetId) }
    func submitVote(targetId: String?) { server.hostDayVote(targetId: targetId) }
    func submitHunterShot(targetId: String) { server.hostHunterShot(targetId: targetId) }
    func callTutorialVote() { server.hostCallTutorialVote() }
    func tutorialVote(_ yes: Bool) { server.hostTutorialVote(yes) }
    func dismissTutorial() { server.hostDismissTutorial() }
    func stop() { server.stop(); joinUrl = nil }

    func name(_ id: String) -> String { server.engine.players[id]?.name ?? id }

    private func refresh() {
        let e = server.engine
        phase = e.phase
        players = Array(e.players.values).sorted { $0.id < $1.id }
        alive = e.alive
        canStart = e.canStart
        day = e.day
        lastKilledId = e.lastNight?.killedId
        lastSeerResult = e.lastSeerResult
        hunterShotsThisRound = e.hunterShotsThisRound
        pendingHunterShooter = e.pendingHunterShooter
        // Only show pack list to the host if they're a wolf.
        if e.players[WerewolfServer.hostId]?.role == .werewolf {
            fellowWolfNames = e.players.values
                .filter { $0.role == .werewolf && $0.id != WerewolfServer.hostId }
                .map(\.name)
        } else {
            fellowWolfNames = []
        }
        if e.phase == .gameOver, let w = e.winner {
            winnerLabel = w == .town ? "Village wins" : "Werewolves win"
        }
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
