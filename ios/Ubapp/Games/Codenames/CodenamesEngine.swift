import Foundation

enum Team: String { case red, blue
    var other: Team { self == .red ? .blue : .red }
    var name2: String { rawValue }
}
enum CardKind: String { case red, blue, neutral, assassin }
enum CodenamesPhase { case lobby, playing, gameOver }

final class CodenamesCard {
    let word: String
    let kind: CardKind
    var revealed = false
    init(word: String, kind: CardKind) { self.word = word; self.kind = kind }
}

final class CodenamesPlayer {
    let id: String, name: String, isHost: Bool
    var team: Team?
    var isSpymaster = false
    init(id: String, name: String, isHost: Bool) { self.id = id; self.name = name; self.isHost = isHost }
}

final class CodenamesEngine {
    private var rng: any RandomNumberGenerator
    private(set) var players: [String: CodenamesPlayer] = [:]
    var phase: CodenamesPhase = .lobby

    var board: [CodenamesCard] = []
    var startingTeam: Team = .red
    var currentTeam: Team = .red
    var currentClue: String?
    var currentNumber = 0
    var guessesLeftThisTurn = 0
    var winner: Team?
    var endReason: String?
    var lastEvent: String?

    let tutorialVote = TutorialVote()

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) { self.rng = rng }

    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> CodenamesPlayer {
        let p = CodenamesPlayer(id: id, name: name, isHost: isHost); players[id] = p; return p
    }
    func removePlayer(_ id: String) { if phase == .lobby { players[id] = nil } }
    func setTeam(_ id: String, _ team: Team) {
        guard phase == .lobby, let p = players[id] else { return }
        p.team = team
    }
    func setSpymaster(_ id: String, _ isSpymaster: Bool) {
        guard phase == .lobby, let p = players[id] else { return }
        if isSpymaster, let t = p.team {
            for other in players.values where other.id != id && other.team == t {
                other.isSpymaster = false
            }
        }
        p.isSpymaster = isSpymaster
    }

    var canStart: Bool {
        guard phase == .lobby, players.count >= 4 else { return false }
        let red = players.values.filter { $0.team == .red }
        let blue = players.values.filter { $0.team == .blue }
        guard red.count >= 2, blue.count >= 2 else { return false }
        return red.contains { $0.isSpymaster } && blue.contains { $0.isSpymaster }
    }

    func start() {
        guard canStart else { return }
        var pool = CodenamesWords.bank
        pool.shuffle(using: &rng)
        let words = Array(pool.prefix(25))
        startingTeam = Bool.random(using: &rng) ? .red : .blue
        currentTeam = startingTeam
        var kinds: [CardKind] = Array(repeating: .red, count: startingTeam == .red ? 9 : 8)
            + Array(repeating: .blue, count: startingTeam == .blue ? 9 : 8)
            + Array(repeating: .neutral, count: 7)
            + [.assassin]
        kinds.shuffle(using: &rng)
        board = (0..<25).map { CodenamesCard(word: words[$0], kind: kinds[$0]) }
        phase = .playing
        currentClue = nil; currentNumber = 0; guessesLeftThisTurn = 0
        winner = nil; endReason = nil
        lastEvent = "Game begins. \(currentTeam.name2.uppercased()) spymaster, give the first clue."
    }

    @discardableResult
    func submitClue(spymasterId: String, clue: String, number: Int) -> Bool {
        guard phase == .playing,
              let p = players[spymasterId], p.isSpymaster, p.team == currentTeam,
              currentClue == nil else { return false }
        let trimmed = clue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        currentClue = trimmed
        currentNumber = number
        guessesLeftThisTurn = number + 1
        lastEvent = "\(p.name) (\(currentTeam.name2)) clue: \"\(trimmed)\" \(number)"
        return true
    }

    @discardableResult
    func guess(guesserId: String, boardIndex: Int) -> CardKind? {
        guard phase == .playing,
              let p = players[guesserId], !p.isSpymaster, p.team == currentTeam,
              currentClue != nil, guessesLeftThisTurn > 0,
              (0..<25).contains(boardIndex) else { return nil }
        let card = board[boardIndex]
        guard !card.revealed else { return nil }
        card.revealed = true

        let teamKind: CardKind = currentTeam == .red ? .red : .blue
        let opponentKind: CardKind = currentTeam == .red ? .blue : .red

        if card.kind == .assassin {
            winner = currentTeam.other
            endReason = "\(currentTeam.name2.uppercased()) hit the assassin"
            phase = .gameOver
            lastEvent = "\(p.name) guessed \(card.word) — ASSASSIN. \(winner!.name2.uppercased()) wins!"
            return card.kind
        }

        lastEvent = "\(p.name) guessed \(card.word) (\(card.kind.rawValue))"
        if card.kind == teamKind {
            guessesLeftThisTurn -= 1
            if checkBoardWin() { return card.kind }
            if guessesLeftThisTurn <= 0 { endTurnInternal() }
        } else if card.kind == opponentKind {
            if checkBoardWin() { return card.kind }
            endTurnInternal()
        } else {
            if checkBoardWin() { return card.kind }
            endTurnInternal()
        }
        return card.kind
    }

    func endTurn(guesserId: String) {
        guard phase == .playing,
              let p = players[guesserId], !p.isSpymaster, p.team == currentTeam,
              currentClue != nil,
              guessesLeftThisTurn != currentNumber + 1 else { return }
        endTurnInternal()
    }

    private func endTurnInternal() {
        currentTeam = currentTeam.other
        currentClue = nil; currentNumber = 0; guessesLeftThisTurn = 0
        let prefix = (lastEvent?.isEmpty == false) ? "\(lastEvent!). " : ""
        lastEvent = "\(prefix)Turn passes to \(currentTeam.name2.uppercased())."
    }

    private func checkBoardWin() -> Bool {
        let redLeft = board.filter { !$0.revealed && $0.kind == .red }.count
        let blueLeft = board.filter { !$0.revealed && $0.kind == .blue }.count
        if redLeft == 0 {
            winner = .red; endReason = "red found all their words"; phase = .gameOver; return true
        }
        if blueLeft == 0 {
            winner = .blue; endReason = "blue found all their words"; phase = .gameOver; return true
        }
        return false
    }

    func cardsLeftFor(team: Team) -> Int {
        let kind: CardKind = team == .red ? .red : .blue
        return board.filter { !$0.revealed && $0.kind == kind }.count
    }

    func reset() {
        phase = .lobby
        board.removeAll()
        currentClue = nil; currentNumber = 0; guessesLeftThisTurn = 0
        winner = nil; endReason = nil; lastEvent = nil
    }
}

enum CodenamesWords {
    /// Family-friendly subset of the standard 400-word Codenames bank — pick 25
    /// per game.
    static let bank: [String] = [
        "AFRICA", "AGENT", "AIR", "ALIEN", "ALPS", "AMAZON", "AMBULANCE", "ANGEL",
        "ANTARCTICA", "APPLE", "ARM", "ATLANTIS", "AUSTRALIA", "AZTEC", "BACK", "BALL",
        "BAND", "BANK", "BAR", "BARK", "BAT", "BATTERY", "BEACH", "BEAR",
        "BEAT", "BED", "BEIJING", "BELL", "BELT", "BERLIN", "BERMUDA", "BERRY",
        "BILL", "BLOCK", "BOARD", "BOLT", "BOMB", "BOND", "BOOM", "BOOT",
        "BOTTLE", "BOW", "BOX", "BRIDGE", "BRUSH", "BUCK", "BUFFALO", "BUG",
        "BUGLE", "BUTTON", "CALF", "CANADA", "CAP", "CAPITAL", "CAR", "CARD",
        "CARROT", "CASINO", "CAST", "CAT", "CELL", "CENTAUR", "CENTER", "CHAIR",
        "CHANGE", "CHARGE", "CHECK", "CHEST", "CHICK", "CHINA", "CHOCOLATE", "CHURCH",
        "CIRCLE", "CLIFF", "CLOAK", "CLUB", "CODE", "COLD", "COMIC", "COMPOUND",
        "CONCERT", "CONDUCTOR", "CONTRACT", "COOK", "COPPER", "COTTON", "COURT", "COVER",
        "CRANE", "CRASH", "CROSS", "CROWN", "CYCLE", "CZECH", "DANCE", "DATE",
        "DAY", "DEATH", "DECK", "DEGREE", "DIAMOND", "DICE", "DINOSAUR", "DISEASE",
        "DOCTOR", "DOG", "DRAFT", "DRAGON", "DRESS", "DRILL", "DROP", "DUCK",
        "DWARF", "EAGLE", "EGYPT", "EMBASSY", "ENGINE", "ENGLAND", "EUROPE", "EYE",
        "FACE", "FAIR", "FALL", "FAN", "FENCE", "FIELD", "FIGHTER", "FIGURE",
        "FILE", "FILM", "FIRE", "FISH", "FLUTE", "FLY", "FOOT", "FORCE",
        "FOREST", "FORK", "FRANCE", "GAME", "GAS", "GENIUS", "GERMANY", "GHOST",
        "GIANT", "GLASS", "GLOVE", "GOLD", "GRACE", "GRASS", "GREECE", "GREEN",
        "GROUND", "HAM", "HAND", "HAWK", "HEAD", "HEART", "HELICOPTER", "HIMALAYAS",
        "HOLE", "HOLLYWOOD", "HONEY", "HOOD", "HOOK", "HORN", "HORSE", "HORSESHOE",
        "HOSPITAL", "HOTEL", "ICE", "INDIA", "IRON", "IVORY", "JACK", "JAM",
        "JET", "JUPITER", "KANGAROO", "KETCHUP", "KEY", "KID", "KING", "KIWI",
        "KNIFE", "KNIGHT", "LAB", "LADY", "LAP", "LASER", "LAWYER", "LEAD",
        "LEMON", "LEPRECHAUN", "LIFE", "LIGHT", "LIMOUSINE", "LINE", "LINK", "LION",
        "LITTER", "LOCH NESS", "LOCK", "LOG", "LONDON", "LUCK", "MAIL", "MAMMOTH",
        "MAPLE", "MARBLE", "MARCH", "MASS", "MATCH", "MERCURY", "MEXICO", "MICROSCOPE",
        "MILLIONAIRE", "MINE", "MINT", "MISSILE", "MODEL", "MOON", "MOSCOW", "MOUNT",
        "MOUSE", "MOUTH", "MUG", "NAIL",
    ]
}
