import SwiftUI

struct ConnectFourView: View {
    @State private var model = ConnectFourModel()
    @State private var thinking = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            VStack(spacing: 16) {
                Text(statusText).font(.headline)
                board
                Button("Reset") { model = ConnectFourModel() }
                    .disabled(thinking)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ubappChrome()
        .navigationTitle("Connect Four")
    }

    private var statusText: String {
        if let w = model.winner { return "\(w == .red ? "Red" : "Yellow") wins" }
        if model.isDraw { return "Draw" }
        return "\(model.current == .red ? "Red" : "Yellow") to play"
    }

    private var board: some View {
        VStack(spacing: 4) {
            ForEach((0..<kRows).reversed(), id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<kCols, id: \.self) { c in
                        Button {
                            playColumn(c)
                        } label: {
                            Circle()
                                .fill(color(for: model.at(c, r)))
                                .frame(width: 40, height: 40)
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

    private func color(for d: Disc) -> Color {
        switch d { case .red: .red; case .yellow: .yellow; case .empty: .gray.opacity(0.3) }
    }

    private func playColumn(_ c: Int) {
        guard model.current == .red, model.isLegal(c), !model.isOver else { return }
        model.apply(c)
        if model.isOver { return }
        thinking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let move = ConnectFourAI.bestMove(model, ai: .yellow, depth: 5)
            DispatchQueue.main.async {
                if let m = move { model.apply(m) }
                thinking = false
            }
        }
    }
}

#Preview { ConnectFourView() }
