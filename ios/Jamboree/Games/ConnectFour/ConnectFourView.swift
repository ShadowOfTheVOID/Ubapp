import SwiftUI

struct ConnectFourView: View {
    @State private var options = ConnectFourOptions().normalized()
    @State private var model = ConnectFourModel()
    @State private var thinking = false
    @State private var showTutorial = false
    // Running tally across rematches in this sitting; resets when options change.
    @State private var series = SeriesScore()
    @State private var seriesText = ""

    private static let presets = [(6, 5), (7, 6), (8, 7)]

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Text(statusText).font(.headline)
                if !seriesText.isEmpty { Text(seriesText).font(.subheadline).foregroundStyle(.secondary) }
                optionControls
                board
                HStack(spacing: 16) {
                    Button("Reset") { newGame() }.disabled(thinking)
                    Button("How to play") { showTutorial = true }
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ubappChrome()
        .navigationTitle("Connect Four")
        .onChange(of: model.isOver) { _, over in
            if over { recordResult() }
        }
        .sheet(isPresented: $showTutorial) { TutorialSheet(tutorial: GameTutorials.connectFour) }
    }

    @ViewBuilder private var optionControls: some View {
        Picker("Board", selection: presetBinding) {
            ForEach(Array(Self.presets.indices), id: \.self) { i in
                Text("\(Self.presets[i].0)x\(Self.presets[i].1)").tag(i)
            }
        }
        .pickerStyle(.segmented)
        .disabled(thinking)

        Picker("Difficulty", selection: difficultyBinding) {
            ForEach(ConnectFourDifficulty.allCases, id: \.self) { d in Text(d.label).tag(d) }
        }
        .pickerStyle(.segmented)
        .disabled(thinking)
    }

    private var presetBinding: Binding<Int> {
        Binding(
            get: { Self.presets.firstIndex(where: { $0.0 == options.cols && $0.1 == options.rows }) ?? 1 },
            set: {
                let (c, r) = Self.presets[$0]
                options = ConnectFourOptions(cols: c, rows: r, connectN: 4, difficulty: options.difficulty).normalized()
                resetSeries()
                newGame()
            }
        )
    }
    private var difficultyBinding: Binding<ConnectFourDifficulty> {
        Binding(get: { options.difficulty }, set: { options.difficulty = $0; resetSeries() })
    }

    private func resetSeries() { series = SeriesScore(); seriesText = "" }

    private var board: some View {
        VStack(spacing: 4) {
            ForEach(Array((0..<options.rows).reversed()), id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(Array(0..<options.cols), id: \.self) { c in
                        Button {
                            playColumn(c)
                        } label: {
                            Circle()
                                .fill(color(for: model.at(c, r)))
                                .frame(width: discSize, height: discSize)
                        }
                        .buttonStyle(.plain)
                        .disabled(thinking || model.isOver || !model.isLegal(c))
                    }
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var discSize: CGFloat { options.cols <= 6 ? 44 : (options.cols == 7 ? 38 : 32) }

    private func color(for d: Disc) -> Color {
        switch d { case .red: .red; case .yellow: .yellow; case .empty: .gray.opacity(0.3) }
    }

    private func newGame() {
        model = ConnectFourModel(cols: options.cols, rows: options.rows, connectN: options.connectN)
        thinking = false
    }

    private func recordResult() {
        let outcome: String
        switch model.winner {
        case .red: outcome = "red"
        case .yellow: outcome = "yellow"
        default: outcome = "draw"
        }
        StatsStore.record(gameId: "connect_four", players: ["You", "CPU"], outcome: outcome)
        switch model.winner {
        case .red: series.record("You")
        case .yellow: series.record("CPU")
        default: series.record("Draw")
        }
        seriesText = series.banner()
    }

    private var statusText: String {
        if let w = model.winner { return "\(w == .red ? "Red" : "Yellow") wins" }
        if model.isDraw { return "Draw" }
        return "\(model.current == .red ? "Red" : "Yellow") to play"
    }

    private func playColumn(_ c: Int) {
        guard model.current == .red, model.isLegal(c), !model.isOver else { return }
        model.apply(c)
        if model.isOver { return }
        thinking = true
        let depth = options.difficulty.searchDepth()
        DispatchQueue.global(qos: .userInitiated).async {
            let move = ConnectFourAI.bestMove(model, ai: .yellow, depth: depth)
            DispatchQueue.main.async {
                if let m = move { model.apply(m) }
                thinking = false
            }
        }
    }
}

#Preview { ConnectFourView() }
