import SwiftUI

/// Native guest UI for Mafia. Consumes the same JSON the browser bundle does:
/// see `mafia_browser.html` for the wire protocol.
struct MafiaGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = MafiaGuestModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.error != nil { errorBanner }
                switch model.phase {
                case "lobby":     lobby
                case "night":     night
                case "dayReveal": dayReveal
                case "dayVote":   dayVote
                case "gameOver":  gameOver
                default:          waiting
                }
                playersSection
            }
            .padding()
        }
        .navigationTitle("Mafia")
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
    }

    @ViewBuilder private var header: some View {
        HStack {
            Text("Playing as \(ctx.yourName)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            if model.phase != "lobby" {
                Text("Day \(model.day)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var errorBanner: some View {
        Text(model.error ?? "").foregroundStyle(.white).padding()
            .frame(maxWidth: .infinity).background(Color.red).cornerRadius(12)
    }

    @ViewBuilder private var lobby: some View {
        TutorialGuestCard(state: model.tutorialState, content: model.tutorialContent,
                          myVote: model.myTutorialVote,
                          onCall: { model.send(["type": "call_tutorial_vote"]) },
                          onVote: { yes in model.myTutorialVote = yes
                              model.send(["type": "tutorial_vote", "yes": yes]) })
        GroupBox("Lobby (\(model.lobby.count))") {
            ForEach(model.lobby, id: \.id) { p in
                HStack {
                    Text(p.name).fontWeight(p.id == ctx.yourId ? .bold : .regular)
                    if p.isHost { Text("host").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if p.id == ctx.yourId { Text("you").font(.caption).foregroundStyle(.blue) }
                }
            }
        }
        Text("Waiting for the host to start…").foregroundStyle(.secondary).font(.caption)
    }

    @ViewBuilder private var night: some View {
        roleCard
        if !iAmAlive {
            spectator
        } else if model.role == "mafia" {
            targetPicker(prompt: "Choose someone to eliminate",
                         targets: model.alive.filter { $0.id != ctx.yourId },
                         kind: "night")
        } else if model.role == "doctor" {
            targetPicker(prompt: "Choose someone to save",
                         targets: model.alive, kind: "night")
        } else {
            Text("Mafia and doctor are acting…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var dayReveal: some View {
        lastNightSummary
    }

    @ViewBuilder private var dayVote: some View {
        if !iAmAlive {
            spectator
        } else {
            lastNightSummary
            targetPicker(prompt: "Vote to eliminate",
                         targets: model.alive.filter { $0.id != ctx.yourId },
                         kind: "vote", allowSkip: true)
        }
    }

    @ViewBuilder private var gameOver: some View {
        GroupBox(model.winner == "mafia" ? "Mafia win" : "Town wins") {
            ForEach(model.rolesReveal, id: \.id) { entry in
                HStack {
                    Text(entry.name); Spacer(); Text(entry.role.capitalized).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var waiting: some View {
        Text("Waiting…").foregroundStyle(.secondary)
    }

    @ViewBuilder private var spectator: some View {
        GroupBox("You're out") {
            Text("Watching from the sidelines.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var roleCard: some View {
        if let role = model.role {
            let (label, blurb, color) = mafiaRoleStyle(role)
            GroupBox(label) {
                Text(blurb).font(.callout).foregroundStyle(.secondary)
                if role == "mafia", model.mafiaIds.count > 1 {
                    let others = model.mafiaIds.filter { $0 != ctx.yourId }
                        .compactMap { id in model.lobby.first(where: { $0.id == id })?.name
                            ?? model.alive.first(where: { $0.id == id })?.name }
                    if !others.isEmpty {
                        Text("Your fellow mafia: \(others.joined(separator: ", "))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .background(color.opacity(0.15))
            .cornerRadius(12)
        }
    }

    @ViewBuilder private var lastNightSummary: some View {
        if let k = model.lastNightKilled {
            Text("\(playerName(k)) was killed in the night.")
                .padding().frame(maxWidth: .infinity).background(.thinMaterial).cornerRadius(12)
        } else if model.lastNightSaved != nil {
            Text("The doctor saved someone — no one died.")
                .padding().frame(maxWidth: .infinity).background(.thinMaterial).cornerRadius(12)
        } else if model.nightResolved {
            Text("A quiet night.")
                .padding().frame(maxWidth: .infinity).background(.thinMaterial).cornerRadius(12)
        }
    }

    @ViewBuilder private var playersSection: some View {
        if model.phase != "lobby" && (model.alive.count + model.dead.count) > 0 {
            GroupBox("Players") {
                ForEach(model.alive, id: \.id) { p in
                    HStack { Text(p.name); Spacer(); Text("alive").font(.caption).foregroundStyle(.green) }
                }
                ForEach(model.dead, id: \.id) { p in
                    HStack { Text(p.name); Spacer(); Text("dead").font(.caption).foregroundStyle(.red) }
                }
            }
        }
    }

    @ViewBuilder
    private func targetPicker(prompt: String, targets: [MafiaGuestModel.Player],
                              kind: String, allowSkip: Bool = false) -> some View {
        let submitted = model.submittedKind == kind && model.submittedDay == model.day
        GroupBox(prompt) {
            ForEach(targets, id: \.id) { p in
                Button { model.picked = p.id } label: {
                    HStack {
                        Text(p.name)
                        Spacer()
                        if model.picked == p.id { Image(systemName: "checkmark.circle.fill") }
                    }
                    .padding(.vertical, 6)
                }
                .disabled(submitted)
            }
            if allowSkip {
                Button { model.picked = "__skip" } label: {
                    HStack { Text("Skip vote"); Spacer()
                        if model.picked == "__skip" { Image(systemName: "checkmark.circle.fill") } }
                }.disabled(submitted)
            }
            Button(submitted ? "Submitted" : "Confirm") {
                let target: String? = model.picked == "__skip" ? nil : model.picked
                if kind == "night" {
                    model.send(["type": "night_action", "targetId": target ?? ""])
                } else {
                    let payload: [String: Any] = target == nil
                        ? ["type": "vote", "targetId": NSNull()]
                        : ["type": "vote", "targetId": target!]
                    model.send(payload)
                }
                model.submittedKind = kind
                model.submittedDay = model.day
            }
            .disabled(submitted || model.picked == nil)
            .buttonStyle(.borderedProminent)
        }
    }

    private var iAmAlive: Bool {
        model.alive.contains { $0.id == ctx.yourId }
    }

    private func playerName(_ id: String) -> String {
        model.alive.first(where: { $0.id == id })?.name
            ?? model.dead.first(where: { $0.id == id })?.name
            ?? model.lobby.first(where: { $0.id == id })?.name
            ?? id
    }
}

private func mafiaRoleStyle(_ role: String) -> (String, String, Color) {
    switch role {
    case "mafia":    return ("Your role: Mafia", "Eliminate the town. You can see your fellow mafia at night.", .red)
    case "doctor":   return ("Your role: Doctor", "Save one player each night. You can self-save once per game.", .green)
    case "villager": return ("Your role: Villager", "Use your vote during the day. Find the mafia.", .gray)
    default:         return ("Your role", role, .gray)
    }
}

@MainActor
final class MafiaGuestModel: ObservableObject {
    struct Player: Identifiable { let id: String; let name: String; let isHost: Bool; let alive: Bool }
    @Published var lobby: [Player] = []
    @Published var alive: [Player] = []
    @Published var dead: [Player] = []
    @Published var phase: String = "lobby"
    @Published var day: Int = 0
    @Published var role: String?
    @Published var mafiaIds: [String] = []
    @Published var lastNightKilled: String?
    @Published var lastNightSaved: String?
    @Published var nightResolved: Bool = false
    @Published var winner: String?
    @Published var rolesReveal: [(id: String, name: String, role: String)] = []
    @Published var error: String?
    @Published var picked: String?
    @Published var submittedKind: String?
    @Published var submittedDay: Int?
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
            lobby = arr.map { Player(id: $0["id"] as? String ?? "",
                                     name: $0["name"] as? String ?? "",
                                     isHost: $0["isHost"] as? Bool ?? false,
                                     alive: true) }
        case "role":
            role = m["role"] as? String
            mafiaIds = m["mafiaIds"] as? [String] ?? []
        case "phase":
            let prev = phase
            phase = m["phase"] as? String ?? phase
            day = m["day"] as? Int ?? day
            alive = readPlayers(m["alive"])
            dead = readPlayers(m["dead"])
            if m["killedId"] != nil || m["savedId"] != nil {
                lastNightKilled = m["killedId"] as? String
                lastNightSaved = m["savedId"] as? String
                nightResolved = true
            }
            if prev != phase { picked = nil }
        case "vote_update":
            break // optional: track day votes
        case "day_result":
            alive = readPlayers(m["alive"])
            dead = readPlayers(m["dead"])
        case "game_over":
            phase = "gameOver"
            winner = m["winner"] as? String
            if let r = m["roles"] as? [String: String] {
                let combined = lobby + alive + dead
                rolesReveal = r.map { id, role in
                    let name = combined.first(where: { $0.id == id })?.name ?? id
                    return (id, name, role)
                }.sorted { $0.name < $1.name }
            }
        case "tutorial_vote_state":
            tutorialState.apply(m)
            if let title = m["title"] as? String {
                tutorialContent = GuestTutorialContent(title: title,
                    sections: GuestTutorialContent.readSections(m["sections"]),
                    menuSections: GuestTutorialContent.readSections(m["menuSections"]))
            }
        case "error":
            error = m["message"] as? String
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.error = nil }
        default: break
        }
    }

    private func readPlayers(_ raw: Any?) -> [Player] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.map { Player(id: $0["id"] as? String ?? "",
                                name: $0["name"] as? String ?? "",
                                isHost: false,
                                alive: $0["alive"] as? Bool ?? true) }
    }
}
