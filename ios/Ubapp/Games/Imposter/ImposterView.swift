import SwiftUI

/// Host's player UI for Imposter. The category card / secret word reveal /
/// vote phase happen here; the rich animated UI lives in the browser bundle.
struct ImposterView: View {
    @StateObject private var model = ImposterViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                              onStop: model.stop)

                Text(phaseLabel).font(.headline)

                switch model.phase {
                case .lobby:
                    TutorialVoteCard(
                        state: model.tutorialState, tutorial: GameTutorials.imposter,
                        onCall: model.callTutorialVote, onVote: model.tutorialVote,
                        onDismiss: model.dismissTutorial)
                    lobbyView
                case .playing: playingView
                case .voting: votingView
                case .result, .gameOver: resultView
                }
            }
            .padding()
        }
        .navigationTitle("Imposter")
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
        GroupBox("Category") {
            Picker("Category", selection: $model.selectedCategory) {
                Text("Random").tag(Optional<String>.none)
                ForEach(model.availableCategories, id: \.self) { c in
                    Text(c).tag(Optional<String>.some(c))
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.options.mixedPool)
        }
        GroupBox("Options") {
            Stepper(value: $model.options.imposterCount,
                    in: 1...max(1, model.maxImposterCount)) {
                Text("Imposters: \(model.options.imposterCount)")
            }
            Toggle("Decoy word for imposters", isOn: $model.options.decoyWord)
            Toggle("Hide category from imposters", isOn: $model.options.hideCategory)
            Toggle("Mixed-category pool", isOn: $model.options.mixedPool)
        }
        .onChange(of: model.options) { _, new in model.applyOptions(new) }
        if model.canStart {
            Button("Start round") { model.start() }.buttonStyle(.borderedProminent)
        } else {
            Text("Need at least 3 players to start.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var playingView: some View {
        if !(model.hostIsImposter && model.options.hideCategory) {
            GroupBox("Category") { Text(model.category).font(.title3.bold()) }
        }
        if model.hostIsImposter {
            GroupBox("Your card") {
                Text("IMPOSTER").font(.largeTitle.bold()).foregroundStyle(.red)
                if let decoy = model.hostDecoyWord {
                    Text("Decoy word: \(decoy)").font(.title3.bold())
                    Text("This isn't the real word — bluff carefully.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Bluff your way through.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        } else {
            GroupBox("Your secret word") {
                Text(model.secretWord).font(.largeTitle.bold())
            }
        }
        Button("Call vote") { model.beginVoting() }.buttonStyle(.borderedProminent)
    }

    @ViewBuilder private var votingView: some View {
        GroupBox("Vote: who is the imposter?") {
            ForEach(model.players.filter { $0.id != ImposterServer.hostId }, id: \.id) { p in
                Button { model.vote(p.id) } label: {
                    HStack { Text(p.name); Spacer() }.padding(.vertical, 6)
                }
            }
            Button("Skip vote") { model.vote(nil) }
        }
    }

    @ViewBuilder private var resultView: some View {
        GroupBox("Result") {
            Text(model.winnerLabel).font(.title2.bold())
            if !model.imposterNames.isEmpty {
                let label = model.imposterNames.count == 1 ? "imposter was" : "imposters were"
                Text("The \(label) \(model.imposterNames.joined(separator: ", ")).")
            }
            Text("Word: \(model.secretWord)  ·  Category: \(model.category)")
                .foregroundStyle(.secondary)
        }
        Button("New round") { model.newRound() }.buttonStyle(.borderedProminent)
    }

    private var phaseLabel: String {
        switch model.phase {
        case .lobby: "Lobby"; case .playing: "Playing"
        case .voting: "Voting"; case .result, .gameOver: "Result"
        }
    }
}

@MainActor
final class ImposterViewModel: ObservableObject {
    private let server = ImposterServer(hostName: "Host")
    @Published var joinUrl: URL?
    @Published var phase: ImposterPhase = .lobby
    @Published var players: [ImposterPlayer] = []
    @Published var canStart = false
    @Published var availableCategories: [String] = []
    @Published var selectedCategory: String?
    @Published var category = ""
    @Published var secretWord = ""
    @Published var hostIsImposter = false
    @Published var hostDecoyWord: String?
    @Published var imposterNames: [String] = []
    @Published var winnerLabel = ""
    @Published var options = ImposterOptions()
    @Published var maxImposterCount: Int = 1
    @Published var tutorialState = TutorialVoteCard.State(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() {
        server.onStateChange = { [weak self] in self?.refresh() }
        availableCategories = server.engine.availableCategories.sorted()
    }

    func startHosting() {
        do { joinUrl = try server.start() } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func applyOptions(_ o: ImposterOptions) { server.hostSetOptions(o) }
    func start() {
        server.hostStart(category: options.mixedPool ? nil : selectedCategory)
    }
    func beginVoting() { server.hostBeginVoting() }
    func vote(_ targetId: String?) { server.hostVote(targetId: targetId) }
    func newRound() { server.hostNewRound() }
    func callTutorialVote() { server.hostCallTutorialVote() }
    func tutorialVote(_ yes: Bool) { server.hostTutorialVote(yes) }
    func dismissTutorial() { server.hostDismissTutorial() }
    func stop() { server.stop(); joinUrl = nil }

    private func refresh() {
        let e = server.engine
        phase = e.phase
        players = Array(e.players.values).sorted { $0.id < $1.id }
        canStart = e.canStart
        category = e.category
        secretWord = e.secretWord
        let host = e.players[ImposterServer.hostId]
        hostIsImposter = host?.isImposter == true
        hostDecoyWord = host?.decoyWord
        imposterNames = e.imposterIds.compactMap { e.players[$0]?.name }.sorted()
        if let w = e.winner {
            winnerLabel = w == .town ? "Town wins" : "Imposter wins"
        } else { winnerLabel = "" }
        if options != e.options { options = e.options }
        maxImposterCount = e.maxImposterCount
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}
