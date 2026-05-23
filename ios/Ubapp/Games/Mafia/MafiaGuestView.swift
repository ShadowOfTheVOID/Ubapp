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
                if let e = model.error { errorBanner(e) }
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
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Mafia")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
        .ubappChrome()
    }

    private var phaseLabel: String {
        switch model.phase {
        case "night": "Mafia · night \(max(model.day, 1))"
        case "dayReveal": "Mafia · dawn"
        case "dayVote": "Mafia · day \(model.day)"
        case "gameOver": "Mafia · over"
        default: "Mafia · lobby"
        }
    }

    @ViewBuilder private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            MonoLabel(phaseLabel, color: UbappTheme.accent)
            Spacer()
            if model.phase != "lobby" {
                MonoLabel(iAmAlive ? "alive" : "out",
                          size: 9, color: iAmAlive ? UbappTheme.online : UbappTheme.faint)
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(UbappTheme.accent)
            .padding(.vertical, 12).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubAccentCard(radius: UbappRadius.row)
    }

    @ViewBuilder private var lobby: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Waiting for the host")
                .font(.system(size: 26, weight: .heavy)).kerning(-0.8).foregroundStyle(.white)
            Text("Playing as \(ctx.yourName)")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
        }
        TutorialGuestCard(state: model.tutorialState, content: model.tutorialContent,
                          myVote: model.myTutorialVote,
                          onCall: { model.send(["type": "call_tutorial_vote"]) },
                          onVote: { yes in model.myTutorialVote = yes
                              model.send(["type": "tutorial_vote", "yes": yes]) })
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("In the room · \(model.lobby.count)")
            VStack(spacing: 8) {
                ForEach(model.lobby, id: \.id) { p in
                    HStack(spacing: 12) {
                        Avatar(name: p.name, host: p.isHost, size: 30)
                        Text(p.name).font(.system(size: 15, weight: p.id == ctx.yourId ? .bold : .semibold))
                            .foregroundStyle(.white)
                        if p.id == ctx.yourId { MonoLabel("you", size: 9, color: UbappTheme.accent) }
                        Spacer()
                        if p.isHost { MonoLabel("host", size: 9, color: UbappTheme.faint) }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: UbappRadius.row)
                }
            }
        }
    }

    @ViewBuilder private var night: some View {
        roleCard
        if !iAmAlive {
            spectator
        } else if model.role == "mafia" {
            targetPicker(prompt: "Tap a player to kill",
                         targets: model.alive.filter { $0.id != ctx.yourId },
                         kind: "night", verb: "Lock in kill")
        } else if model.role == "doctor" {
            targetPicker(prompt: "Choose someone to save",
                         targets: model.alive, kind: "night", verb: "Lock in save")
        } else {
            infoBanner("The mafia and doctor are choosing in the dark…")
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
                         kind: "vote", verb: "Lock in vote", allowSkip: true)
        }
    }

    @ViewBuilder private var gameOver: some View {
        let mafiaWin = model.winner == "mafia"
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Game over", color: UbappTheme.accent)
            Text(mafiaWin ? "Mafia win" : "Town wins")
                .font(.system(size: 30, weight: .heavy)).kerning(-1)
                .foregroundStyle(mafiaWin ? UbappTheme.accent : .white)
        }
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Full reveal")
            VStack(spacing: 8) {
                ForEach(model.rolesReveal, id: \.id) { entry in
                    let isMafia = entry.role == "mafia"
                    HStack(spacing: 12) {
                        Avatar(name: entry.name, size: 30)
                        Text(entry.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text(entry.role.capitalized)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isMafia ? UbappTheme.onAccent : UbappTheme.muted)
                            .padding(.vertical, 5).padding(.horizontal, 10)
                            .background(isMafia ? UbappTheme.accent : Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: UbappRadius.row)
                }
            }
        }
    }

    @ViewBuilder private var waiting: some View {
        infoBanner("Waiting…")
    }

    @ViewBuilder private var spectator: some View {
        infoBanner("You're out — watching from the sidelines.")
    }

    private func infoBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14)).foregroundStyle(UbappTheme.muted)
            .padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard(radius: UbappRadius.row)
    }

    @ViewBuilder private var roleCard: some View {
        if let role = model.role {
            let m = roleMeta(role)
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("Your secret role", color: UbappTheme.accent)
                (Text("You are ") + Text(m.name + ".")
                    .foregroundColor(m.accent ? UbappTheme.accent : .white))
                    .font(.system(size: 32, weight: .heavy)).kerning(-1)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text(m.letter)
                    .font(.system(size: 28, weight: .heavy)).kerning(-1)
                    .foregroundStyle(m.accent ? UbappTheme.onAccent : .white)
                    .frame(width: 56, height: 56)
                    .background(m.accent ? UbappTheme.accent : UbappTheme.surfaceHi)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel("Team \(m.team)", color: m.accent ? UbappTheme.accent : UbappTheme.muted)
                    Text(m.name).font(.system(size: 22, weight: .heavy)).foregroundStyle(.white)
                    Text(m.blurb).font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
                }
                if role == "mafia", model.mafiaIds.count > 1 {
                    let others = model.mafiaIds.filter { $0 != ctx.yourId }
                        .compactMap { id in model.lobby.first(where: { $0.id == id })?.name
                            ?? model.alive.first(where: { $0.id == id })?.name }
                    if !others.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            MonoLabel("Team-mates", size: 9)
                            Text(others.joined(separator: ", "))
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard(radius: UbappRadius.panel,
                    fill: m.accent ? UbappTheme.accentSoft : UbappTheme.surface,
                    stroke: m.accent ? UbappTheme.accentLine : UbappTheme.line)
        }
    }

    @ViewBuilder private var lastNightSummary: some View {
        if let k = model.lastNightKilled {
            infoBanner("\(playerName(k)) was killed in the night.")
        } else if model.lastNightSaved != nil {
            infoBanner("The doctor saved someone — no one died.")
        } else if model.nightResolved {
            infoBanner("A quiet night. No one died.")
        }
    }

    @ViewBuilder private var playersSection: some View {
        if model.phase != "lobby" && (model.alive.count + model.dead.count) > 0 {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Players · \(model.alive.count) alive")
                let cols = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(model.alive, id: \.id) { p in playerCell(p, alive: true) }
                    ForEach(model.dead, id: \.id) { p in playerCell(p, alive: false) }
                }
            }
        }
    }

    private func playerCell(_ p: MafiaGuestModel.Player, alive: Bool) -> some View {
        HStack(spacing: 10) {
            Avatar(name: p.name, host: p.isHost, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.name).font(.system(size: 12, weight: .semibold))
                    .strikethrough(!alive).foregroundStyle(alive ? .white : UbappTheme.muted)
                MonoLabel(alive ? "alive" : "dead", size: 9,
                          color: alive ? UbappTheme.faint : UbappTheme.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .ubCard(radius: UbappRadius.button,
                fill: alive ? UbappTheme.surface : UbappTheme.accentSoft,
                stroke: alive ? UbappTheme.line : UbappTheme.accentLine)
    }

    @ViewBuilder
    private func targetPicker(prompt: String, targets: [MafiaGuestModel.Player],
                              kind: String, verb: String, allowSkip: Bool = false) -> some View {
        let submitted = model.submittedKind == kind && model.submittedDay == model.day
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(prompt)
            let cols = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(targets, id: \.id) { p in pickCell(id: p.id, name: p.name, submitted: submitted) }
                if allowSkip { pickCell(id: "__skip", name: "Skip vote", submitted: submitted) }
            }
            Button(submitted ? "Submitted" : verb) {
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
            .buttonStyle(UbPrimaryButtonStyle())
            .disabled(submitted || model.picked == nil)
            .opacity(submitted || model.picked == nil ? 0.5 : 1)
        }
    }

    private func pickCell(id: String, name: String, submitted: Bool) -> some View {
        let selected = model.picked == id
        return Button { if !submitted { model.picked = id } } label: {
            HStack(spacing: 8) {
                if id != "__skip" { Avatar(name: name, size: 24) }
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? UbappTheme.onAccent : .white)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 9).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? UbappTheme.accent : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? Color.clear : UbappTheme.lineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(submitted)
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

private func roleMeta(_ role: String) -> (name: String, team: String, blurb: String, letter: String, accent: Bool) {
    switch role {
    case "mafia":    return ("Mafia", "Mafia", "Wake at night and pick a target. Lie convincingly by day.", "M", true)
    case "doctor":   return ("Doctor", "Town", "Save one player each night. You can self-save once.", "D", false)
    case "detective": return ("Detective", "Town", "Investigate one player each night to learn their side.", "?", false)
    case "villager": return ("Villager", "Town", "No night power — use your vote by day to find the mafia.", "V", false)
    default:         return (role.capitalized, "Town", role, "•", false)
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
