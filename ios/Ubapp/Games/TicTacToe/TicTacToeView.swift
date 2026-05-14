import SwiftUI

/// Single-device demo: you're X, the AI is O (perfect-play minimax — best
/// result against it is a draw).
struct TicTacToeView: View {
    @State private var model = TicTacToeModel()
    @State private var aiThinking = false

    var body: some View {
        VStack(spacing: 16) {
            Text(statusText).font(.headline)
            ForEach(0..<3) { row in
                HStack(spacing: 8) {
                    ForEach(0..<3) { col in
                        let idx = row * 3 + col
                        Button {
                            tap(idx)
                        } label: {
                            Text(model.board[idx].symbol)
                                .font(.system(size: 48, weight: .bold))
                                .frame(width: 80, height: 80)
                                .background(.quaternary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.board[idx] != .empty || model.isOver || aiThinking)
                    }
                }
            }
            Button("Reset") { model.reset() }
        }
        .padding()
        .navigationTitle("Tic-Tac-Toe")
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
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = model
            let move = Minimax.bestMove(snapshot, ai: .o)
            DispatchQueue.main.async {
                if let m = move { model.apply(m) }
                aiThinking = false
            }
        }
    }
}
