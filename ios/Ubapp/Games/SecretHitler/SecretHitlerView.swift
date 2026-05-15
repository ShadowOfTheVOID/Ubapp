import SwiftUI

/// Host's player UI for Secret Hitler. The host plays as `hostId`; this view
/// branches on phase + whether the host is currently President / Chancellor.
struct SecretHitlerView: View {
    @StateObject private var model = SecretHitlerViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HostingChrome(joinUrl: model.joinUrl, onStart: model.startHosting)

                trackHeader

                if model.phase == .lobby {
                    TutorialVoteCard(
                        state: model.tutorialState,
                        tutorial: GameTutorials.secretHitler,
                        onCall: model.callTutorialVote,
                        onVote: model.tutorialVote,
                        onDismiss: model.dismissTutorial,
                    )
                    lobbyView
                } else {
                    roleCard
                    gameBody
                }
            }
            .padding()
        }
        .navigationTitle("Secret Hitler")
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var trackHeader: some View {
        if model.phase != .lobby {
            HStack(spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Liberal").font(.caption).foregroundStyle(.secondary)
                    Text("\(model.liberalPolicies) / 5").font(.title3.bold()).foregroundStyle(.green)
                }
                VStack(alignment: .leading) {
                    Text("Fascist").font(.caption).foregroundStyle(.secondary)
                    Text("\(model.fascistPolicies) / 6").font(.title3.bold()).foregroundStyle(.red)
                }
                VStack(alignment: .leading) {
                    Text("Election").font(.caption).foregroundStyle(.secondary)
                    Text("\(model.electionTracker) / 3").font(.title3.bold())
                }
                Spacer()
            }
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
        if model.canStart {
            Button("Start round") { model.start() }.buttonStyle(.borderedProminent)
        } else {
            Text("Need 5–10 players to start.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var roleCard: some View {
        if let role = model.hostRole {
            GroupBox("Your role: \(role.rawValue.capitalized)") {
                Text(roleTagline(role)).font(.callout).foregroundStyle(.secondary)
                if !model.hostAllies.isEmpty {
                    Text("Allies: " + model.hostAllies.map { $0.name }.joined(separator: ", "))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func roleTagline(_ r: SecretHitlerRole) -> String {
        switch r {
        case .liberal: return "Pass 5 Liberal policies, or have Hitler executed."
        case .fascist: return "Get 6 Fascist policies through — or sneak Hitler in as Chancellor after 3."
        case .hitler:  return "Stay hidden. After 3 Fascist policies, getting elected Chancellor wins the game."
        }
    }

    @ViewBuilder private var gameBody: some View {
        leadershipHeader
        switch model.phase {
        case .nomination:           nominationView
        case .election:             electionView
        case .presidentDiscard:     presidentDiscardView
        case .chancellorEnact:      chancellorEnactView
        case .vetoDecision:         vetoDecisionView
        case .policyPeek:           policyPeekView
        case .investigation:        investigationView
        case .investigationReveal:  investigationRevealView
        case .specialElection:      specialElectionView
        case .execution:            executionView
        case .gameOver:             gameOverView
        case .lobby:                EmptyView()
        }
    }

    @ViewBuilder private var leadershipHeader: some View {
        GroupBox("Government") {
            HStack {
                VStack(alignment: .leading) {
                    Text("President").font(.caption).foregroundStyle(.secondary)
                    Text(model.name(model.presidentId)).font(.body.bold())
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Chancellor").font(.caption).foregroundStyle(.secondary)
                    Text(model.name(model.chancellorId ?? model.chancellorNomineeId))
                        .font(.body.bold())
                }
            }
        }
    }

    @ViewBuilder private var nominationView: some View {
        if model.amPresident {
            GroupBox("Pick a Chancellor") {
                ForEach(model.eligibleChancellors, id: \.id) { p in
                    Button {
                        model.nominate(p.id)
                    } label: {
                        HStack { Text(p.name); Spacer() }.padding(.vertical, 6)
                    }
                }
            }
        } else {
            Text("Waiting for \(model.name(model.presidentId)) to nominate a Chancellor…")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var electionView: some View {
        if model.hostAlive {
            GroupBox("Vote on the government") {
                Text("\(model.name(model.presidentId)) as President with \(model.name(model.chancellorNomineeId)) as Chancellor")
                    .font(.subheadline)
                HStack {
                    Button("Ja!") { model.vote(true) }.buttonStyle(.borderedProminent).tint(.green)
                    Button("Nein!") { model.vote(false) }.buttonStyle(.borderedProminent).tint(.red)
                }
                Text("\(model.voteProgress) / \(model.voteTotal) voted").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var presidentDiscardView: some View {
        if model.amPresident {
            GroupBox("Discard one policy") {
                Text("Two remaining go to the Chancellor.").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(model.presidentialHand.enumerated()), id: \.offset) { i, pol in
                    Button { model.discard(index: i) } label: {
                        HStack { Text(policyLabel(pol)); Spacer(); Text("discard") }
                            .padding(.vertical, 6)
                    }
                }
            }
        } else {
            Text("Waiting for the President to discard…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var chancellorEnactView: some View {
        if model.amChancellor {
            GroupBox("Enact one policy") {
                ForEach(Array(model.chancellorHand.enumerated()), id: \.offset) { i, pol in
                    Button { model.enact(index: i) } label: {
                        HStack { Text(policyLabel(pol)); Spacer(); Text("enact") }
                            .padding(.vertical, 6)
                    }
                }
                if model.vetoUnlocked {
                    Button("Request veto") { model.requestVeto() }.buttonStyle(.bordered)
                }
            }
        } else {
            Text("Waiting for the Chancellor to enact a policy…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var vetoDecisionView: some View {
        if model.amPresident {
            GroupBox("Chancellor has requested a veto") {
                Text("If you agree, both policies are discarded and the election tracker advances.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Agree — veto") { model.vetoResponse(true) }.buttonStyle(.borderedProminent).tint(.orange)
                    Button("Refuse") { model.vetoResponse(false) }.buttonStyle(.bordered)
                }
            }
        } else {
            Text("Veto requested — waiting for the President…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var policyPeekView: some View {
        if model.amPresident {
            GroupBox("Top three policies") {
                ForEach(Array(model.peekedPolicies.enumerated()), id: \.offset) { i, pol in
                    Text("\(i + 1). \(policyLabel(pol))")
                }
                Button("Done") { model.acknowledgePeek() }.buttonStyle(.borderedProminent)
            }
        } else {
            Text("The President is peeking at the next three policies…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var investigationView: some View {
        if model.amPresident {
            GroupBox("Investigate a player's party") {
                ForEach(model.investigationTargets, id: \.id) { p in
                    Button { model.investigate(p.id) } label: {
                        HStack { Text(p.name); Spacer() }.padding(.vertical, 6)
                    }
                }
            }
        } else {
            Text("The President is investigating someone…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var investigationRevealView: some View {
        if model.amPresident, let inv = model.lastInvestigation {
            GroupBox("\(model.name(inv.subjectId)) is part of the \(inv.party.rawValue.capitalized) party") {
                Text("This is the result you may share — or lie about.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Done") { model.acknowledgeInvestigation() }.buttonStyle(.borderedProminent)
            }
        } else {
            Text("The President has the investigation result…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var specialElectionView: some View {
        if model.amPresident {
            GroupBox("Call a special election — pick the next President") {
                ForEach(model.specialElectionTargets, id: \.id) { p in
                    Button { model.specialElection(p.id) } label: {
                        HStack { Text(p.name); Spacer() }.padding(.vertical, 6)
                    }
                }
            }
        } else {
            Text("The President is choosing a special-election successor…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var executionView: some View {
        if model.amPresident {
            GroupBox("Execute a player") {
                ForEach(model.executionTargets, id: \.id) { p in
                    Button { model.execute(p.id) } label: {
                        HStack { Text(p.name); Spacer() }.padding(.vertical, 6)
                    }
                }
            }
        } else {
            Text("The President is choosing someone to execute…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var gameOverView: some View {
        GroupBox("Game over — \(model.winnerLabel)") {
            Text(model.winReasonLabel).font(.subheadline)
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name)
                    Spacer()
                    Text(p.role?.rawValue.capitalized ?? "—").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func policyLabel(_ p: SecretHitlerPolicy) -> String {
        p == .liberal ? "Liberal policy" : "Fascist policy"
    }
}

@MainActor
final class SecretHitlerViewModel: ObservableObject {
    private let server = SecretHitlerServer(hostName: "Host")
    @Published var joinUrl: URL?
    @Published var phase: SecretHitlerPhase = .lobby
    @Published var players: [SecretHitlerPlayer] = []
    @Published var canStart = false
    @Published var liberalPolicies = 0
    @Published var fascistPolicies = 0
    @Published var electionTracker = 0
    @Published var vetoUnlocked = false
    @Published var presidentId: String?
    @Published var chancellorNomineeId: String?
    @Published var chancellorId: String?
    @Published var eligibleChancellors: [SecretHitlerPlayer] = []
    @Published var voteProgress = 0
    @Published var voteTotal = 0
    @Published var presidentialHand: [SecretHitlerPolicy] = []
    @Published var chancellorHand: [SecretHitlerPolicy] = []
    @Published var peekedPolicies: [SecretHitlerPolicy] = []
    @Published var lastInvestigation: (subjectId: String, party: SecretHitlerParty)?
    @Published var investigationTargets: [SecretHitlerPlayer] = []
    @Published var specialElectionTargets: [SecretHitlerPlayer] = []
    @Published var executionTargets: [SecretHitlerPlayer] = []
    @Published var winnerLabel = ""
    @Published var winReasonLabel = ""
    @Published var hostAllies: [SecretHitlerPlayer] = []
    @Published var tutorialState = TutorialVoteCard.State(
        isOpen: false, yesCount: 0, noCount: 0, eligibleCount: 0,
        result: nil, tutorialShown: false)

    init() { server.onStateChange = { [weak self] in self?.refresh() } }

    var hostRole: SecretHitlerRole? { server.engine.players[SecretHitlerServer.hostId]?.role }
    var hostAlive: Bool { server.engine.players[SecretHitlerServer.hostId]?.alive ?? false }
    var amPresident: Bool { presidentId == SecretHitlerServer.hostId }
    var amChancellor: Bool { chancellorId == SecretHitlerServer.hostId }

    func name(_ id: String?) -> String {
        guard let id else { return "—" }
        return server.engine.players[id]?.name ?? id
    }

    func startHosting() {
        do { joinUrl = try server.start() } catch { print("HostServer failed: \(error)") }
        refresh()
    }
    func start() { server.hostStart() }
    func stop() { server.stop() }

    func callTutorialVote() { server.hostCallTutorialVote() }
    func tutorialVote(_ yes: Bool) { server.hostTutorialVote(yes) }
    func dismissTutorial() { server.hostDismissTutorial() }

    func nominate(_ id: String) { server.hostNominate(id) }
    func vote(_ ja: Bool) { server.hostVote(ja) }
    func discard(index: Int) { server.hostDiscard(index: index) }
    func enact(index: Int) { server.hostEnact(index: index) }
    func requestVeto() { server.hostRequestVeto() }
    func vetoResponse(_ confirm: Bool) { server.hostVetoResponse(confirm) }
    func acknowledgePeek() { server.hostAcknowledgePeek() }
    func investigate(_ id: String) { server.hostInvestigate(id) }
    func acknowledgeInvestigation() { server.hostAcknowledgeInvestigation() }
    func specialElection(_ id: String) { server.hostSpecialElection(id) }
    func execute(_ id: String) { server.hostExecute(id) }

    private func refresh() {
        let e = server.engine
        phase = e.phase
        players = e.seatOrder.compactMap { e.players[$0] }
        canStart = e.canStart
        liberalPolicies = e.liberalPolicies
        fascistPolicies = e.fascistPolicies
        electionTracker = e.electionTracker
        vetoUnlocked = e.vetoUnlocked
        presidentId = e.presidentId
        chancellorNomineeId = e.chancellorNomineeId
        chancellorId = e.chancellorId
        eligibleChancellors = e.phase == .nomination ? e.eligibleChancellorNominees() : []
        voteProgress = e.electionVotes.count
        voteTotal = e.alive.count
        presidentialHand = e.presidentialHand
        chancellorHand = e.chancellorHand
        peekedPolicies = e.peekedPolicies
        if let inv = e.lastInvestigation { lastInvestigation = inv } else { lastInvestigation = nil }
        investigationTargets = e.phase == .investigation ? e.investigationTargets() : []
        specialElectionTargets = e.phase == .specialElection
            ? e.alive.filter { $0.id != e.presidentId } : []
        executionTargets = e.phase == .execution ? e.executionTargets() : []

        if e.phase == .gameOver {
            winnerLabel = e.winner == .liberal ? "Liberals win" : "Fascists win"
            winReasonLabel = winReasonText(e.winReason)
        }

        let allies = e.knownAllies(for: SecretHitlerServer.hostId)
        hostAllies = allies.compactMap { e.players[$0] }

        let v = e.tutorialVote
        tutorialState = .init(
            isOpen: v.isOpen, yesCount: v.yesCount, noCount: v.noCount,
            eligibleCount: v.eligibleCount, result: v.result, tutorialShown: v.tutorialShown)
    }

    private func winReasonText(_ r: SecretHitlerWinReason?) -> String {
        switch r {
        case .fiveLiberalPolicies: return "Five Liberal policies enacted."
        case .sixFascistPolicies:  return "Six Fascist policies enacted."
        case .hitlerElectedChancellor: return "Hitler was elected Chancellor after three Fascist policies."
        case .hitlerExecuted:      return "Hitler was executed."
        case .none:                return ""
        }
    }
}
