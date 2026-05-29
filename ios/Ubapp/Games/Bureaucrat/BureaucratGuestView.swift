import SwiftUI

/// Native guest UI for The Bureaucrat. Consumes the same JSON the browser
/// bundle does — see `bureaucrat_browser.html` for the wire protocol.
struct BureaucratGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = BureaucratGuestModel()
    @State private var denialDraft = ""
    @State private var rebuttalDraft = ""
    @State private var now = Date()

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var iAmBureaucrat: Bool { model.bureaucratId == ctx.yourId }
    private var secondsLeft: Int {
        max(0, Int(ceil((model.deadlineMs / 1000) - now.timeIntervalSince1970)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch model.phase {
                case "lobby":     lobby
                case "arguing":   arguing
                case "rebuttal":  rebuttal
                case "roundOver": roundOver
                case "gameOver":  gameOver
                default:          EmptyView()
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("The Bureaucrat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
        .onReceive(ticker) { t in if model.phase == "rebuttal" { now = t } }
        .ubappChrome()
    }

    // MARK: Phases
    @ViewBuilder private var lobby: some View {
        header("The Bureaucrat")
        TutorialGuestCard(state: model.tutorialState, content: model.tutorialContent,
                          myVote: model.myTutorialVote,
                          onCall: { model.send(["type": "call_tutorial_vote"]) },
                          onVote: { yes in model.myTutorialVote = yes
                              model.send(["type": "tutorial_vote", "yes": yes]) })
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Rules")
            Text("First to \(model.targetScore) wins · \(model.challengeTokens) loopholes each · \(model.rebuttalSeconds)s to rebut · \(model.aiAssist ? "AI rebuttal check on" : "timer only")")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).ubCard()
        MonoLabel("In the room · \(model.players.count)")
        ForEach(model.players, id: \.id) { p in
            HStack(spacing: 12) {
                Avatar(name: p.name, host: p.isHost, size: 30)
                Text(p.name).font(.system(size: 15, weight: p.id == ctx.yourId ? .bold : .semibold))
                    .foregroundStyle(.white)
                if p.id == ctx.yourId { MonoLabel("you", size: 9, color: UbappTheme.accent) }
                Spacer()
                if p.isHost { MonoLabel("host", size: 9, color: UbappTheme.faint) }
            }
            .padding(.vertical, 10).padding(.horizontal, 14).ubCard(radius: UbappRadius.row)
        }
    }

    @ViewBuilder private var arguing: some View {
        header("Round \(model.roundNumber)")
        roleBar
        taskCard
        if iAmBureaucrat { denialComposer } else { loopholePanel }
        policyLog
        scoreboard
    }

    @ViewBuilder private var rebuttal: some View {
        header("Loophole!")
        roleBar
        taskCard
        if iAmBureaucrat { rebuttalComposer } else { spectateRebuttal }
        policyLog
    }

    @ViewBuilder private var roundOver: some View {
        header("Round over")
        VStack(alignment: .center, spacing: 6) {
            Text(roundOverText).font(.system(size: 14)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let next = model.nextBureaucratName, !next.isEmpty {
                Text("Next round, \(next) takes the desk.")
                    .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
            }
        }
        .frame(maxWidth: .infinity).padding(16).ubCard()
        scoreboard
        infoBanner("Waiting for the host to start the next round…")
    }

    @ViewBuilder private var gameOver: some View {
        header("\(model.winnerName.isEmpty ? "Someone" : model.winnerName) wins!")
        infoBanner("First past \(model.targetScore) points. The office is finally closed.")
        scoreboard
    }

    // MARK: Pieces
    private func header(_ t: String) -> some View {
        Text(t).font(.system(size: 28, weight: .heavy)).kerning(-0.8).foregroundStyle(.white)
    }

    @ViewBuilder private var roleBar: some View {
        HStack(spacing: 10) {
            Text(iAmBureaucrat ? "You are the Bureaucrat" : "Citizen")
                .font(.system(size: 10, weight: .bold)).kerning(1.2).textCase(.uppercase)
                .foregroundStyle(iAmBureaucrat ? UbappTheme.onAccent : .white)
                .padding(.vertical, 4).padding(.horizontal, 10)
                .background(iAmBureaucrat ? UbappTheme.accent : Color.white.opacity(0.08))
                .clipShape(Capsule())
            if !iAmBureaucrat, !model.bureaucratName.isEmpty {
                Text("Bureaucrat: \(model.bureaucratName)")
                    .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
            }
        }
    }

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("The task before the office", color: UbappTheme.accent)
            Text(model.task).font(.system(size: 19, weight: .heavy)).foregroundStyle(.white)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(radius: UbappRadius.panel, fill: UbappTheme.accentSoft, stroke: UbappTheme.accentLine)
    }

    private var denialComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Issue a denial")
            Text("Every denial becomes binding policy. Be specific — but specifics can be turned against you.")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
            TextField("e.g. Form 7B is required for all exemptions.", text: $denialDraft, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder).foregroundStyle(.black)
            Button("Add to policy log") {
                let t = denialDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { model.send(["type": "denial", "text": t]); denialDraft = "" }
            }
            .buttonStyle(UbPrimaryButtonStyle())
            .disabled(denialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).ubCard()
    }

    private var loopholePanel: some View {
        let left = model.tokens[ctx.yourId] ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Find the loophole")
            Text("Argue out loud. When you've trapped the Bureaucrat in their own logic, call a loophole — they must rebut before the clock runs out.")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
            Button("Call loophole (\(left) left)") { model.send(["type": "call_loophole"]) }
                .buttonStyle(UbPrimaryButtonStyle())
                .disabled(left <= 0)
            if left <= 0 {
                Text("You're out of challenges this round.")
                    .font(.system(size: 13)).foregroundStyle(UbappTheme.faint)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).ubCard()
    }

    private var rebuttalComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Rebuttal demanded")
            Text("\(model.challengerName) called a loophole. Defend your policy before the clock runs out.")
                .font(.system(size: 14)).foregroundStyle(.white)
            countdown
            TextField("Your binding rebuttal…", text: $rebuttalDraft, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder).foregroundStyle(.black)
            Button("Submit rebuttal") {
                let t = rebuttalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { model.send(["type": "rebuttal", "text": t]); rebuttalDraft = "" }
            }
            .buttonStyle(UbPrimaryButtonStyle())
            .disabled(rebuttalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).ubCard()
    }

    private var spectateRebuttal: some View {
        VStack(alignment: .center, spacing: 8) {
            MonoLabel("Loophole called")
            Text("\(model.challengerName) is challenging the Bureaucrat.")
                .font(.system(size: 14)).foregroundStyle(.white)
            countdown
            Text("If the Bureaucrat can't rebut in time, \(model.challengerName) takes the round.")
                .font(.system(size: 13)).foregroundStyle(UbappTheme.muted).multilineTextAlignment(.center)
        }
        .padding(16).frame(maxWidth: .infinity).ubCard()
    }

    private var countdown: some View {
        Text("\(secondsLeft)s")
            .font(.system(size: 46, weight: .heavy)).kerning(-1)
            .foregroundStyle(secondsLeft <= 5 ? UbappTheme.accent : .white)
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var policyLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Policy log")
            if model.policyLog.isEmpty {
                Text("No policy on record yet. The Bureaucrat has said nothing binding… for now.")
                    .font(.system(size: 13)).foregroundStyle(UbappTheme.muted)
            } else {
                ForEach(Array(model.policyLog.enumerated()), id: \.offset) { item in
                    let e = item.element
                    VStack(alignment: .leading, spacing: 4) {
                        MonoLabel(e.isRebuttal ? "rebuttal" : "policy §\(item.offset + 1)", size: 9, color: UbappTheme.faint)
                        Text(e.text).font(.system(size: 14)).foregroundStyle(.white)
                    }
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ubCard(radius: UbappRadius.row,
                            fill: e.isRebuttal ? UbappTheme.accentSoft : UbappTheme.surface,
                            stroke: e.isRebuttal ? UbappTheme.accentLine : UbappTheme.line)
                }
            }
        }
    }

    @ViewBuilder private var scoreboard: some View {
        if !model.scores.isEmpty {
            let maxScore = model.scores.values.max() ?? 0
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("Scores · first to \(model.targetScore)")
                ForEach(model.scores.sorted { $0.value > $1.value }, id: \.key) { row in
                    let lead = row.value == maxScore && maxScore > 0
                    HStack {
                        Text(model.nameOf(row.key) + (row.key == ctx.yourId ? " (you)" : ""))
                            .font(.system(size: 14)).foregroundStyle(.white)
                        Spacer()
                        Text("\(row.value)").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: UbappRadius.row,
                            fill: lead ? UbappTheme.accentSoft : UbappTheme.surface,
                            stroke: lead ? UbappTheme.accentLine : UbappTheme.line)
                }
            }
        }
    }

    private var roundOverText: String {
        let who = model.lastChallengerName.isEmpty ? "A citizen" : model.lastChallengerName
        switch model.lastReason {
        case "timeout": return "\(who) found the loophole — the Bureaucrat couldn't rebut in time."
        case "contradiction": return "\(who) won — the rebuttal contradicted the office's own policy."
        case "survived": return "The Bureaucrat survived the round. No loophole stuck."
        case "exhausted": return "The citizens ran out of challenges. The Bureaucrat survives."
        default: return ""
        }
    }

    private func infoBanner(_ text: String) -> some View {
        Text(text).font(.system(size: 14)).foregroundStyle(UbappTheme.muted)
            .padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading).ubCard(radius: UbappRadius.row)
    }
}

@MainActor
final class BureaucratGuestModel: ObservableObject {
    struct Player: Identifiable { let id: String; let name: String; let isHost: Bool }
    struct Entry { let text: String; let isRebuttal: Bool; let challengerId: String? }

    @Published var players: [Player] = []
    @Published var phase = "lobby"
    @Published var roundNumber = 0
    @Published var bureaucratId: String?
    @Published var bureaucratName = ""
    @Published var task = ""
    @Published var targetScore = 10
    @Published var challengeTokens = 2
    @Published var rebuttalSeconds = 20
    @Published var aiAssist = true
    @Published var scores: [String: Int] = [:]
    @Published var tokens: [String: Int] = [:]
    @Published var policyLog: [Entry] = []
    @Published var challengerName = ""
    @Published var deadlineMs: Double = 0
    @Published var lastReason = ""
    @Published var lastChallengerName = ""
    @Published var nextBureaucratName: String?
    @Published var winnerName = ""
    @Published var tutorialState = GuestTutorialState()
    @Published var tutorialContent: GuestTutorialContent?
    @Published var myTutorialVote: Bool?

    private weak var client: (any GuestLink)?

    func nameOf(_ id: String) -> String { players.first { $0.id == id }?.name ?? id }

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
        case "options":
            targetScore = m["targetScore"] as? Int ?? targetScore
            challengeTokens = m["challengeTokens"] as? Int ?? challengeTokens
            rebuttalSeconds = m["rebuttalSeconds"] as? Int ?? rebuttalSeconds
            aiAssist = m["aiAssist"] as? Bool ?? aiAssist
        case "round", "policy":
            applyRound(m)
        case "rebuttal_open":
            phase = "rebuttal"
            challengerName = m["challengerName"] as? String ?? ""
            deadlineMs = numeric(m["deadlineMs"])
            rebuttalSeconds = m["seconds"] as? Int ?? rebuttalSeconds
            if let log = m["policyLog"] { policyLog = readLog(log) }
        case "round_over":
            phase = "roundOver"
            lastReason = m["reason"] as? String ?? ""
            lastChallengerName = m["challengerName"] as? String ?? ""
            if let nid = m["nextBureaucratId"] as? String { nextBureaucratName = nameOf(nid) }
            else { nextBureaucratName = nil }
            scores = readScores(m["scores"])
            targetScore = m["targetScore"] as? Int ?? targetScore
            if let log = m["policyLog"] { policyLog = readLog(log) }
        case "game_over":
            phase = "gameOver"
            winnerName = m["winnerName"] as? String ?? ""
            scores = readScores(m["scores"])
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

    private func applyRound(_ m: [String: Any]) {
        phase = (m["phase"] as? String == "rebuttal") ? "rebuttal" : "arguing"
        roundNumber = m["roundNumber"] as? Int ?? roundNumber
        bureaucratId = m["bureaucratId"] as? String
        bureaucratName = m["bureaucratName"] as? String ?? ""
        task = m["task"] as? String ?? ""
        targetScore = m["targetScore"] as? Int ?? targetScore
        scores = readScores(m["scores"])
        tokens = readScores(m["tokens"])
        policyLog = readLog(m["policyLog"])
    }

    private func readLog(_ raw: Any?) -> [Entry] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.map { Entry(text: $0["text"] as? String ?? "",
                               isRebuttal: $0["isRebuttal"] as? Bool ?? false,
                               challengerId: $0["challengerId"] as? String) }
    }
    private func readScores(_ raw: Any?) -> [String: Int] {
        guard let o = raw as? [String: Any] else { return [:] }
        var out: [String: Int] = [:]
        for (k, v) in o { out[k] = (v as? Int) ?? Int(numeric(v)) }
        return out
    }
    private func numeric(_ v: Any?) -> Double {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let n = v as? NSNumber { return n.doubleValue }
        return 0
    }
}
