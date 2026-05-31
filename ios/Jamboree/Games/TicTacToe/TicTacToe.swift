import Foundation

enum Mark: String { case empty, x, o
    var symbol: String { switch self { case .empty: ""; case .x: "X"; case .o: "O" } }
    var opponent: Mark { switch self { case .x: .o; case .o: .x; case .empty: .empty } }
}

enum TicTacToeDifficulty: CaseIterable { case easy, medium, hard
    /// Search depth handed to `TicTacToeAI`. `.hard` reaches every leaf on a
    /// 3x3 (unbeatable); larger boards stay depth-limited so the AI stays snappy.
    func searchDepth(_ boardSize: Int) -> Int {
        switch self { case .easy: 1; case .medium: 3; case .hard: boardSize <= 3 ? 9 : 5 }
    }
    var label: String { switch self { case .easy: "Easy"; case .medium: "Medium"; case .hard: "Hard" } }
}

/// Host-configurable knobs. Defaults reproduce the classic 3x3 perfect-AI game.
struct TicTacToeOptions: Equatable {
    var boardSize: Int = 3
    /// 0 = auto: 3 in a row on a 3x3, 4 in a row on larger boards.
    var winLength: Int = 0
    var difficulty: TicTacToeDifficulty = .hard

    static let allowedSizes = [3, 4, 5]
    static func autoWinLength(_ size: Int) -> Int { size <= 3 ? 3 : 4 }

    func normalized() -> TicTacToeOptions {
        let size = Self.allowedSizes.contains(boardSize) ? boardSize : 3
        let base = winLength <= 0 ? Self.autoWinLength(size) : winLength
        let win = min(max(base, 3), size)
        return TicTacToeOptions(boardSize: size, winLength: win, difficulty: difficulty)
    }
}

struct TicTacToeModel {
    let size: Int
    let winLength: Int
    var board: [Mark]
    var current: Mark = .x

    init(size: Int = 3, winLength: Int = 3) {
        self.size = size
        self.winLength = winLength
        self.board = Array(repeating: .empty, count: size * size)
    }

    var cellCount: Int { size * size }

    var winner: Mark? {
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for r in 0..<size {
            for c in 0..<size {
                let m = board[r * size + c]
                if m == .empty { continue }
                for (dr, dc) in dirs {
                    var rr = r, cc = c, run = 0
                    while rr >= 0 && rr < size && cc >= 0 && cc < size && board[rr * size + cc] == m {
                        run += 1
                        if run >= winLength { return m }
                        rr += dr; cc += dc
                    }
                }
            }
        }
        return nil
    }
    var isDraw: Bool { winner == nil && !board.contains(.empty) }
    var isOver: Bool { winner != nil || isDraw }

    mutating func reset() {
        board = Array(repeating: .empty, count: size * size)
        current = .x
    }
    mutating func apply(_ idx: Int) {
        guard idx >= 0, idx < board.count, board[idx] == .empty, !isOver else { return }
        board[idx] = current
        current = current.opponent
    }
}

/// Depth-limited negamax with alpha-beta pruning and a window heuristic at the
/// horizon. Deterministic (no RNG): a depth that reaches every leaf plays
/// perfectly, shallower depths give a beatable opponent.
enum TicTacToeAI {
    private static let win = 100_000

    static func bestMove(_ model: TicTacToeModel, ai: Mark, depth: Int) -> Int? {
        var bestScore = Int.min / 2
        var bestIdx: Int?
        for i in emptyCells(model) {
            var copy = model; copy.apply(i)
            let s = -negamax(copy, depth: depth - 1, alpha: Int.min / 2, beta: Int.max / 2)
            if s > bestScore { bestScore = s; bestIdx = i }
        }
        return bestIdx
    }

    /// Centre-biased ordering sharpens alpha-beta pruning.
    private static func emptyCells(_ m: TicTacToeModel) -> [Int] {
        let mid = Double(m.size - 1) / 2.0
        func dist(_ idx: Int) -> Double {
            let r = Double(idx / m.size), c = Double(idx % m.size)
            return abs(r - mid) + abs(c - mid)
        }
        return (0..<m.cellCount).filter { m.board[$0] == .empty }.sorted { dist($0) < dist($1) }
    }

    private static func negamax(_ m: TicTacToeModel, depth: Int, alpha alphaIn: Int, beta: Int) -> Int {
        if m.winner != nil { return -(win - depth) }
        if m.isDraw { return 0 }
        if depth == 0 { return heuristic(m, ai: m.current) }
        var alpha = alphaIn
        var best = Int.min / 2
        for i in emptyCells(m) {
            var copy = m; copy.apply(i)
            let s = -negamax(copy, depth: depth - 1, alpha: -beta, beta: -alpha)
            if s > best { best = s }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
        }
        return best
    }

    private static func heuristic(_ m: TicTacToeModel, ai: Mark) -> Int {
        let k = m.winLength
        var score = 0
        let dirs = [(0, 1), (1, 0), (1, 1), (1, -1)]
        for r in 0..<m.size {
            for c in 0..<m.size {
                for (dr, dc) in dirs {
                    let endR = r + (k - 1) * dr, endC = c + (k - 1) * dc
                    if endR < 0 || endR >= m.size || endC < 0 || endC >= m.size { continue }
                    var mine = 0, theirs = 0
                    for i in 0..<k {
                        let cell = m.board[(r + i * dr) * m.size + (c + i * dc)]
                        if cell == ai { mine += 1 } else if cell == ai.opponent { theirs += 1 }
                    }
                    if mine > 0 && theirs > 0 { continue }
                    if mine > 0 { score += mine * mine } else if theirs > 0 { score -= theirs * theirs }
                }
            }
        }
        return score
    }
}
