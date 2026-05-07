import GameplayKit

enum Mark: Int {
    case empty = 0, x = 1, o = 2

    var symbol: String {
        switch self {
        case .empty: return ""
        case .x: return "X"
        case .o: return "O"
        }
    }

    var opponent: Mark {
        switch self {
        case .x: return .o
        case .o: return .x
        case .empty: return .empty
        }
    }
}

final class TicTacToePlayer: NSObject, GKGameModelPlayer {
    static let x = TicTacToePlayer(mark: .x)
    static let o = TicTacToePlayer(mark: .o)
    static let all: [TicTacToePlayer] = [x, o]

    let mark: Mark
    var playerId: Int { mark.rawValue }

    init(mark: Mark) { self.mark = mark }
}

final class TicTacToeMove: NSObject, GKGameModelUpdate {
    var value: Int = 0
    let index: Int
    init(index: Int) { self.index = index }
}

final class TicTacToeModel: NSObject, GKGameModel {
    var board: [Mark]
    var current: TicTacToePlayer

    var players: [GKGameModelPlayer]? { TicTacToePlayer.all }
    var activePlayer: GKGameModelPlayer? { current }

    override init() {
        self.board = Array(repeating: .empty, count: 9)
        self.current = .x
        super.init()
    }

    func copy(with zone: NSZone? = nil) -> Any {
        let m = TicTacToeModel()
        m.setGameModel(self)
        return m
    }

    func setGameModel(_ gameModel: GKGameModel) {
        guard let other = gameModel as? TicTacToeModel else { return }
        self.board = other.board
        self.current = other.current
    }

    func gameModelUpdates(for player: GKGameModelPlayer) -> [GKGameModelUpdate]? {
        guard winner == nil else { return nil }
        var moves: [TicTacToeMove] = []
        for i in 0..<9 where board[i] == .empty {
            moves.append(TicTacToeMove(index: i))
        }
        return moves.isEmpty ? nil : moves
    }

    func apply(_ gameModelUpdate: GKGameModelUpdate) {
        guard let move = gameModelUpdate as? TicTacToeMove else { return }
        board[move.index] = current.mark
        current = current.mark == .x ? .o : .x
    }

    func score(for player: GKGameModelPlayer) -> Int {
        guard let player = player as? TicTacToePlayer else { return 0 }
        if let w = winner {
            return w.mark == player.mark ? 100 : -100
        }
        return 0
    }

    func isWin(for player: GKGameModelPlayer) -> Bool {
        guard let player = player as? TicTacToePlayer else { return false }
        return winner?.mark == player.mark
    }

    func isLoss(for player: GKGameModelPlayer) -> Bool {
        guard let player = player as? TicTacToePlayer else { return false }
        if let w = winner { return w.mark != player.mark }
        return false
    }

    var isDraw: Bool {
        winner == nil && !board.contains(.empty)
    }

    var winner: TicTacToePlayer? {
        let lines: [[Int]] = [
            [0,1,2],[3,4,5],[6,7,8],
            [0,3,6],[1,4,7],[2,5,8],
            [0,4,8],[2,4,6]
        ]
        for line in lines {
            let a = board[line[0]], b = board[line[1]], c = board[line[2]]
            if a != .empty && a == b && b == c {
                return a == .x ? .x : .o
            }
        }
        return nil
    }
}
