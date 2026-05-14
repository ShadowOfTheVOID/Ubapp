import Foundation

enum Mark: String { case empty, x, o
    var symbol: String { switch self { case .empty: ""; case .x: "X"; case .o: "O" } }
    var opponent: Mark { switch self { case .x: .o; case .o: .x; case .empty: .empty } }
}

private let winningLines: [[Int]] = [
    [0,1,2], [3,4,5], [6,7,8],
    [0,3,6], [1,4,7], [2,5,8],
    [0,4,8], [2,4,6],
]

struct TicTacToeModel {
    var board: [Mark] = Array(repeating: .empty, count: 9)
    var current: Mark = .x

    var winner: Mark? {
        for line in winningLines {
            let a = board[line[0]]
            if a != .empty && a == board[line[1]] && a == board[line[2]] { return a }
        }
        return nil
    }
    var isDraw: Bool { winner == nil && !board.contains(.empty) }
    var isOver: Bool { winner != nil || isDraw }

    mutating func reset() { board = Array(repeating: .empty, count: 9); current = .x }
    mutating func apply(_ idx: Int) {
        guard board[idx] == .empty, !isOver else { return }
        board[idx] = current
        current = current.opponent
    }
}

enum Minimax {
    static func bestMove(_ model: TicTacToeModel, ai: Mark) -> Int? {
        var bestScore = Int.min, bestIdx: Int?
        for i in 0..<9 where model.board[i] == .empty {
            var copy = model; copy.apply(i)
            let s = score(copy, ai: ai, maximizing: false, depth: 0)
            if s > bestScore { bestScore = s; bestIdx = i }
        }
        return bestIdx
    }
    private static func score(_ m: TicTacToeModel, ai: Mark, maximizing: Bool, depth: Int) -> Int {
        if let w = m.winner { return w == ai ? 100 - depth : depth - 100 }
        if m.isDraw { return 0 }
        var best = maximizing ? Int.min : Int.max
        for i in 0..<9 where m.board[i] == .empty {
            var copy = m; copy.apply(i)
            let s = score(copy, ai: ai, maximizing: !maximizing, depth: depth + 1)
            best = maximizing ? max(s, best) : min(s, best)
        }
        return best
    }
}
