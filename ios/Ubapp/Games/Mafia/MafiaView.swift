import SwiftUI
import CoreImage.CIFilterBuiltins

/// Host's player UI: shows the QR for guests to join, the lobby roster, and
/// per-phase action UI. The host plays as the special player with id
/// MafiaServer.hostId (no WebSocket connection needed).
struct MafiaView: View {
    @StateObject private var model = MafiaViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting)

                phaseHeader

                if model.phase == .lobby {
                    TutorialVoteCard(
                        state: model.tutorialState,
                        tutorial: GameTutorials.mafia,
                        onCall: model.callTutorialVote,
                        onVote: model.tutorialVote,
                        onDismiss: model.dismissTutorial,
                    )
                    lobbyView
                }
                else if model.phase == .night { nightView }
                else if model.phase == .dayReveal { dayRevealView }
                else if model.phase == .dayVote { dayVoteView }
                else if model.phase == .gameOver { gameOverView }
            }
            .padding()
        }
        .navigationTitle("Mafia")
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var phaseHeader: some View {
        HStack {
            Text(phaseLabel).font(.headline)
            Spacer()
            Text("Day \(model.day)").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var lobbyView: some View {
        GroupBox("Players (\(model.players.count))") {
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name)
                    if p.isHost { Text("(host)").foregroundStyle(.secondary).font(.caption) }
                    Spacer()
                }
            }
        }
        GroupBox("Options") {
            Toggle("Auto-balance mafia count", isOn: $model.autoMafiaCount)
                .onChange(of: model.autoMafiaCount) { _, on in
                    model.applyOptions(MafiaOptions(
                        mafiaCount: on ? nil : model.mafiaCountValue,
                        doctorEnabled: model.options.doctorEnabled))
                }
            if !model.autoMafiaCount {
                Stepper(value: $model.mafiaCountValue,
                        in: 1...max(1, model.maxMafiaCount)) {
                    Text("Mafia: \(model.mafiaCountValue)")
                }
                .onChange(of: model.mafiaCountValue) { _, v in
                    model.applyOptions(MafiaOptions(
                        mafiaCount: v, doctorEnabled: model.options.doctorEnabled))
                }
            }
            Toggle("Doctor", isOn: Binding(
                get: { model.options.doctorEnabled },
                set: { model.applyOptions(MafiaOptions(
                    mafiaCount: model.autoMafiaCount ? nil : model.mafiaCountValue,
                    doctorEnabled: $0)) }))
        }
        if model.canStart {
            Button("Start round") { model.start() }.buttonStyle(.borderedProminent)
        } else {
            Text("Need at least 4 players to start.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var nightView: some View {
        if let role = model.hostRole {
            GroupBox("Your role: \(role.displayName)") {
                Text(role.tagline).font(.callout).foregroundStyle(.secondary)
            }
        }
        if let role = model.hostRole, role.hasNightAction {
            let targets = model.alive.filter { $0.id != MafiaServer.hostId || role == .doctor }
            targetPicker(prompt: role == .mafia ? "Pick a target to kill" : "Pick someone to save",
                         targets: targets, kind: "night")
        } else {
            Text("Waiting for mafia and doctor to act…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var dayRevealView: some View {
        GroupBox("Last night") {
            if let kid = model.lastKilledId {
                Text("\(model.name(kid)) was killed.")
            } else if model.lastSavedId != nil {
                Text("The doctor saved someone — no one died.")
            } else {
                Text("A quiet night. No one died.")
            }
        }
        Button("Continue to day vote") { model.advanceFromReveal() }.buttonStyle(.borderedProminent)
    }

    @ViewBuilder private var dayVoteView: some View {
        targetPicker(prompt: "Vote to eliminate",
                     targets: model.alive.filter { $0.id != MafiaServer.hostId },
                     kind: "vote", allowSkip: true)
    }

    @ViewBuilder private var gameOverView: some View {
        GroupBox("Result") {
            Text(model.winnerLabel).font(.title2.bold())
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name)
                    Spacer()
                    Text(p.role?.displayName ?? "—").foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func targetPicker(prompt: String, targets: [MafiaPlayer], kind: String, allowSkip: Bool = false) -> some View {
        GroupBox(prompt) {
            ForEach(targets, id: \.id) { p in
                Button {
                    if kind == "night" { model.submitNight(targetId: p.id) }
                    else { model.submitVote(targetId: p.id) }
                } label: {
                    HStack { Text(p.name); Spacer() }
                        .padding(.vertical, 6)
                }
            }
            if allowSkip {
                Button("Skip vote") { model.submitVote(targetId: nil) }
            }
        }
    }

    private var phaseLabel: String {
        switch model.phase {
        case .lobby: "Lobby"; case .night: "Night"
        case .dayReveal: "Day reveal"; case .dayVote: "Day vote"; case .gameOver: "Game over"
        }
    }
}

@MainActor
final class MafiaViewModel: ObservableObject {
    private let server = MafiaServer(hostName: "Host")
    @Published var joinUrl: URL?
    @Published var phase: MafiaPhase = .lobby
    @Published var players: [MafiaPlayer] = []
    @Published var alive: [MafiaPlayer] = []
    @Published var canStart = false
    @Published var day = 0
    @Published var lastKilledId: String?
    @Published var lastSavedId: String?
    @Published var winnerLabel = ""
    @Published var options = MafiaOptions()
    @Published var autoMafiaCount = true
    @Published var mafiaCountValue = 1
    @Published var maxMafiaCount = 1
    @Published var tutorialState = TutorialVoteCard.VoteState(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    func applyOptions(_ o: MafiaOptions) { server.hostSetOptions(o) }

    func callTutorialVote() { server.hostCallTutorialVote() }
    func tutorialVote(_ yes: Bool) { server.hostTutorialVote(yes) }
    func dismissTutorial() { server.hostDismissTutorial() }

    var hostRole: MafiaRole? { server.engine.players[MafiaServer.hostId]?.role }

    func startHosting() {
        do { joinUrl = try server.start() } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func start() { server.hostStart() }
    func advanceFromReveal() { server.advanceFromReveal() }
    func submitNight(targetId: String) { server.hostNightAction(targetId: targetId) }
    func submitVote(targetId: String?) { server.hostDayVote(targetId: targetId) }
    func stop() { server.stop() }

    func name(_ id: String) -> String { server.engine.players[id]?.name ?? id }

    private func refresh() {
        let e = server.engine
        phase = e.phase
        players = Array(e.players.values).sorted { $0.id < $1.id }
        alive = e.alive
        canStart = e.canStart
        day = e.day
        lastKilledId = e.lastNight?.killedId
        lastSavedId = e.lastNight?.savedId
        if e.phase == .gameOver, let w = e.winner {
            winnerLabel = w == .town ? "Town wins" : "Mafia wins"
        }
        if options != e.options { options = e.options }
        autoMafiaCount = e.options.mafiaCount == nil
        maxMafiaCount = e.maxMafiaCount
        if let c = e.options.mafiaCount, mafiaCountValue != c { mafiaCountValue = c }
        else if e.options.mafiaCount == nil && mafiaCountValue == 1 {
            // Suggest the formula-derived value for when the host toggles auto off.
            mafiaCountValue = max(1, min(e.players.count - 2, e.players.count / 4))
        }
        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }
}

enum QRCode {
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let ci = filter.outputImage?.transformed(by: .init(scaleX: 8, y: 8)) else { return nil }
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
