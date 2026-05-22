import Foundation

enum Disc: String { case empty, red, yellow
    var opponent: Disc { switch self { case .red: .yellow; case .yellow: .red; case .empty: .empty } }
    var symbol: String { switch self { case .empty: ""; case .red: "R"; case .yellow: "Y" } }
}

enum ConnectFourDifficulty: CaseIterable { case easy, medium, hard
    /// Negamax search depth handed to `ConnectFourAI`.
    func searchDepth() -> Int { switch self { case .easy: 2; case .medium: 5; case .hard: 7 } }
    var label: String { switch self { case .easy: "Easy"; case .medium: "Medium"; case .hard: "Hard" } }
}

/// Host-configurable knobs. Defaults reproduce the classic 7x6 connect-4 game.
struct ConnectFourOptions: Equatable {
    var cols: Int = 7
    var rows: Int = 6
    var connectN: Int = 4
    var difficulty: ConnectFourDifficulty = .medium

    func normalized() -> ConnectFourOptions {
        let c = min(max(cols, 5), 10)
        let r = min(max(rows, 4), 10)
        let n = min(max(connectN, 3), min(c, r))
        return ConnectFourOptions(cols: c, rows: r, connectN: n, difficulty: difficulty)
    }
}

struct ConnectFourModel {
    let cols: Int
    let rows: Int
    let connectN: Int
    /// Column-major: board[col][row], row 0 = bottom.
    var board: [[Disc]]
    var current: Disc = .red

    init(cols: Int = 7, rows: Int = 6, connectN: Int = 4) {
        self.cols = cols
        self.rows = rows
        self.connectN = connectN
        self.board = Array(repeating: Array(repeating: .empty, count: rows), count: cols)
    }

    func at(_ col: Int, _ row: Int) -> Disc { board[col][row] }
    func isLegal(_ col: Int) -> Bool {
        col >= 0 && col < cols && board[col][rows - 1] == .empty
    }
    func legalMoves() -> [Int] { (0..<cols).filter { isLegal($0) } }

    /// Returns the row the disc landed on, or -1 if illegal.
    @discardableResult
    mutating func apply(_ col: Int) -> Int {
        guard isLegal(col), !isOver else { return -1 }
        for r in 0..<rows {
            if board[col][r] == .empty {
                board[col][r] = current
                current = current.opponent
                return r
            }
        }
        return -1
    }

    var winner: Disc? {
        for c in 0..<cols {
            for r in 0..<rows {
                let d = board[c][r]
                if d == .empty { continue }
                for (dc, dr) in [(1, 0), (0, 1), (1, 1), (1, -1)] {
                    if runOf(c, r, dc, dr, d) >= connectN { return d }
                }
            }
        }
        return nil
    }
    private func runOf(_ cStart: Int, _ rStart: Int, _ dc: Int, _ dr: Int, _ d: Disc) -> Int {
        var c = cStart, r = rStart, count = 0
        while c >= 0 && c < cols && r >= 0 && r < rows && board[c][r] == d {
            count += 1; c += dc; r += dr
        }
        return count
    }
    var isDraw: Bool { winner == nil && (0..<cols).allSatisfy { !isLegal($0) } }
    var isOver: Bool { winner != nil || isDraw }

    mutating func reset() {
        board = Array(repeating: Array(repeating: .empty, count: rows), count: cols)
        current = .red
    }
}
