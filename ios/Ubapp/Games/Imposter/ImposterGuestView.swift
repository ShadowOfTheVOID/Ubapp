import SwiftUI

/// Native guest UI for Imposter — see `imposter_browser.html` for the wire protocol.
struct ImposterGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = ImposterGuestModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MonoLabel(phaseLabel, color: UbappTheme.accent)
                if let err = model.error {
                    Text(err).font(.system(size: 13, weight: .semibold)).foregroundStyle(UbappTheme.accent)
                        .padding(.vertical, 12).padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .ubAccentCard(radius: UbappRadius.row)
                }
                SeriesBanner(state: model.series)
                switch model.phase {
                case "lobby":   lobby
                case "playing": playing
                case "voting":  voting
                case "result":  result
                default:        infoBanner("Waiting…")
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Imposter")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
        .ubappChrome()
    }

    private var phaseLabel: String {
        switch model.phase {
        case "playing": "Imposter · clue round"
        case "voting": "Imposter · vote"
        case "result": "Imposter · result"
        default: "Imposter · lobby"
        }
    }

    private func infoBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14)).foregroundStyle(UbappTheme.muted)
            .padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard(radius: UbappRadius.row)
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
            MonoLabel("In the room · \(model.players.count)")
            VStack(spacing: 8) {
                ForEach(model.players, id: \.id) { p in
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

    @ViewBuilder private var playing: some View {
        if model.isImposter {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Your secret role", color: UbappTheme.accent)
                Text("You are the Imposter.")
                    .font(.system(size: 32, weight: .heavy)).kerning(-1).foregroundStyle(UbappTheme.accent)
                if !model.hideCategory {
                    MonoLabel("Category · \(model.category)", size: 10)
                }
                if let decoy = model.word, model.isDecoy {
                    Text("Decoy word: \(decoy)")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                    Text("This isn't the real word — bluff carefully.")
                        .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
                } else {
                    Text("Blend in. Give a clue vague enough to survive.")
                        .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard(radius: UbappRadius.panel, fill: UbappTheme.accentSoft, stroke: UbappTheme.accentLine)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Secret word", color: UbappTheme.accent)
                Text(model.word ?? "—")
                    .font(.system(size: 36, weight: .heavy)).kerning(-1).foregroundStyle(.white)
                MonoLabel("Category · \(model.category)", size: 10)
                Text("Drop a clue that proves you know it — without giving it away.")
                    .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard(radius: UbappRadius.panel)
        }
        if !model.firstPlayerName.isEmpty {
            let who = model.firstPlayerId == ctx.yourId
                ? "You go first" : "\(model.firstPlayerName) goes first"
            let dir = model.direction == "counterclockwise" ? "counter-clockwise" : "clockwise"
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("Speaking order")
                Text("\(who) — then continue \(dir).")
                    .font(.system(size: 14)).foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard()
        }
        infoBanner("Waiting for the host to call a vote…")
    }

    @ViewBuilder private var voting: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Pick the imposter")
            let others = model.players.filter { $0.id != ctx.yourId }
            let cols = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(others, id: \.id) { p in pickCell(id: p.id, name: p.name) }
                pickCell(id: "__skip", name: "Skip")
            }
            Button(model.voted ? "Vote in ✓" : "Lock in vote") {
                let target: Any = model.picked == "__skip" ? NSNull() : (model.picked ?? "")
                model.send(["type": "vote", "targetId": target])
                model.voted = true
            }
            .buttonStyle(UbPrimaryButtonStyle())
            .disabled(model.voted || model.picked == nil)
            .opacity(model.voted || model.picked == nil ? 0.5 : 1)
        }
    }

    private func pickCell(id: String, name: String) -> some View {
        let selected = model.picked == id
        return Button { if !model.voted { model.picked = id } } label: {
            HStack(spacing: 8) {
                if id != "__skip" { Avatar(name: name, size: 24) }
                Text(name).font(.system(size: 13, weight: .semibold))
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
        .disabled(model.voted)
    }

    @ViewBuilder private var result: some View {
        let townWins = model.winner == "town"
        let names = model.imposterIds.compactMap { id in
            model.players.first(where: { $0.id == id })?.name
        }
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Result", color: UbappTheme.accent)
            Text(townWins ? "Town wins" : "Imposter wins")
                .font(.system(size: 30, weight: .heavy)).kerning(-1)
                .foregroundStyle(townWins ? .white : UbappTheme.accent)
        }
        VStack(alignment: .leading, spacing: 10) {
            let label = names.count == 1 ? "imposter was" : "imposters were"
            Text(names.isEmpty ? "Imposters: ?" : "The \(label) \(names.joined(separator: ", ")).")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            if let m = model.mostVotedId, let p = model.players.first(where: { $0.id == m }) {
                Text("You voted out \(p.name) — \(model.imposterCaught ? "correct!" : "wrong.")")
                    .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
            } else {
                Text("The vote tied — no one was eliminated.")
                    .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
            }
            MonoLabel("Word · \(model.resultWord) (\(model.category))", size: 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(radius: UbappRadius.panel)
    }
}

@MainActor
final class ImposterGuestModel: ObservableObject {
    struct Player: Identifiable { let id: String; let name: String; let isHost: Bool }
    @Published var players: [Player] = []
    @Published var phase: String = "lobby"
    @Published var category: String = ""
    @Published var word: String?
    @Published var isImposter = false
    @Published var picked: String?
    @Published var voted = false
    @Published var winner: String?
    @Published var imposterIds: [String] = []
    @Published var imposterCaught = false
    @Published var mostVotedId: String?
    @Published var resultWord: String = ""
    @Published var hideCategory = false
    @Published var isDecoy = false
    @Published var firstPlayerId: String?
    @Published var firstPlayerName: String = ""
    @Published var direction: String = "clockwise"
    @Published var error: String?
    @Published var tutorialState = GuestTutorialState()
    @Published var tutorialContent: GuestTutorialContent?
    @Published var myTutorialVote: Bool?
    @Published var series = GuestSeriesState()

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
                                       isHost: $0["isHost"] as? Bool ?? false) }
            phase = "lobby"
        case "role":
            category = m["category"] as? String ?? ""
            word = m["word"] as? String
            isImposter = m["isImposter"] as? Bool ?? false
            hideCategory = m["hideCategory"] as? Bool ?? false
            isDecoy = m["isDecoy"] as? Bool ?? false
            firstPlayerId = m["firstPlayerId"] as? String
            firstPlayerName = m["firstPlayerName"] as? String ?? ""
            direction = m["direction"] as? String ?? "clockwise"
            phase = "playing"; voted = false; picked = nil
        case "voting":
            phase = "voting"; voted = false; picked = nil
        case "result":
            phase = "result"
            winner = m["winner"] as? String
            if let ids = m["imposterIds"] as? [String] { imposterIds = ids }
            else if let single = m["imposterId"] as? String { imposterIds = [single] }
            imposterCaught = m["imposterCaught"] as? Bool ?? false
            mostVotedId = m["mostVotedId"] as? String
            resultWord = m["word"] as? String ?? ""
            if let category = m["category"] as? String { self.category = category }
            if let plist = m["players"] as? [[String: Any]] {
                players = plist.map { Player(id: $0["id"] as? String ?? "",
                                             name: $0["name"] as? String ?? "",
                                             isHost: $0["isHost"] as? Bool ?? false) }
            }
        case "reset":
            phase = "lobby"; word = nil; isImposter = false
        case "series_state":
            series.apply(m)
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
}
