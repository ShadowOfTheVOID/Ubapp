import SwiftUI
import CoreImage.CIFilterBuiltins

/// Host screen. In the lobby the host owns the QR, options and "Start round".
/// Once the round begins the host plays on the *exact same* player screen
/// every guest sees (`MafiaGuestView`), driven by an in-process loopback as
/// the `host` player — plus a thin control bar for the one orchestration step
/// the player screen lacks (advancing past the night reveal).
struct MafiaView: View {
    @StateObject private var model = MafiaViewModel()

    var body: some View {
        Group {
            if model.phase == .lobby {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting,
                                      onStop: model.stop)
                        Text("Lobby").font(.headline)
                        TutorialVoteCard(
                            state: model.tutorialState,
                            tutorial: GameTutorials.mafia,
                            onCall: model.callTutorialVote,
                            onVote: model.tutorialVote,
                            onDismiss: model.dismissTutorial,
                        )
                        lobbyView
                    }
                    .padding()
                }
            } else if let ctx = model.loopbackCtx {
                VStack(spacing: 0) {
                    MafiaGuestView(ctx: ctx)
                    if model.phase == .dayReveal {
                        Divider()
                        Button("Continue to day vote") { model.advanceFromReveal() }
                            .buttonStyle(.borderedProminent)
                            .padding()
                    }
                }
            }
        }
        .navigationTitle("Mafia")
        .onDisappear { model.stop() }
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

}

@MainActor
final class MafiaViewModel: ObservableObject {
    private let server = MafiaServer(hostName: "Host")
    @Published var joinUrl: URL?
    @Published var phase: MafiaPhase = .lobby
    @Published var players: [MafiaPlayer] = []
    @Published var canStart = false
    @Published var options = MafiaOptions()
    /// In-process player screen for the host once the round starts.
    @Published var loopbackCtx: GuestContext?
    private var loopback: LoopbackGuest?
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

    func startHosting() {
        do {
            joinUrl = try server.start()
            let lb = server.makeLoopback()
            loopback = lb
            loopbackCtx = GuestContext(client: lb, game: "mafia",
                                       yourId: MafiaServer.hostId,
                                       yourName: server.hostName, replay: [])
        } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func start() { server.hostStart() }
    func advanceFromReveal() { server.advanceFromReveal() }
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
