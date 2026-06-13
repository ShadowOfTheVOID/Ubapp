import SwiftUI
import Speech
import AVFoundation

/// Native guest UI for The Bureaucrat. Consumes the same JSON the browser
/// bundle does — see `bureaucrat_browser.html` for the wire protocol.
struct BureaucratGuestView: View {
    let ctx: GuestContext
    @StateObject private var model = BureaucratGuestModel()
    @State private var denialDraft = ""
    @State private var claimDraft = ""
    @State private var rebuttalDraft = ""
    @State private var speakTranscript = ""
    @State private var isRecording = false
    @State private var speechUnavailable = false
    @State private var now = Date()

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    @State private var audioEngine = AVAudioEngine()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?

    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var iAmBureaucrat: Bool { model.bureaucratId == ctx.yourId }
    private var iAmChallenger: Bool { model.challengerId == ctx.yourId }
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
                case "voting":    voting
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
        .jamboreeChrome()
    }

    // MARK: - Phases

    @ViewBuilder private var lobby: some View {
        // Header
        Text("The Bureaucrat")
            .font(.system(size: 28, weight: .heavy))
            .kerning(-0.8)
            .foregroundStyle(.white)

        TutorialGuestCard(
            state: model.tutorialState,
            content: model.tutorialContent,
            myVote: model.myTutorialVote,
            onCall: { model.send(["type": "call_tutorial_vote"]) },
            onVote: { yes in
                model.myTutorialVote = yes
                model.send(["type": "tutorial_vote", "yes": yes])
            }
        )

        // Rules card
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Rules")
            Text("First to \(model.targetScore) wins · \(model.challengeTokens) loopholes each · \(model.rebuttalSeconds)s to rebut · \(model.judging == "vote" ? "the table votes" : (model.aiAssist ? "AI judge" : "timer only"))")
                .font(.system(size: 13))
                .foregroundStyle(JamboreeTheme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(fill: JamboreeTheme.surface, stroke: JamboreeTheme.line)

        howToCard

        MonoLabel("In the room · \(model.players.count)")

        ForEach(model.players, id: \.id) { p in
            HStack(spacing: 12) {
                Avatar(name: p.name, host: p.isHost, size: 30)
                Text(p.name)
                    .font(.system(size: 15, weight: p.id == ctx.yourId ? .bold : .semibold))
                    .foregroundStyle(.white)
                if p.id == ctx.yourId {
                    MonoLabel("you", size: 9, color: JamboreeTheme.accent)
                }
                Spacer()
                if p.isHost {
                    MonoLabel("host", size: 9, color: JamboreeTheme.faint)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .ubCard(radius: JamboreeRadius.row)
        }
    }

    @ViewBuilder private var arguing: some View {
        arguingHeader
        hotSeatBanner
        taskCard
        verdictBanner
        if iAmBureaucrat { denialComposer } else { loopholePanel }
        denialLedger
        tokenEconomy
        scoreboard
    }

    @ViewBuilder private var rebuttal: some View {
        arguingHeader
        liveChallengeBanner
        claimCard
        if iAmBureaucrat { rebuttalComposer } else { spectateCard }
        denialLedger
    }

    // MARK: - Voting phase (table-vote judging)

    @ViewBuilder private var voting: some View {
        arguingHeader
        taskCard
        claimCard
        rebuttalShownCard
        voteTally
        if iAmBureaucrat || iAmChallenger { voteSpectate } else { votePanel }
        denialLedger
    }

    @ViewBuilder private var rebuttalShownCard: some View {
        if !model.rebuttalText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("The Bureaucrat's rebuttal", color: JamboreeTheme.faint)
                Text("“\(model.rebuttalText)”")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard()
        }
    }

    private var voteTally: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MonoLabel("The table decides")
                Spacer()
                MonoLabel("\(model.voteStands + model.voteDenial) / \(model.voteEligible) voted",
                          size: 9, color: JamboreeTheme.faint)
            }
            HStack(spacing: 8) {
                tallyChip(label: "Loophole", count: model.voteStands, lead: true)
                tallyChip(label: "Denial", count: model.voteDenial, lead: false)
            }
        }
    }

    private func tallyChip(label: String, count: Int, lead: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(.white)
            Spacer()
            Text("\(count)").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .ubCard(radius: JamboreeRadius.row,
                fill: lead ? JamboreeTheme.accentSoft : JamboreeTheme.surface,
                stroke: lead ? JamboreeTheme.accentLine : JamboreeTheme.line)
    }

    private var votePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel("Your verdict")
            Text("Did the loophole beat the Bureaucrat's rebuttal?")
                .font(.system(size: 13))
                .foregroundStyle(JamboreeTheme.muted)
            HStack(spacing: 8) {
                Button("Loophole stands") { castVote(true) }
                    .buttonStyle(UbPrimaryButtonStyle())
                    .opacity(model.myVote == false ? 0.5 : 1)
                Button("Denial stands") { castVote(false) }
                    .buttonStyle(UbSecondaryButtonStyle())
                    .opacity(model.myVote == true ? 0.5 : 1)
            }
            if model.myVote != nil {
                Text("Vote in — waiting on the rest of the table.")
                    .font(.system(size: 13))
                    .foregroundStyle(JamboreeTheme.faint)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
    }

    private var voteSpectate: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("To the vote")
            Text(iAmBureaucrat
                 ? "The table is ruling on your rebuttal. You can't vote on your own defence."
                 : "The table is ruling on your loophole. You can't vote on your own challenge.")
                .font(.system(size: 14))
                .foregroundStyle(.white)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
    }

    private func castVote(_ stands: Bool) {
        model.myVote = stands
        model.send(["type": "cast_vote", "stands": stands])
    }

    /// The legible AI ruling — shown after a defense and on the round-over
    /// screen so players can see exactly what the judge decided.
    @ViewBuilder private var verdictBanner: some View {
        if let v = model.verdict {
            let cited = (v.lineIndex >= 0 && v.lineIndex < model.policyLog.count) ? model.policyLog[v.lineIndex].text : nil
            let pct = v.confidence > 0 ? "  ·  \(Int((v.confidence * 100).rounded()))%" : ""
            let head = (v.contradicts ? "AI judge · loophole stands — contradiction" : "AI judge · rebuttal holds — \(v.label)") + pct
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel(head, size: 9, color: v.contradicts ? Color(hex: 0xFF6B6B) : Color(hex: 0x3DDC84))
                if let cited {
                    Text("\(v.contradicts ? "Clashes with" : "Closest line"): “\(cited)”")
                        .font(.system(size: 13))
                        .foregroundStyle(JamboreeTheme.muted)
                        .lineLimit(3)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard(radius: JamboreeRadius.row,
                    fill: v.contradicts ? Color(hex: 0xF85149).opacity(0.10) : Color(hex: 0x2EA043).opacity(0.10),
                    stroke: v.contradicts ? Color(hex: 0xF85149).opacity(0.5) : Color(hex: 0x2EA043).opacity(0.5))
        }
    }

    /// The challenger's loophole claim, shown during the rebuttal window.
    @ViewBuilder private var claimCard: some View {
        if !model.challengerClaim.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("\(model.challengerName.isEmpty ? "A citizen" : model.challengerName)'s loophole claim", color: JamboreeTheme.accent)
                Text("“\(model.challengerClaim)”")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard(radius: JamboreeRadius.panel, fill: JamboreeTheme.accentSoft, stroke: JamboreeTheme.accentLine)
        }
    }

    @ViewBuilder private var roundOver: some View {
        MonoLabel("End of Round \(model.roundNumber)", color: JamboreeTheme.accent)

        // Seat-rotates banner
        HStack(spacing: 12) {
            BureaucratStamp("NEXT", rotate: -6)
            VStack(alignment: .leading, spacing: 4) {
                if let next = model.nextBureaucratName, !next.isEmpty {
                    Text("\(next) takes the desk next round.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                } else {
                    Text(roundOverText)
                        .font(.system(size: 14))
                        .foregroundStyle(.white)
                }
                if let next = model.nextBureaucratName, !next.isEmpty {
                    Text(roundOverText)
                        .font(.system(size: 13))
                        .foregroundStyle(JamboreeTheme.muted)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(radius: 16, fill: JamboreeTheme.accentSoft, stroke: JamboreeTheme.accentLine)

        verdictBanner

        standingsScoreboard

        infoBanner("Waiting for host to start next round…")
    }

    @ViewBuilder private var gameOver: some View {
        ZStack(alignment: .top) {
            RadialGradient(
                gradient: Gradient(colors: [JamboreeTheme.accent.opacity(0.16), .clear]),
                center: .top,
                startRadius: 0,
                endRadius: 200
            )
            .frame(height: 200)
            .allowsHitTesting(false)

            VStack(alignment: .center, spacing: 16) {
                Spacer().frame(height: 24)
                BureaucratStamp(
                    model.winnerName.isEmpty ? "WINNER" : model.winnerName.uppercased(),
                    color: Color(hex: 0x3DDC84),
                    rotate: -6
                )
                Text(model.winnerName.isEmpty ? "Someone" : model.winnerName)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Text("Wins!")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x3DDC84))
                Text("First past \(model.targetScore) points.")
                    .font(.system(size: 14))
                    .foregroundStyle(JamboreeTheme.muted)
                Spacer().frame(height: 8)
            }
            .frame(maxWidth: .infinity)
        }

        standingsScoreboard
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("How to play")
            ForEach(Array(Self.howToSteps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(JamboreeTheme.accent))
                    Text(step)
                        .font(.system(size: 13))
                        .foregroundStyle(JamboreeTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(fill: JamboreeTheme.surface, stroke: JamboreeTheme.line)
    }

    private static let howToSteps = [
        "One Bureaucrat must deny an absurd request; everyone else is a Citizen. The role rotates each round.",
        "The Bureaucrat types denials — each becomes binding policy on every screen.",
        "A Citizen spends a token to call a loophole, stating the claim they're exploiting.",
        "The Bureaucrat must rebut before the timer. Then the verdict — an AI judge or a table vote, the host's pick — decides: beat the rebuttal and the loophole wins.",
    ]

    // MARK: - Arguing sub-views

    private var arguingHeader: some View {
        HStack {
            MonoLabel("The Bureaucrat · Round \(model.roundNumber)", size: 10, color: JamboreeTheme.accent)
            Spacer()
        }
    }

    private var hotSeatBanner: some View {
        HStack(spacing: 14) {
            Avatar(name: model.bureaucratName.isEmpty ? "?" : model.bureaucratName, host: true, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                MonoLabel("In the hot seat", size: 9, color: JamboreeTheme.accent)
                Text("\(model.bureaucratName.isEmpty ? "Unknown" : model.bureaucratName) is the Bureaucrat")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(model.policyLog.filter { $0.kind == "denial" }.count)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(JamboreeTheme.faint)
                MonoLabel("rulings", size: 8, color: JamboreeTheme.faint)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(fill: JamboreeTheme.surface, stroke: JamboreeTheme.accentLine)
    }

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("The task before the office", color: JamboreeTheme.accent)
            Text(model.task)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(.white)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(radius: JamboreeRadius.panel, fill: JamboreeTheme.accentSoft, stroke: JamboreeTheme.accentLine)
    }

    private var denialComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Issue a ruling")
            Text("Every denial becomes binding policy. Be specific — but specifics can be turned against you.")
                .font(.system(size: 13))
                .foregroundStyle(JamboreeTheme.muted)
            TextField("e.g. Form 7B is required for all exemptions.", text: $denialDraft, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.black)
            Button("Stamp and record") {
                let t = denialDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    model.send(["type": "denial", "text": t])
                    denialDraft = ""
                }
            }
            .buttonStyle(UbPrimaryButtonStyle())
            .disabled(denialDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
    }

    private var loopholePanel: some View {
        let left = model.tokens[ctx.yourId] ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            TokenDots(filled: left, total: model.challengeTokens)
            MonoLabel("Challenge tokens · \(left) left")
            Text("Caught the Bureaucrat boxed in by their own rules? State the loophole you're exploiting, then call it — they must rebut before the clock runs out, and \(model.judging == "vote" ? "the table votes on whether your loophole wins" : "the AI judge checks their answer against your claim").")
                .font(.system(size: 13))
                .foregroundStyle(JamboreeTheme.muted)
            TextField("e.g. A goldfish is alive in law, so it qualifies as a co-signer.", text: $claimDraft, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.black)
                .disabled(left <= 0)
            Button("Call loophole") {
                let c = claimDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !c.isEmpty {
                    model.send(["type": "call_loophole", "claim": c])
                    claimDraft = ""
                }
            }
            .buttonStyle(UbPrimaryButtonStyle())
            .disabled(left <= 0 || claimDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
    }

    @ViewBuilder private var denialLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MonoLabel("Denial ledger · this round")
                Spacer()
                MonoLabel("Every word is on record", size: 8, color: JamboreeTheme.faint)
            }
            // The request is shown in the task card already; the ledger holds the
            // denial/loophole back-and-forth, numbered for readability.
            let entries = Array(model.policyLog.enumerated()).filter { $0.element.kind != "request" }
            if entries.isEmpty {
                Text("No policy on record yet. The Bureaucrat has said nothing binding… for now.")
                    .font(.system(size: 13))
                    .foregroundStyle(JamboreeTheme.muted)
            } else {
                let clashIndex = (model.verdict?.contradicts == true) ? (model.verdict?.lineIndex ?? -1) : -1
                ForEach(Array(entries.enumerated()), id: \.offset) { display in
                    let e = display.element.element
                    LedgerRow(
                        number: display.offset + 1,
                        reason: e.text,
                        verdict: ledgerVerdict(e.kind),
                        isCited: e.kind == "rebuttal" || e.kind == "claim",
                        isClash: display.element.offset == clashIndex
                    )
                }
            }
        }
    }

    @ViewBuilder private var tokenEconomy: some View {
        if !model.tokens.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Challenge tokens left")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(model.players, id: \.id) { p in
                            let left = model.tokens[p.id] ?? 0
                            VStack(spacing: 6) {
                                Avatar(name: p.name, host: p.isHost, size: 26)
                                Text(p.name)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                TokenDots(filled: left, total: model.challengeTokens)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .ubCard(radius: JamboreeRadius.card)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Rebuttal sub-views

    private var liveChallengeBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                TimerRing(seconds: secondsLeft, totalSeconds: model.rebuttalSeconds)
                VStack(alignment: .leading, spacing: 5) {
                    MonoLabel("Challenge · Rebuttal window", size: 9, color: JamboreeTheme.accent)
                    Text("\(model.challengerName.isEmpty ? "A challenger" : model.challengerName) challenges the ruling")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    if let latest = model.policyLog.last(where: { $0.kind == "denial" }) {
                        Text("\"\(latest.text)\"")
                            .font(.system(size: 12))
                            .foregroundStyle(JamboreeTheme.muted)
                            .lineLimit(2)
                    }
                }
            }
            if let latest = model.policyLog.last(where: { $0.kind == "denial" }) {
                VStack(alignment: .leading, spacing: 4) {
                    MonoLabel("Contested ruling", size: 9, color: JamboreeTheme.faint)
                    Text(latest.text)
                        .font(.system(size: 13))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ubCard(radius: JamboreeRadius.row, fill: JamboreeTheme.surface, stroke: JamboreeTheme.line)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: 0xFF2E88).opacity(0.20),
                    Color(hex: 0xFF2E88).opacity(0.05),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(JamboreeTheme.accentLine, lineWidth: 1)
        )
    }

    @ViewBuilder private var rebuttalComposer: some View {
        if model.rebuttalMode == "speak" {
            rebuttalComposerSpeak
        } else {
            rebuttalComposerType
        }
    }

    private var rebuttalComposerType: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Rebuttal demanded")
            Text("\(model.challengerName.isEmpty ? "A challenger" : model.challengerName) called a loophole. Defend your policy before the clock runs out.")
                .font(.system(size: 14))
                .foregroundStyle(.white)
            TextField("Your rebuttal…", text: $rebuttalDraft, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(.black)
            detectorRow
            Button("Submit rebuttal") {
                let t = rebuttalDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    model.send(["type": "rebuttal", "text": t])
                    rebuttalDraft = ""
                }
            }
            .buttonStyle(UbPrimaryButtonStyle())
            .disabled(rebuttalDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
    }

    @ViewBuilder private var rebuttalComposerSpeak: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel("Rebuttal demanded")
            Text("\(model.challengerName.isEmpty ? "A challenger" : model.challengerName) called a loophole. Defend your policy before the clock runs out.")
                .font(.system(size: 14))
                .foregroundStyle(.white)
            if speechUnavailable {
                Text("Voice not supported — type instead.")
                    .font(.system(size: 13))
                    .foregroundStyle(JamboreeTheme.muted)
                TextField("Your rebuttal…", text: $rebuttalDraft, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.black)
            } else {
                Button(isRecording ? "⏹ Stop" : "🎙 Tap to speak") {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
                .buttonStyle(UbPrimaryButtonStyle())
                if !speakTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        MonoLabel("Transcript", size: 9, color: JamboreeTheme.faint)
                        Text(speakTranscript)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .ubCard(radius: JamboreeRadius.row, fill: JamboreeTheme.surfaceHi, stroke: JamboreeTheme.line)
                }
            }
            detectorRow
            Button("Submit rebuttal") {
                let t = (speechUnavailable ? rebuttalDraft : speakTranscript)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    if isRecording { stopRecording() }
                    model.send(["type": "rebuttal", "text": t])
                    speakTranscript = ""
                    rebuttalDraft = ""
                }
            }
            .buttonStyle(UbPrimaryButtonStyle())
            .disabled({
                let t = speechUnavailable ? rebuttalDraft : speakTranscript
                return t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
        .onAppear {
            speakTranscript = ""
            isRecording = false
            // Check authorisation eagerly so the button is responsive.
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async {
                    speechUnavailable = (status != .authorized || speechRecognizer?.isAvailable != true)
                }
            }
        }
        .onDisappear { if isRecording { stopRecording() } }
    }

    private var detectorRow: some View {
        let voteMode = model.judging == "vote"
        let lit = voteMode || model.aiAssist
        let text = voteMode ? "The table will vote on your rebuttal"
                            : "Detector: \(model.aiAssist ? "Listening…" : "Timer only")"
        return HStack(spacing: 8) {
            Circle()
                .fill(lit ? Color(hex: 0x3DDC84) : JamboreeTheme.muted)
                .frame(width: 8, height: 8)
            MonoLabel(text, size: 9, color: lit ? Color(hex: 0x3DDC84) : JamboreeTheme.muted)
        }
    }

    private func startRecording() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            speechUnavailable = true; return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { speechUnavailable = true; return }
                do {
                    let req = SFSpeechAudioBufferRecognitionRequest()
                    req.shouldReportPartialResults = true
                    recognitionRequest = req
                    recognitionTask = recognizer.recognitionTask(with: req) { result, error in
                        if let r = result {
                            speakTranscript = r.bestTranscription.formattedString
                        }
                        if error != nil || result?.isFinal == true {
                            stopRecording()
                        }
                    }
                    let node = audioEngine.inputNode
                    let fmt = node.outputFormat(forBus: 0)
                    node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
                        req.append(buf)
                    }
                    audioEngine.prepare()
                    try audioEngine.start()
                    isRecording = true
                } catch {
                    speechUnavailable = true
                }
            }
        }
    }

    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isRecording = false
    }

    private var spectateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel("Loophole called")
            Text("\(model.challengerName.isEmpty ? "A challenger" : model.challengerName) is challenging the Bureaucrat.")
                .font(.system(size: 14))
                .foregroundStyle(.white)
            Text("If the Bureaucrat can't rebut in time, the challenger takes the round.")
                .font(.system(size: 13))
                .foregroundStyle(JamboreeTheme.faint)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard()
    }

    // MARK: - Scoreboards

    @ViewBuilder private var standingsScoreboard: some View {
        if !model.scores.isEmpty {
            let maxScore = max(model.scores.values.max() ?? 1, 1)
            let sorted = model.scores.sorted { $0.value > $1.value }
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("Standings")
                ForEach(Array(sorted.enumerated()), id: \.element.key) { rankIdx, row in
                    let pts = row.value
                    let isMe = row.key == ctx.yourId
                    HStack(spacing: 10) {
                        Text("\(rankIdx + 1)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(JamboreeTheme.faint)
                            .frame(width: 18, alignment: .trailing)
                        Avatar(name: model.nameOf(row.key), host: false, size: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(model.nameOf(row.key))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                if isMe {
                                    Text("· you")
                                        .font(.system(size: 13))
                                        .foregroundStyle(JamboreeTheme.accent)
                                }
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(JamboreeTheme.line).frame(height: 5)
                                    Capsule().fill(JamboreeTheme.accent)
                                        .frame(
                                            width: geo.size.width * CGFloat(pts) / CGFloat(maxScore),
                                            height: 5
                                        )
                                }
                            }
                            .frame(height: 5)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(pts)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                            MonoLabel("pts", size: 8, color: JamboreeTheme.faint)
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .ubCard(radius: JamboreeRadius.row,
                            fill: isMe ? JamboreeTheme.accentSoft : JamboreeTheme.surface,
                            stroke: isMe ? JamboreeTheme.accentLine : JamboreeTheme.line)
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
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(row.value)")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .ubCard(radius: JamboreeRadius.row,
                            fill: lead ? JamboreeTheme.accentSoft : JamboreeTheme.surface,
                            stroke: lead ? JamboreeTheme.accentLine : JamboreeTheme.line)
                }
            }
        }
    }

    // MARK: - Helpers

    private func ledgerVerdict(_ kind: String) -> String {
        switch kind {
        case "request":  return "REQUEST"
        case "claim":    return "LOOPHOLE"
        case "rebuttal": return "REBUTTAL"
        default:         return "DENIED"
        }
    }

    private var roundOverText: String {
        let who = model.lastChallengerName.isEmpty ? "A citizen" : model.lastChallengerName
        switch model.lastReason {
        case "timeout":       return "\(who) found the loophole — the Bureaucrat couldn't rebut in time."
        case "contradiction": return "\(who) won — the rebuttal contradicted the office's own policy."
        case "vote":          return "The table sided with \(who) — the loophole stands."
        case "survived":      return "The Bureaucrat survived the round. No loophole stuck."
        case "exhausted":     return "The citizens ran out of challenges. The Bureaucrat survives."
        default: return ""
        }
    }

    private func infoBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(JamboreeTheme.muted)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .ubCard(radius: JamboreeRadius.row)
    }
}

// MARK: - New shared atoms (file-private)

/// Rubber-stamp badge — mono bold all-caps text with a matching border,
/// rotated and slightly transparent.
private struct BureaucratStamp: View {
    let label: String
    var color: Color = JamboreeTheme.accent
    var size: CGFloat = 13
    var rotate: Double = -8.0

    init(_ label: String, color: Color = JamboreeTheme.accent, size: CGFloat = 13, rotate: Double = -8.0) {
        self.label = label
        self.color = color
        self.size = size
        self.rotate = rotate
    }

    var body: some View {
        Text(label.uppercased())
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .tracking(size * 0.18)
            .foregroundStyle(color)
            .padding(.vertical, size * 0.32)
            .padding(.horizontal, size * 0.7)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(color, lineWidth: 2)
            )
            .rotationEffect(.degrees(rotate))
            .opacity(0.92)
    }
}

/// Ledger entry row — numbered denial reason with a verdict pill.
private struct LedgerRow: View {
    let number: Int
    let reason: String
    var verdict: String = "DENIED"
    var isCited: Bool = false
    /// The exact line the AI judge flagged as the contradiction.
    var isClash: Bool = false

    private var verdictColor: Color {
        switch verdict {
        case "APPROVED": return Color(hex: 0x3DDC84)
        case "LOOPHOLE": return Color(hex: 0x3DDC84)
        case "DENIED":   return JamboreeTheme.accent
        default:         return JamboreeTheme.muted
        }
    }

    private var clashColor: Color { Color(hex: 0xF85149) }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("#\(number)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(JamboreeTheme.faint)
                .frame(width: 30, alignment: .leading)

            Text(reason)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(verdict)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(verdictColor)
                .padding(.vertical, 3)
                .padding(.horizontal, 7)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(verdictColor, lineWidth: 1)
                )
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ubCard(
            radius: 12,
            fill: isClash ? clashColor.opacity(0.12) : (isCited ? JamboreeTheme.accentSoft : Color.white.opacity(0.03)),
            stroke: isClash ? clashColor.opacity(0.6) : (isCited ? JamboreeTheme.accentLine : JamboreeTheme.line)
        )
    }
}

/// Circular countdown ring — track + progress arc + center label.
private struct TimerRing: View {
    let seconds: Int
    let totalSeconds: Int

    private var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(seconds) / Double(totalSeconds)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(JamboreeTheme.lineStrong, lineWidth: 4)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    JamboreeTheme.accent,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)

            VStack(spacing: 1) {
                Text("\(seconds)")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("SEC")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(JamboreeTheme.muted)
            }
        }
        .frame(width: 64, height: 64)
    }
}

/// Row of filled/empty dots representing token count.
private struct TokenDots: View {
    let filled: Int
    let total: Int
    var gap: CGFloat = 3

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                Circle()
                    .fill(i < filled ? JamboreeTheme.accent : Color.white.opacity(0.14))
                    .frame(width: 6, height: 6)
                    .overlay(
                        i < filled ? nil :
                            Circle().stroke(JamboreeTheme.line, lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - BureaucratGuestModel (unchanged)

@MainActor
final class BureaucratGuestModel: ObservableObject {
    struct Player: Identifiable { let id: String; let name: String; let isHost: Bool }
    struct Entry {
        let text: String
        /// "request", "denial", "claim", or "rebuttal".
        let kind: String
        let author: String?
        var isRebuttal: Bool { kind == "rebuttal" }
    }
    /// The AI judge's last ruling, for the legible verdict card.
    struct Verdict { let contradicts: Bool; let label: String; let confidence: Double; let lineIndex: Int }

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
    @Published var rebuttalMode = "type"
    @Published var judging = "nli"
    @Published var scores: [String: Int] = [:]
    @Published var tokens: [String: Int] = [:]
    @Published var policyLog: [Entry] = []
    @Published var challengerId: String?
    @Published var challengerName = ""
    @Published var challengerClaim = ""
    @Published var rebuttalText = ""
    @Published var voteStands = 0
    @Published var voteDenial = 0
    @Published var voteEligible = 0
    @Published var myVote: Bool?
    @Published var verdict: Verdict?
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
            if let rm = m["rebuttalMode"] as? String { rebuttalMode = (rm == "speak") ? "speak" : "type" }
            if let jg = m["judging"] as? String { judging = (jg == "vote") ? "vote" : "nli" }
        case "round", "policy":
            applyRound(m)
        case "rebuttal_open":
            phase = "rebuttal"
            challengerId = m["challengerId"] as? String
            challengerName = m["challengerName"] as? String ?? ""
            challengerClaim = m["claim"] as? String ?? ""
            verdict = nil
            deadlineMs = numeric(m["deadlineMs"])
            rebuttalSeconds = m["seconds"] as? Int ?? rebuttalSeconds
            if let log = m["policyLog"] { policyLog = readLog(log) }
        case "vote_state":
            let wasVoting = phase == "voting"
            phase = "voting"
            challengerId = m["challengerId"] as? String
            challengerName = m["challengerName"] as? String ?? ""
            if let bid = m["bureaucratId"] as? String { bureaucratId = bid }
            challengerClaim = m["claim"] as? String ?? ""
            rebuttalText = m["rebuttal"] as? String ?? ""
            voteStands = m["standsCount"] as? Int ?? 0
            voteDenial = m["denialCount"] as? Int ?? 0
            voteEligible = m["eligibleCount"] as? Int ?? 0
            if let log = m["policyLog"] { policyLog = readLog(log) }
            if !wasVoting { myVote = nil }
        case "round_over":
            phase = "roundOver"
            lastReason = m["reason"] as? String ?? ""
            lastChallengerName = m["challengerName"] as? String ?? ""
            if let nid = m["nextBureaucratId"] as? String { nextBureaucratName = nameOf(nid) }
            else { nextBureaucratName = nil }
            scores = readScores(m["scores"])
            targetScore = m["targetScore"] as? Int ?? targetScore
            verdict = readVerdict(m["verdict"])
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
        verdict = readVerdict(m["verdict"])
        policyLog = readLog(m["policyLog"])
        if m["type"] as? String == "round" { challengerClaim = "" }
    }

    private func readLog(_ raw: Any?) -> [Entry] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.map { Entry(text: $0["text"] as? String ?? "",
                               kind: $0["kind"] as? String ?? "denial",
                               author: $0["author"] as? String) }
    }
    private func readVerdict(_ raw: Any?) -> Verdict? {
        guard let o = raw as? [String: Any] else { return nil }
        return Verdict(contradicts: o["contradicts"] as? Bool ?? false,
                       label: o["label"] as? String ?? "neutral",
                       confidence: numeric(o["confidence"]),
                       lineIndex: o["lineIndex"] as? Int ?? -1)
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
