import SwiftUI

/// Placeholder views wired to their pure engines but without the full UI.
/// TODO: port each game's screen.dart to a dedicated SwiftUI file under its
/// Games/<Name>/ folder. These exist to keep MainMenuView compiling while
/// the engines (which carry the real game logic) are already production-ready.

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
        // Pure function — fast enough to run inline on tic-tac-toe.
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

struct SocialView: View {
    var body: some View { TODOView(title: "Social",
        note: "Empty placeholder in the Flutter app too. Reserved for future cross-game lobby.") }
}

private struct TODOView: View {
    let title: String
    let note: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(note).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32)
        .navigationTitle(title)
    }
}
