import SwiftUI

/// Native guest UI for Secret Hitler — wire protocol from `secret_hitler_browser.html`.
struct SecretHitlerGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = SecretHitlerGuestModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Playing as \(ctx.yourName)").font(.caption).foregroundStyle(.secondary)
                if model.phase == "gameOver" {
                    gameOver
                } else if model.phase == "lobby" {
                    lobby
                } else {
                    roleCard
                    tracks
                    government
                    phaseSection
                }
            }
            .padding()
        }
        .navigationTitle("Secret Hitler")
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
    }

    @ViewBuilder private var lobby: some View {
        TutorialGuestCard(state: model.tutorialState, content: model.tutorialContent,
                          myVote: model.myTutorialVote,
                          onCall: { model.send(["type": "call_tutorial_vote"]) },
                          onVote: { yes in model.myTutorialVote = yes
                              model.send(["type": "tutorial_vote", "yes": yes]) })
        GroupBox("Players (\(model.players.count))") {
            ForEach(model.players, id: \.id) { p in
                HStack {
                    Text(p.name).fontWeight(p.id == ctx.yourId ? .bold : .regular)
                    if p.isHost { Text("host").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                }
            }
        }
        Text("5–10 players. Waiting for the host to start…")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var roleCard: some View {
        if let role = model.role {
            let (label, blurb, color) = secretHitlerRoleStyle(role)
            GroupBox(label) {
                Text(blurb).font(.callout).foregroundStyle(.secondary)
                if !model.allies.isEmpty {
                    Text("Allies: " + model.allies.map { ally in
                        ally.role == "hitler" ? "\(ally.name) (Hitler)" : ally.name
                    }.joined(separator: ", "))
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }.background(color.opacity(0.15)).cornerRadius(12)
        }
    }

    @ViewBuilder private var tracks: some View {
        HStack(spacing: 8) {
            track("Liberal", "\(model.liberalPolicies) / 5", .blue)
            track("Fascist", "\(model.fascistPolicies) / 6", .red)
            track("Election", "\(model.electionTracker) / 3", .gray)
        }
    }
    @ViewBuilder private func track(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack { Text(label).font(.caption); Text(value).font(.title3.bold()).foregroundStyle(color) }
            .frame(maxWidth: .infinity).padding(8).background(.thinMaterial).cornerRadius(8)
    }

    @ViewBuilder private var government: some View {
        HStack {
            VStack(alignment: .leading) { Text("President").font(.caption)
                Text(playerName(model.presidentId)).fontWeight(.bold) }
            Spacer()
            VStack(alignment: .trailing) { Text("Chancellor").font(.caption)
                Text(playerName(model.chancellorId ?? model.chancellorNomineeId)).fontWeight(.bold) }
        }
        .padding().background(.thinMaterial).cornerRadius(8)
    }

    @ViewBuilder private var phaseSection: some View {
        let amPresident = model.presidentId == ctx.yourId
        let amChancellor = model.chancellorId == ctx.yourId
        switch model.phase {
        case "nomination":
            if amPresident {
                GroupBox("Nominate a Chancellor") {
                    ForEach(model.players.filter { model.eligibleChancellors.contains($0.id) }, id: \.id) { p in
                        Button { model.send(["type": "nominate", "targetId": p.id]) } label: {
                            HStack { Text(p.name); Spacer() }.padding(.vertical, 6)
                        }
                    }
                }
            } else {
                waiting("\(playerName(model.presidentId)) is nominating a Chancellor")
            }
        case "election":
            let meAlive = model.players.first { $0.id == ctx.yourId }?.alive ?? false
            if !meAlive { waiting("Watching from the sidelines") }
            else if model.voted {
                Text("Vote locked in. \(model.voteProgress) / \(model.voteTotal) have voted.")
                    .padding().background(.thinMaterial).cornerRadius(8)
            } else {
                GroupBox("Vote on the government") {
                    Text("\(playerName(model.presidentId)) / \(playerName(model.chancellorNomineeId))")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Ja!") { model.send(["type": "vote", "ja": true]); model.voted = true }
                            .buttonStyle(.borderedProminent).tint(.green).frame(maxWidth: .infinity)
                        Button("Nein!") { model.send(["type": "vote", "ja": false]); model.voted = true }
                            .buttonStyle(.borderedProminent).tint(.red).frame(maxWidth: .infinity)
                    }
                    Text("\(model.voteProgress) / \(model.voteTotal) voted").font(.caption).foregroundStyle(.secondary)
                }
            }
        case "presidentDiscard":
            if amPresident, let hand = model.presidentialHand {
                GroupBox("Discard one — two go to the Chancellor") {
                    ForEach(Array(hand.enumerated()), id: \.offset) { i, pol in
                        Button { model.send(["type": "discard", "index": i]) } label: {
                            HStack { Text(policyLabel(pol)); Spacer(); Text("discard") }
                                .padding(.vertical, 6)
                        }
                    }
                }
            } else { waiting("\(playerName(model.presidentId)) is discarding") }
        case "chancellorEnact":
            if amChancellor, let hand = model.chancellorHand {
                GroupBox("Enact one policy") {
                    ForEach(Array(hand.enumerated()), id: \.offset) { i, pol in
                        Button { model.send(["type": "enact", "index": i]) } label: {
                            HStack { Text(policyLabel(pol)); Spacer(); Text("enact") }
                                .padding(.vertical, 6)
                        }
                    }
                    if model.vetoUnlocked {
                        Button("Request veto") { model.send(["type": "request_veto"]) }
                            .buttonStyle(.bordered)
                    }
                }
            } else { waiting("\(playerName(model.chancellorId)) is enacting a policy") }
        case "vetoDecision":
            if amPresident {
                GroupBox("Chancellor wants to veto") {
                    HStack {
                        Button("Agree — veto") { model.send(["type": "veto_response", "confirm": true]) }
                            .buttonStyle(.borderedProminent).tint(.orange)
                        Button("Refuse") { model.send(["type": "veto_response", "confirm": false]) }
                            .buttonStyle(.bordered)
                    }
                }
            } else { waiting("Veto requested — \(playerName(model.presidentId)) is deciding") }
        case "policyPeek":
            if amPresident, let peek = model.peekedPolicies {
                GroupBox("Top three policies") {
                    ForEach(Array(peek.enumerated()), id: \.offset) { i, pol in
                        Text("\(i+1). \(policyLabel(pol))")
                    }
                    Button("Done") { model.send(["type": "ack_peek"]) }.buttonStyle(.borderedProminent)
                }
            } else { waiting("\(playerName(model.presidentId)) is peeking at the deck") }
        case "investigation":
            if amPresident {
                GroupBox("Investigate a player's party") {
                    let targets = model.players.filter {
                        $0.alive && $0.id != model.presidentId && !model.investigatedIds.contains($0.id)
                    }
                    ForEach(targets, id: \.id) { p in
                        Button { model.send(["type": "investigate", "targetId": p.id]) } label: {
                            HStack { Text(p.name); Spacer() }.padding(.vertical, 6)
                        }
                    }
                }
            } else { waiting("\(playerName(model.presidentId)) is investigating") }
        case "investigationReveal":
            if amPresident, let inv = model.investigationResult {
                GroupBox("\(playerName(inv.subjectId)) is \(inv.party.capitalized)") {
                    Text("Share it or lie about it.").font(.caption).foregroundStyle(.secondary)
                    Button("Done") { model.send(["type": "ack_investigation"]) }.buttonStyle(.borderedProminent)
                }
            } else { waiting("\(playerName(model.presidentId)) has the investigation result") }
        case "specialElection":
            if amPresident {
                GroupBox("Pick the next President") {
                    ForEach(model.players.filter { $0.alive && $0.id != model.presidentId }, id: \.id) { p in
                        Button { model.send(["type": "special_election", "targetId": p.id]) } label: {
                            HStack { Text(p.name); Spacer() }.padding(.vertical, 6)
                        }
                    }
                }
            } else { waiting("\(playerName(model.presidentId)) is calling a special election") }
        case "execution":
            if amPresident {
                GroupBox("Execute a player") {
                    ForEach(model.players.filter { $0.alive && $0.id != model.presidentId }, id: \.id) { p in
                        Button { model.send(["type": "execute", "targetId": p.id]) } label: {
                            HStack { Text(p.name); Spacer() }.padding(.vertical, 6)
                        }
                    }
                }
            } else { waiting("\(playerName(model.presidentId)) is choosing someone to execute") }
        default: waiting("Waiting…")
        }
    }

    @ViewBuilder private var gameOver: some View {
        let winText = model.winner == "liberal" ? "Liberals win" : "Fascists win"
        let reason = ({ () -> String in
            switch model.reason {
            case "fiveLiberalPolicies": "Five Liberal policies enacted."
            case "sixFascistPolicies":  "Six Fascist policies enacted."
            case "hitlerElectedChancellor": "Hitler was elected Chancellor."
            case "hitlerExecuted":      "Hitler was executed."
            default: ""
            }
        })()
        GroupBox(winText) {
            Text(reason).font(.subheadline)
            ForEach(model.players, id: \.id) { p in
                HStack { Text(p.name); Spacer()
                    Text((model.finalRoles[p.id] ?? "").capitalized).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private func waiting(_ msg: String) -> some View {
        Text("\(msg)…").foregroundStyle(.secondary).padding()
            .frame(maxWidth: .infinity).background(.thinMaterial).cornerRadius(8)
    }

    private func policyLabel(_ p: String) -> String { p == "liberal" ? "Liberal policy" : "Fascist policy" }
    private func playerName(_ id: String?) -> String {
        guard let id else { return "—" }
        return model.players.first { $0.id == id }?.name ?? id
    }
}

private func secretHitlerRoleStyle(_ role: String) -> (String, String, Color) {
    switch role {
    case "liberal": return ("Your role: Liberal", "Pass 5 Liberal policies or have Hitler executed.", .blue)
    case "fascist": return ("Your role: Fascist", "Pass 6 Fascist policies or sneak Hitler in as Chancellor after 3.", .red)
    case "hitler":  return ("Your role: Hitler", "Stay hidden. After 3 Fascist policies, getting elected Chancellor wins.", Color(red: 0.5, green: 0, blue: 0))
    default:        return ("Your role", role, .gray)
    }
}

@MainActor
final class SecretHitlerGuestModel: ObservableObject {
    struct Player: Identifiable { let id: String; let name: String; let isHost: Bool; let alive: Bool }
    struct Ally { let id: String; let name: String; let role: String }
    struct Investigation { let subjectId: String; let party: String }

    @Published var players: [Player] = []
    @Published var phase: String = "lobby"
    @Published var presidentId: String?
    @Published var chancellorNomineeId: String?
    @Published var chancellorId: String?
    @Published var liberalPolicies = 0
    @Published var fascistPolicies = 0
    @Published var electionTracker = 0
    @Published var vetoUnlocked = false
    @Published var vetoRequested = false
    @Published var eligibleChancellors: [String] = []
    @Published var voteProgress = 0
    @Published var voteTotal = 0
    @Published var voted = false
    @Published var investigatedIds: [String] = []
    @Published var role: String?
    @Published var allies: [Ally] = []
    @Published var presidentialHand: [String]?
    @Published var chancellorHand: [String]?
    @Published var peekedPolicies: [String]?
    @Published var investigationResult: Investigation?
    @Published var winner: String?
    @Published var reason: String?
    @Published var finalRoles: [String: String] = [:]
    @Published var tutorialState = GuestTutorialState()
    @Published var tutorialContent: GuestTutorialContent?
    @Published var myTutorialVote: Bool?

    private weak var client: (any GuestLink)?

    func attach(ctx: GuestContext) {
        client = ctx.client
        ctx.client.onMessage = { [weak self] msg in self?.handle(msg) }
        for m in ctx.replay { handle(m) }
    }

    func send(_ payload: [String: Any]) { client?.send(payload) }

    private func handle(_ m: [String: Any]) {
        guard let type = m["type"] as? String else { return }
        switch type {
        case "lobby":
            let arr = m["players"] as? [[String: Any]] ?? []
            players = arr.map { Player(id: $0["id"] as? String ?? "",
                                       name: $0["name"] as? String ?? "",
                                       isHost: $0["isHost"] as? Bool ?? false,
                                       alive: $0["alive"] as? Bool ?? true) }
        case "role":
            role = m["role"] as? String
            allies = (m["allies"] as? [[String: Any]] ?? []).map {
                Ally(id: $0["id"] as? String ?? "",
                     name: $0["name"] as? String ?? "",
                     role: $0["role"] as? String ?? "")
            }
        case "state":
            let prev = phase
            phase = m["phase"] as? String ?? phase
            if let arr = m["players"] as? [[String: Any]] {
                players = arr.map { Player(id: $0["id"] as? String ?? "",
                                           name: $0["name"] as? String ?? "",
                                           isHost: $0["isHost"] as? Bool ?? false,
                                           alive: $0["alive"] as? Bool ?? true) }
            }
            presidentId = m["presidentId"] as? String
            chancellorNomineeId = m["chancellorNomineeId"] as? String
            chancellorId = m["chancellorId"] as? String
            liberalPolicies = m["liberalPolicies"] as? Int ?? liberalPolicies
            fascistPolicies = m["fascistPolicies"] as? Int ?? fascistPolicies
            electionTracker = m["electionTracker"] as? Int ?? electionTracker
            vetoUnlocked = m["vetoUnlocked"] as? Bool ?? vetoUnlocked
            vetoRequested = m["vetoRequested"] as? Bool ?? false
            eligibleChancellors = m["eligibleChancellors"] as? [String] ?? []
            voteProgress = m["voteProgress"] as? Int ?? 0
            voteTotal = m["voteTotal"] as? Int ?? 0
            investigatedIds = m["investigatedIds"] as? [String] ?? []
            // Clear per-phase scratch on phase transition.
            if prev != phase {
                voted = false
                if phase != "presidentDiscard" { presidentialHand = nil }
                if phase != "chancellorEnact" && phase != "vetoDecision" { chancellorHand = nil }
                if phase != "policyPeek" { peekedPolicies = nil }
                if phase != "investigationReveal" { investigationResult = nil }
            }
        case "vote_progress":
            voteProgress = m["voteProgress"] as? Int ?? voteProgress
            voteTotal = m["voteTotal"] as? Int ?? voteTotal
        case "election_result":
            electionTracker = m["electionTracker"] as? Int ?? electionTracker
        case "policy_enacted":
            liberalPolicies = m["liberalPolicies"] as? Int ?? liberalPolicies
            fascistPolicies = m["fascistPolicies"] as? Int ?? fascistPolicies
        case "veto_confirmed":
            electionTracker = m["electionTracker"] as? Int ?? electionTracker
        case "presidential_hand":
            presidentialHand = m["policies"] as? [String]
        case "chancellor_hand":
            chancellorHand = m["policies"] as? [String]
            vetoUnlocked = m["vetoUnlocked"] as? Bool ?? vetoUnlocked
        case "policy_peek":
            peekedPolicies = m["policies"] as? [String]
        case "investigation_result":
            if let s = m["subjectId"] as? String, let p = m["party"] as? String {
                investigationResult = Investigation(subjectId: s, party: p)
            }
        case "executed":
            break // already covered by state
        case "game_over":
            phase = "gameOver"
            winner = m["winner"] as? String
            reason = m["reason"] as? String
            finalRoles = (m["roles"] as? [String: String]) ?? [:]
        case "tutorial_vote_state":
            tutorialState.apply(m)
            if let title = m["title"] as? String {
                tutorialContent = GuestTutorialContent(title: title,
                    sections: GuestTutorialContent.readSections(m["sections"]),
                    menuSections: GuestTutorialContent.readSections(m["menuSections"]))
            }
        default: break
        }
    }
}
