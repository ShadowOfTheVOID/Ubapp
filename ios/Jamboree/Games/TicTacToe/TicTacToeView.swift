import SwiftUI

/// Single-device game: you're X, the AI is O. Board size and AI difficulty are
/// configurable; on Hard 3x3 the AI plays perfectly (best result is a draw).
struct TicTacToeView: View {
    @State private var options = TicTacToeOptions().normalized()
    @State private var model = TicTacToeModel()
    @State private var aiThinking = false
    @State private var showTutorial = false
    // Running tally across rematches in this sitting; resets when options change.
    @State private var series = SeriesScore()
    @State private var seriesText = ""

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Text(statusText).font(.headline)
                if !seriesText.isEmpty { Text(seriesText).font(.subheadline).foregroundStyle(.secondary) }
                optionControls
                grid
                HStack(spacing: 16) {
                    Button("Reset") { newGame() }.disabled(aiThinking)
                    Button("How to play") { showTutorial = true }
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .jamboreeChrome()
        .navigationTitle("Tic-Tac-Toe")
        .onChange(of: model.isOver) { _, over in
            if over { recordResult() }
        }
        .sheet(isPresented: $showTutorial) { TutorialSheet(tutorial: GameTutorials.ticTacToe) }
    }

    @ViewBuilder private var optionControls: some View {
        Picker("Board", selection: boardBinding) {
            ForEach(TicTacToeOptions.allowedSizes, id: \.self) { s in Text("\(s)x\(s)").tag(s) }
        }
        .pickerStyle(.segmented)
        .disabled(aiThinking)

        Picker("Difficulty", selection: difficultyBinding) {
            ForEach(TicTacToeDifficulty.allCases, id: \.self) { d in Text(d.label).tag(d) }
        }
        .pickerStyle(.segmented)
        .disabled(aiThinking)
    }

    private var boardBinding: Binding<Int> {
        Binding(get: { options.boardSize },
                set: { options = TicTacToeOptions(boardSize: $0, difficulty: options.difficulty).normalized(); resetSeries(); newGame() })
    }
    private var difficultyBinding: Binding<TicTacToeDifficulty> {
        Binding(get: { options.difficulty },
                set: { options.difficulty = $0; resetSeries() })
    }

    private func resetSeries() { series = SeriesScore(); seriesText = "" }

    private var grid: some View {
        VStack(spacing: 8) {
            ForEach(Array(0..<options.boardSize), id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(Array(0..<options.boardSize), id: \.self) { col in
                        let idx = row * options.boardSize + col
                        Button {
                            tap(idx)
                        } label: {
                            Text(model.board[idx].symbol)
                                .font(.system(size: markSize, weight: .bold))
                                .frame(width: cellSize, height: cellSize)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.board[idx] != .empty || model.isOver || aiThinking)
                    }
                }
            }
        }
    }

    private var cellSize: CGFloat { switch options.boardSize { case 3: 80; case 4: 60; default: 48 } }
    private var markSize: CGFloat { switch options.boardSize { case 3: 48; case 4: 34; default: 26 } }

    private func newGame() {
        model = TicTacToeModel(size: options.boardSize, winLength: options.winLength)
        aiThinking = false
    }

    private func recordResult() {
        let outcome: String
        switch model.winner {
        case .x: outcome = "x"
        case .o: outcome = "o"
        default: outcome = "draw"
        }
        StatsStore.record(gameId: "tic_tac_toe", players: ["You", "CPU"], outcome: outcome)
        switch model.winner {
        case .x: series.record("You")
        case .o: series.record("CPU")
        default: series.record("Draw")
        }
        seriesText = series.banner()
    }

    private var statusText: String {
        if let w = model.winner { return "\(w.symbol) wins" }
        if model.isDraw { return "Draw" }
        return "\(model.current.symbol) to play"
    }

    private func tap(_ idx: Int) {
        guard model.current == .x else { return }
        model.apply(idx)
        if !model.isOver { runAI() }
    }
    private func runAI() {
        aiThinking = true
        let depth = options.difficulty.searchDepth(model.size)
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = model
            let move = TicTacToeAI.bestMove(snapshot, ai: .o, depth: depth)
            DispatchQueue.main.async {
                if let m = move { model.apply(m) }
                aiThinking = false
            }
        }
    }
}
