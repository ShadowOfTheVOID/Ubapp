import SwiftUI

/// Native guest UI for Secret Hitler — wire protocol from `secret_hitler_browser.html`.
struct SecretHitlerGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = SecretHitlerGuestModel()
    @State private var showInterstitial = false
    @State private var interstitialFired = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.phase == "gameOver" {
                        gameOver
                    } else if model.phase == "lobby" {
                        lobby
                    } else {
                        roleCard
                        tracks
                        government
                        phaseSection
                        chatSection
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(20)
            }
            .scrollIndicators(.hidden)
            if model.phase == "gameOver" {
                AdBannerView(placement: .betweenRounds)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
        }
        .adInterstitial(isPresented: $showInterstitial)
        .onChange(of: model.phase) { _, newPhase in
            if newPhase == "gameOver" && !interstitialFired {
                interstitialFired = true
                showInterstitial = true
            }
        }
        .navigationTitle("Secret Hitler")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.attach(ctx: ctx) }
        .onDisappear { ctx.client.onMessage = nil }
        .jamboreeChrome()
    }

    @ViewBuilder private var lobby: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Secret Hitler · lobby", color: JamboreeTheme.accent)
            Text("Waiting for the deal")
                .font(.system(size: 26, weight: .heavy)).kerning(-0.8).foregroundStyle(.white)
            Text("Playing as \(ctx.yourName) · 5–10 players")
                .font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
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
                        Spacer()
                        if p.isHost { MonoLabel("host", size: 9, color: JamboreeTheme.faint) }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14).ubCard(radius: JamboreeRadius.row)
                }
            }
        }
    }

    @ViewBuilder private var roleCard: some View {
        if let role = model.role {
            let m = roleMeta(role)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Text(m.glyph)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(m.ink)
                        .frame(width: 52, height: 52)
                        .background(m.color)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        MonoLabel("You are · team \(m.team)", size: 9, color: m.color)
                        Text(m.name).font(.system(size: 28, weight: .heavy)).kerning(-1).foregroundStyle(.white)
                    }
                }
                Text(m.blurb).font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
                if !model.allies.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        MonoLabel("You know", size: 9)
                        ForEach(Array(model.allies.enumerated()), id: \.offset) { _, ally in
                            HStack(spacing: 10) {
                                Avatar(name: ally.name, size: 24)
                                Text(ally.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                Spacer()
                                MonoLabel(ally.role == "hitler" ? "Hitler" : "Fascist", size: 9,
                                          color: ally.role == "hitler" ? .white : SH.fascist)
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard(radius: JamboreeRadius.panel, fill: m.color.opacity(0.12), stroke: m.color.opacity(0.45))
        }
    }

    private var tracks: some View {
        VStack(spacing: 8) {
            SHTrackView(title: "Liberal track", filled: model.liberalPolicies, max: 5,
                        color: SH.liberal, glyph: "★")
            SHTrackView(title: "Fascist track", filled: model.fascistPolicies, max: 6,
                        color: SH.fascist, glyph: "✖")
            HStack(spacing: 10) {
                MonoLabel("Election tracker")
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i < model.electionTracker ? JamboreeTheme.accent : Color.white.opacity(0.06))
                            .frame(height: 16)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(JamboreeTheme.lineStrong, lineWidth: 1))
                    }
                }
                MonoLabel("\(model.electionTracker)/3", size: 9, color: JamboreeTheme.faint)
            }
            .padding(.horizontal, 12).padding(.vertical, 10).ubCard(radius: JamboreeRadius.row)
        }
    }

    private var government: some View {
        HStack(spacing: 14) {
            slatePerson(playerName(model.presidentId), "President")
            Text("×").font(.system(size: 22)).foregroundStyle(JamboreeTheme.muted)
            slatePerson(playerName(model.chancellorId ?? model.chancellorNomineeId), "Chancellor")
            Spacer()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).ubCard(radius: JamboreeRadius.row)
    }

    private func slatePerson(_ name: String, _ role: String) -> some View {
        VStack(spacing: 4) {
            Avatar(name: name, host: role == "President", size: 40)
            MonoLabel(role, size: 9, color: JamboreeTheme.accent)
            Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        }
    }

    @ViewBuilder private var phaseSection: some View {
        let amPresident = model.presidentId == ctx.yourId
        let amChancellor = model.chancellorId == ctx.yourId
        switch model.phase {
        case "nomination":
            if amPresident {
                pickList("Nominate a Chancellor",
                         model.players.filter { model.eligibleChancellors.contains($0.id) }) { p in
                    model.send(["type": "nominate", "targetId": p.id])
                }
            } else { waiting("\(playerName(model.presidentId)) is nominating a Chancellor") }
        case "election":
            let meAlive = model.players.first { $0.id == ctx.yourId }?.alive ?? false
            if !meAlive { waiting("Watching from the sidelines") }
            else if model.voted {
                waiting("Vote locked in · \(model.voteProgress)/\(model.voteTotal) voted")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    MonoLabel("Vote on the government")
                    HStack(spacing: 12) {
                        voteButton("JA!", "YES", color: SH.liberal, ink: SH.liberalInk) {
                            model.send(["type": "vote", "ja": true]); model.voted = true
                        }
                        voteButton("NEIN!", "NO", color: SH.fascist, ink: SH.fascistInk) {
                            model.send(["type": "vote", "ja": false]); model.voted = true
                        }
                    }
                    MonoLabel("\(model.voteProgress)/\(model.voteTotal) voted", size: 9, color: JamboreeTheme.faint)
                }
            }
        case "presidentDiscard":
            if amPresident, let hand = model.presidentialHand {
                policyChoice("Discard one — two go to the Chancellor", hand, verb: "Discard") { i in
                    model.send(["type": "discard", "index": i])
                }
            } else { waiting("\(playerName(model.presidentId)) is discarding") }
        case "chancellorEnact":
            if amChancellor, let hand = model.chancellorHand {
                VStack(alignment: .leading, spacing: 10) {
                    policyChoice("Enact one policy", hand, verb: "Enact") { i in
                        model.send(["type": "enact", "index": i])
                    }
                    if model.vetoUnlocked {
                        Button("Request veto") { model.send(["type": "request_veto"]) }
                            .buttonStyle(UbSecondaryButtonStyle())
                    }
                }
            } else { waiting("\(playerName(model.chancellorId)) is enacting a policy") }
        case "vetoDecision":
            if amPresident {
                VStack(alignment: .leading, spacing: 10) {
                    MonoLabel("Chancellor wants to veto")
                    HStack(spacing: 10) {
                        Button("Agree — veto") { model.send(["type": "veto_response", "confirm": true]) }
                            .buttonStyle(UbPrimaryButtonStyle())
                        Button("Refuse") { model.send(["type": "veto_response", "confirm": false]) }
                            .buttonStyle(UbSecondaryButtonStyle())
                    }
                }
            } else { waiting("Veto requested — \(playerName(model.presidentId)) is deciding") }
        case "policyPeek":
            if amPresident, let peek = model.peekedPolicies {
                VStack(alignment: .leading, spacing: 10) {
                    MonoLabel("Top three policies")
                    HStack(spacing: 10) {
                        ForEach(Array(peek.enumerated()), id: \.offset) { _, pol in
                            SHPolicyView(team: pol == "liberal" ? "L" : "F", width: 72)
                        }
                    }
                    Button("Done") { model.send(["type": "ack_peek"]) }.buttonStyle(UbPrimaryButtonStyle())
                }
            } else { waiting("\(playerName(model.presidentId)) is peeking at the deck") }
        case "investigation":
            if amPresident {
                pickList("Investigate a player's party",
                         model.players.filter {
                             $0.alive && $0.id != model.presidentId && !model.investigatedIds.contains($0.id)
                         }) { p in model.send(["type": "investigate", "targetId": p.id]) }
            } else { waiting("\(playerName(model.presidentId)) is investigating") }
        case "investigationReveal":
            if amPresident, let inv = model.investigationResult {
                let party = inv.party.capitalized
                VStack(alignment: .leading, spacing: 10) {
                    MonoLabel("Investigation", color: JamboreeTheme.accent)
                    Text("\(playerName(inv.subjectId)) is \(party)")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(inv.party == "fascist" ? SH.fascist : SH.liberal)
                    Text("Share it or lie about it.").font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
                    Button("Done") { model.send(["type": "ack_investigation"]) }.buttonStyle(UbPrimaryButtonStyle())
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).ubCard(radius: JamboreeRadius.panel)
            } else { waiting("\(playerName(model.presidentId)) has the investigation result") }
        case "specialElection":
            if amPresident {
                pickList("Pick the next President",
                         model.players.filter { $0.alive && $0.id != model.presidentId }) { p in
                    model.send(["type": "special_election", "targetId": p.id])
                }
            } else { waiting("\(playerName(model.presidentId)) is calling a special election") }
        case "execution":
            if amPresident {
                pickList("Execute a player",
                         model.players.filter { $0.alive && $0.id != model.presidentId }) { p in
                    model.send(["type": "execute", "targetId": p.id])
                }
            } else { waiting("\(playerName(model.presidentId)) is choosing someone to execute") }
        default: waiting("Waiting…")
        }
    }

    private func voteButton(_ title: String, _ sub: String, color: Color, ink: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title).font(.system(size: 22, weight: .heavy))
                MonoLabel(sub, size: 9, color: ink.opacity(0.7))
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func pickList(_ title: String, _ players: [SecretHitlerGuestModel.Player],
                          action: @escaping (SecretHitlerGuestModel.Player) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(title)
            VStack(spacing: 8) {
                ForEach(players, id: \.id) { p in
                    Button { action(p) } label: {
                        HStack(spacing: 12) {
                            Avatar(name: p.name, size: 28)
                            Text(p.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(JamboreeTheme.faint)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 14).ubCard(radius: JamboreeRadius.row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func policyChoice(_ title: String, _ hand: [String], verb: String,
                              action: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(title)
            HStack(spacing: 14) {
                ForEach(Array(hand.enumerated()), id: \.offset) { i, pol in
                    Button { action(i) } label: {
                        VStack(spacing: 8) {
                            SHPolicyView(team: pol == "liberal" ? "L" : "F", width: 80)
                            MonoLabel(verb, size: 9,
                                      color: pol == "liberal" ? SH.liberal : SH.fascist)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).ubCard()
        }
    }

    @ViewBuilder private var chatSection: some View {
        if model.role != nil && !model.allies.isEmpty &&
            model.phase != "lobby" && model.phase != "gameOver" {
            let alive = model.players.first { $0.id == ctx.yourId }?.alive ?? true
            TeamChatView(
                title: "Fascist chat",
                subtitle: alive ? "Private — only fascists you know can read this."
                                : "You're out — chat is read-only.",
                messages: model.chat,
                myId: ctx.yourId,
                enabled: alive,
                onSend: { text in model.send(["type": "chat", "text": text]) })
        }
    }

    @ViewBuilder private var gameOver: some View {
        let liberalWin = model.winner == "liberal"
        let color = liberalWin ? SH.liberal : SH.fascist
        let reason: String = {
            switch model.reason {
            case "fiveLiberalPolicies": "Five Liberal policies enacted."
            case "sixFascistPolicies":  "Six Fascist policies enacted."
            case "hitlerElectedChancellor": "Hitler was elected Chancellor."
            case "hitlerExecuted":      "Hitler was executed."
            default: ""
            }
        }()
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Game over", color: color)
            Text(liberalWin ? "Liberals win" : "Fascists win")
                .font(.system(size: 30, weight: .heavy)).kerning(-1).foregroundStyle(color)
            if !reason.isEmpty {
                Text(reason).font(.system(size: 13)).foregroundStyle(JamboreeTheme.muted)
            }
        }
        tracks
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Full reveal")
            VStack(spacing: 8) {
                ForEach(model.players, id: \.id) { p in
                    let role = model.finalRoles[p.id] ?? ""
                    let fascistSide = role == "fascist" || role == "hitler"
                    HStack(spacing: 12) {
                        Avatar(name: p.name, host: p.isHost, size: 30)
                        Text(p.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Text(role.capitalized)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(role == "hitler" ? .white : (fascistSide ? SH.fascist : SH.liberal))
                    }
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .ubCard(radius: JamboreeRadius.row,
                            fill: fascistSide ? SH.fascist.opacity(0.10) : JamboreeTheme.surface,
                            stroke: fascistSide ? SH.fascist.opacity(0.45) : JamboreeTheme.line)
                }
            }
        }
    }

    @ViewBuilder private func waiting(_ msg: String) -> some View {
        Text("\(msg)…")
            .font(.system(size: 14)).foregroundStyle(JamboreeTheme.muted)
            .padding(.vertical, 14).padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading).ubCard(radius: JamboreeRadius.row)
    }

    private func playerName(_ id: String?) -> String {
        guard let id else { return "—" }
        return model.players.first { $0.id == id }?.name ?? id
    }
}

private enum SH {
    static let liberal = Color(hex: 0x4F9EFF)
    static let liberalInk = Color(hex: 0x02152E)
    static let fascist = Color(hex: 0xFF5A4A)
    static let fascistInk = Color(hex: 0x3A0A04)
    static let hitler = Color(hex: 0x0E0E10)
}

private func roleMeta(_ role: String) -> (name: String, team: String, blurb: String,
                                          glyph: String, color: Color, ink: Color) {
    switch role {
    case "liberal": return ("Liberal", "Liberals", "Enact 5 Liberal policies — or have Hitler executed. You don't know who anyone else is.", "★", SH.liberal, SH.liberalInk)
    case "fascist": return ("Fascist", "Fascists", "Enact 6 Fascist policies — or sneak Hitler in as Chancellor after 3.", "✖", SH.fascist, SH.fascistInk)
    case "hitler":  return ("Hitler", "Fascists", "You are also a Fascist. Stay hidden — if elected Chancellor after 3 fascist policies, you win.", "✠", SH.hitler, .white)
    default:        return (role.capitalized, "—", role, "•", SH.liberal, SH.liberalInk)
    }
}

/// Policy track board row — slots fill with the team glyph as policies enact.
private struct SHTrackView: View {
    let title: String; let filled: Int; let max: Int; let color: Color; let glyph: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MonoLabel(title, size: 10, color: color)
                Spacer()
                MonoLabel("\(filled)/\(max)", size: 9, color: JamboreeTheme.faint)
            }
            HStack(spacing: 4) {
                ForEach(0..<max, id: \.self) { i in
                    let on = i < filled
                    Text(on ? glyph : "\(i + 1)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(on ? (color == SH.liberal ? SH.liberalInk : SH.fascistInk)
                                            : Color.white.opacity(0.18))
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background(on ? color : Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .ubCard(radius: JamboreeRadius.row, fill: color.opacity(0.10), stroke: color.opacity(0.45))
    }
}

/// Face-up policy card (Liberal ★ / Fascist ✖).
private struct SHPolicyView: View {
    let team: String; let width: CGFloat
    var body: some View {
        let isLib = team == "L"
        let color = isLib ? SH.liberal : SH.fascist
        let ink = isLib ? SH.liberalInk : SH.fascistInk
        VStack(spacing: 4) {
            Text(isLib ? "★" : "✖").font(.system(size: width * 0.4, weight: .heavy)).foregroundStyle(ink)
            MonoLabel(isLib ? "Liberal" : "Fascist", size: Swift.max(8, width * 0.13), color: ink.opacity(0.7))
        }
        .frame(width: width, height: width * 1.4)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.black.opacity(0.3), lineWidth: 1))
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
    @Published var chat: [TeamChatMessage] = []
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
        case "chat":
            let text = m["text"] as? String ?? ""
            if !text.isEmpty {
                chat.append(TeamChatMessage(id: UUID().uuidString,
                    fromId: m["fromId"] as? String ?? "",
                    fromName: m["fromName"] as? String ?? "", text: text))
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
