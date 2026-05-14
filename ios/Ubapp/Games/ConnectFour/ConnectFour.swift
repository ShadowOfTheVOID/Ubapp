import Foundation

enum Disc: String { case empty, red, yellow
    var opponent: Disc { switch self { case .red: .yellow; case .yellow: .red; case .empty: .empty } }
    var symbol: String { switch self { case .empty: ""; case .red: "R"; case .yellow: "Y" } }
}

let kCols = 7, kRows = 6

struct ConnectFourModel {
    /// Column-major: board[col][row], row 0 = bottom.
    var board: [[Disc]] = Array(repeating: Array(repeating: .empty, count: kRows), count: kCols)
    var current: Disc = .red

    func at(_ col: Int, _ row: Int) -> Disc { board[col][row] }
    func isLegal(_ col: Int) -> Bool {
        col >= 0 && col < kCols && board[col][kRows - 1] == .empty
    }
    func legalMoves() -> [Int] { (0..<kCols).filter { isLegal($0) } }

    /// Returns the row the disc landed on, or -1 if illegal.
    @discardableResult
    mutating func apply(_ col: Int) -> Int {
        guard isLegal(col), !isOver else { return -1 }
        for r in 0..<kRows {
            if board[col][r] == .empty {
                board[col][r] = current
                current = current.opponent
                return r
            }
        }
        return -1
    }

    var winner: Disc? {
        for c in 0..<kCols {
            for r in 0..<kRows {
                let d = board[c][r]
                if d == .empty { continue }
                for (dc, dr) in [(1,0),(0,1),(1,1),(1,-1)] {
                    if runOf(c, r, dc, dr, d) >= 4 { return d }
                }
            }
        }
        return nil
    }
    private func runOf(_ cStart: Int, _ rStart: Int, _ dc: Int, _ dr: Int, _ d: Disc) -> Int {
        var c = cStart, r = rStart, count = 0
        while c >= 0 && c < kCols && r >= 0 && r < kRows && board[c][r] == d {
            count += 1; c += dc; r += dr
        }
        return count
    }
    var isDraw: Bool { winner == nil && (0..<kCols).allSatisfy { !isLegal($0) } }
    var isOver: Bool { winner != nil || isDraw }

    mutating func reset() {
        board = Array(repeating: Array(repeating: .empty, count: kRows), count: kCols)
        current = .red
    }
}
