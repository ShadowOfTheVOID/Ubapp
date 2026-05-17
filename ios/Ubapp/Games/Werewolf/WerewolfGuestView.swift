import SwiftUI

/// Native guest UI for Werewolf — wire protocol from `werewolf_browser.html`.
struct WerewolfGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = WerewolfGuestModel()

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .center, spacing: 16) {
                        HStack {
                            Text("Playing as \(ctx.yourName)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if model.phase != "lobby" {
                                Text("Day \(model.day)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if let err = model.error {
                            Text(err).foregroundStyle(.white).padding().frame(maxWidth: .infinity)
                                .background(Color.red).cornerRadius(12)
                        }
                        switch model.phase {
                        case "lobby":      lobby
                        case "night":      night
                        case "dayReveal":  dayReveal
                        case "dayVote":    dayVote
                        case "hunterShot": hunterShot
                        case "gameOver":   gameOver
                        default:           Text("Waiting…").foregroundStyle(.secondary)
                        }
                        seerFindings
                        playersSection
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
            .navigationTitle("Werewolf")
            .onAppear { model.attach(ctx: ctx) }
            .onDisappear { ctx.client.onMessage = nil }
        }
        .ubappChrome()
    }

    @ViewBuilder private var lobby: some View {
        TutorialGuestCard(state: model.tutorialState, content: model.tutorialContent,
                          myVote: model.myTutorialVote,
                          onCall: { model.send(["type": "call_tutorial_vote"]) },
                          onVote: { yes in model.myTutorialVote = yes
                              model.send(["type": "tutorial_vote", "yes": yes]) })
        GroupBox("Players (\(model.lobby.count))") {
            ForEach(model.lobby, id: \.id) { p in
                HStack {
                    Text(p.name).fontWeight(p.id == ctx.yourId ? .bold : .regular)
                    if p.isHost { Text("host").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if p.id == ctx.yourId { Text("you").font(.caption).foregroundStyle(.blue) }
                }
            }
        }
    }

    @ViewBuilder private var night: some View {
        roleCard
        if !iAmAlive { spectator }
        else if model.role == "werewolf" {
            let targets = model.alive.filter { $0.id != ctx.yourId && !model.wolfIds.contains($0.id) }
            targetPicker(prompt: "Choose a victim", targets: targets, kind: "night")
        } else if model.role == "seer" {
            targetPicker(prompt: "Investigate a player",
                         targets: model.alive.filter { $0.id != ctx.yourId },
                         kind: "night")
        } else {
            Text("The wolves and the seer are acting…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var dayReveal: some View {
        roleCard
        lastNightSummary
    }

    @ViewBuilder private var dayVote: some View {
        roleCard
        if !iAmAlive { spectator }
        else {
            lastNightSummary
            targetPicker(prompt: "Vote to lynch",
                         targets: model.alive.filter { $0.id != ctx.yourId },
                         kind: "vote", allowSkip: true)
        }
    }

    @ViewBuilder private var hunterShot: some View {
        if model.hunterId == ctx.yourId {
            GroupBox("Take one with you") {
                ForEach(model.alive.filter { $0.id != ctx.yourId }, id: \.id) { p in
                    Button { model.picked = p.id } label: {
                        HStack {
                            Text(p.name); Spacer()
                            if model.picked == p.id { Image(systemName: "checkmark.circle.fill") }
                        }.padding(.vertical, 6)
                    }
                }
                Button("Fire") {
                    model.send(["type": "hunter_shot", "targetId": model.picked ?? ""])
                    model.picked = nil
                }
                .disabled(model.picked == nil).buttonStyle(.borderedProminent).tint(.red)
            }
        } else {
            Text("\(playerName(model.hunterId ?? "")) is taking their last shot…")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var gameOver: some View {
        GroupBox(model.winner == "werewolves" ? "Werewolves win" : "Village wins") {
            ForEach(model.rolesReveal, id: \.id) { entry in
                HStack { Text(entry.name); Spacer()
                    Text(entry.role.capitalized).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private var spectator: some View {
        GroupBox("You're out") {
            Text("Watching from the sidelines.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var roleCard: some View {
        if let role = model.role {
            let (label, blurb, color) = werewolfRoleStyle(role)
            GroupBox(label) {
                Text(blurb).font(.callout).foregroundStyle(.secondary)
                if role == "werewolf", model.wolfIds.count > 1 {
                    let others = model.wolfIds.filter { $0 != ctx.yourId }
                        .map { playerName($0) }
                    Text("Your pack: \(others.joined(separator: ", "))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .background(color.opacity(0.15)).cornerRadius(12)
        }
    }

    @ViewBuilder private var seerFindings: some View {
        if model.role == "seer", !model.seerHistory.isEmpty {
            GroupBox("Seer findings") {
                ForEach(model.seerHistory, id: \.day) { r in
                    HStack {
                        Text("Night \(r.day): \(playerName(r.targetId))")
                        Spacer()
                        Text(r.isWerewolf ? "IS a werewolf" : "is not a werewolf")
                            .foregroundStyle(r.isWerewolf ? .red : .green).font(.footnote)
                    }
                }
            }
        }
    }

    @ViewBuilder private var lastNightSummary: some View {
        if let k = model.lastNightKilled {
            Text("\(playerName(k)) was killed in the night.")
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
                    HStack { Text(p.name); Spacer()
                        Text("alive").font(.caption).foregroundStyle(.green) }
                }
                ForEach(model.dead, id: \.id) { p in
                    HStack { Text(p.name); Spacer()
                        Text("dead").font(.caption).foregroundStyle(.red) }
                }
            }
        }
    }

    @ViewBuilder
    private func targetPicker(prompt: String, targets: [WerewolfGuestModel.Player],
                              kind: String, allowSkip: Bool = false) -> some View {
        let submitted = model.submittedKind == kind && model.submittedDay == model.day
        GroupBox(prompt) {
            ForEach(targets, id: \.id) { p in
                Button { model.picked = p.id } label: {
                    HStack {
                        Text(p.name); Spacer()
                        if model.picked == p.id { Image(systemName: "checkmark.circle.fill") }
                    }.padding(.vertical, 6)
                }.disabled(submitted)
            }
            if allowSkip {
                Button { model.picked = "__skip" } label: {
                    HStack { Text("Skip vote"); Spacer()
                        if model.picked == "__skip" { Image(systemName: "checkmark.circle.fill") } }
                }.disabled(submitted)
            }
            Button(submitted ? "Submitted" : "Confirm") {
                if kind == "night" {
                    model.send(["type": "night_action", "targetId": model.picked ?? ""])
                } else {
                    let payload: [String: Any] = model.picked == "__skip"
                        ? ["type": "vote", "targetId": NSNull()]
                        : ["type": "vote", "targetId": model.picked ?? ""]
                    model.send(payload)
                }
                model.submittedKind = kind; model.submittedDay = model.day
            }
            .disabled(submitted || model.picked == nil)
            .buttonStyle(.borderedProminent)
        }
    }

    private var iAmAlive: Bool { model.alive.contains { $0.id == ctx.yourId } }
    private func playerName(_ id: String) -> String {
        model.alive.first(where: { $0.id == id })?.name
            ?? model.dead.first(where: { $0.id == id })?.name
            ?? model.lobby.first(where: { $0.id == id })?.name
            ?? id
    }
}

private func werewolfRoleStyle(_ role: String) -> (String, String, Color) {
    switch role {
    case "werewolf": return ("Your role: Werewolf", "Hunt the village. You can see your pack.", .red)
    case "seer":     return ("Your role: Seer", "Each night, learn if one player is a werewolf.", .purple)
    case "hunter":   return ("Your role: Hunter", "When you die you take one player down with you.", .orange)
    case "villager": return ("Your role: Villager", "Survive and vote wisely.", .gray)
    default:         return ("Your role", role, .gray)
    }
}

@MainActor
final class WerewolfGuestModel: ObservableObject {
    struct Player: Identifiable { let id: String; let name: String; let isHost: Bool; let alive: Bool }
    struct SeerEntry { let targetId: String; let isWerewolf: Bool; let day: Int }

    @Published var lobby: [Player] = []
    @Published var alive: [Player] = []
    @Published var dead: [Player] = []
    @Published var phase: String = "lobby"
    @Published var day: Int = 0
    @Published var role: String?
    @Published var wolfIds: [String] = []
    @Published var lastNightKilled: String?
    @Published var nightResolved = false
    @Published var seerHistory: [SeerEntry] = []
    @Published var hunterId: String?
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
                                     isHost: $0["isHost"] as? Bool ?? false, alive: true) }
        case "role":
            role = m["role"] as? String
            wolfIds = m["wolfIds"] as? [String] ?? []
        case "phase":
            let prev = phase
            phase = m["phase"] as? String ?? phase
            day = m["day"] as? Int ?? day
            alive = readPlayers(m["alive"]); dead = readPlayers(m["dead"])
            if m["killedId"] != nil {
                lastNightKilled = m["killedId"] as? String
                nightResolved = true
            }
            if prev != phase { picked = nil }
        case "seer_result":
            if let t = m["targetId"] as? String, let w = m["isWerewolf"] as? Bool {
                seerHistory.append(SeerEntry(targetId: t, isWerewolf: w, day: day))
            }
        case "hunter_prompt":
            phase = "hunterShot"
            hunterId = m["hunterId"] as? String
            alive = readPlayers(m["alive"]); dead = readPlayers(m["dead"])
            picked = nil
        case "hunter_shot_result":
            alive = readPlayers(m["alive"]); dead = readPlayers(m["dead"])
        case "day_result":
            alive = readPlayers(m["alive"]); dead = readPlayers(m["dead"])
        case "game_over":
            phase = "gameOver"
            winner = m["winner"] as? String
            if let r = m["roles"] as? [String: String] {
                let combined = lobby + alive + dead
                rolesReveal = r.map { id, role in
                    (id, combined.first(where: { $0.id == id })?.name ?? id, role)
                }.sorted { $0.1 < $1.1 }
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
                                isHost: false, alive: $0["alive"] as? Bool ?? true) }
    }
}
