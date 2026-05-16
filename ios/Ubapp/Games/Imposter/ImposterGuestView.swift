import SwiftUI

/// Native guest UI for Imposter — see `imposter_browser.html` for the wire protocol.
struct ImposterGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = ImposterGuestModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Playing as \(ctx.yourName)").font(.caption).foregroundStyle(.secondary)
                if let err = model.error {
                    Text(err).foregroundStyle(.white).padding().frame(maxWidth: .infinity)
                        .background(Color.red).cornerRadius(12)
                }
                switch model.phase {
                case "lobby":   lobby
                case "playing": playing
                case "voting":  voting
                case "result":  result
                default:        Text("Waiting…").foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Imposter")
        .onAppear { model.attach(ctx: ctx) }
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
                    if p.id == ctx.yourId { Text("you").font(.caption).foregroundStyle(.blue) }
                }
            }
        }
    }

    @ViewBuilder private var playing: some View {
        if model.isImposter {
            GroupBox {
                VStack(spacing: 12) {
                    Text("YOUR ROLE").font(.caption).foregroundStyle(.secondary)
                    Text("IMPOSTER").font(.system(size: 42, weight: .heavy)).foregroundStyle(.red)
                    if !model.hideCategory {
                        Text("Category: \(model.category)").foregroundStyle(.secondary)
                    }
                    if let decoy = model.word, model.isDecoy {
                        Text("Decoy word: \(decoy)")
                            .font(.system(size: 24, weight: .bold))
                        Text("This isn't the real word — bluff carefully.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Bluff your way through.").font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(8)
            }
        } else {
            GroupBox {
                VStack(spacing: 12) {
                    Text("SECRET WORD").font(.caption).foregroundStyle(.secondary)
                    Text(model.word ?? "—").font(.system(size: 38, weight: .heavy))
                    Text("Category: \(model.category)").foregroundStyle(.secondary)
                    Text("Find the imposter.").font(.caption).foregroundStyle(.secondary)
                }.padding(8)
            }
        }
        Text("Waiting for the host to call a vote…").foregroundStyle(.secondary)
    }

    @ViewBuilder private var voting: some View {
        GroupBox("Pick the imposter") {
            let others = model.players.filter { $0.id != ctx.yourId }
            ForEach(others, id: \.id) { p in
                Button { model.picked = p.id } label: {
                    HStack { Text(p.name); Spacer()
                        if model.picked == p.id { Image(systemName: "checkmark.circle.fill") } }
                    .padding(.vertical, 6)
                }.disabled(model.voted)
            }
            Button { model.picked = "__skip" } label: {
                HStack { Text("Skip"); Spacer()
                    if model.picked == "__skip" { Image(systemName: "checkmark.circle.fill") } }
            }.disabled(model.voted)
            Button(model.voted ? "Vote in ✓" : "Lock in vote") {
                let target: Any = model.picked == "__skip" ? NSNull() : (model.picked ?? "")
                model.send(["type": "vote", "targetId": target])
                model.voted = true
            }
            .disabled(model.voted || model.picked == nil)
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private var result: some View {
        let winner = model.winner == "town" ? "Town wins" : "Imposter wins"
        GroupBox(winner) {
            let names = model.imposterIds.compactMap { id in
                model.players.first(where: { $0.id == id })?.name
            }
            let label = names.count == 1 ? "imposter was" : "imposters were"
            Text(names.isEmpty ? "Imposters: ?" : "The \(label) \(names.joined(separator: ", ")).")
            if let m = model.mostVotedId, let p = model.players.first(where: { $0.id == m }) {
                Text("You voted out \(p.name) — \(model.imposterCaught ? "correct!" : "wrong.")")
            } else {
                Text("The vote tied — no one was eliminated.")
            }
            Text("Secret word was \(model.resultWord) (\(model.category)).")
                .foregroundStyle(.secondary)
        }
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
    @Published var error: String?
    @Published var tutorialState = GuestTutorialState()
    @Published var tutorialContent: GuestTutorialContent?
    @Published var myTutorialVote: Bool?

    private weak var client: GuestClient?

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
