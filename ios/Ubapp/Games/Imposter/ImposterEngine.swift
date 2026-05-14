import Foundation

enum ImposterPhase { case lobby, playing, voting, result, gameOver }
enum ImposterWinner { case town, imposter }

final class ImposterPlayer {
    let id: String, name: String, isHost: Bool
    var isImposter = false
    init(id: String, name: String, isHost: Bool) { self.id = id; self.name = name; self.isHost = isHost }
}

final class ImposterEngine {
    private var rng: any RandomNumberGenerator
    private(set) var players: [String: ImposterPlayer] = [:]
    var phase: ImposterPhase = .lobby

    var category = ""
    var secretWord = ""
    var imposterId: String?

    var votes: [String: String?] = [:]
    var mostVotedId: String?
    var imposterCaught: Bool?
    var winner: ImposterWinner?

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) { self.rng = rng }

    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> ImposterPlayer {
        let p = ImposterPlayer(id: id, name: name, isHost: isHost)
        players[id] = p
        return p
    }
    func removePlayer(_ id: String) { if phase == .lobby { players[id] = nil } }
    var canStart: Bool { phase == .lobby && players.count >= 3 }
    var availableCategories: [String] { Array(ImposterWords.categories.keys) }

    func start(categoryName: String? = nil) {
        guard canStart else { return }
        let cats = Array(ImposterWords.categories.keys)
        category = (categoryName.flatMap { ImposterWords.categories[$0] != nil ? $0 : nil })
            ?? cats[Int.random(in: 0..<cats.count, using: &rng)]
        let words = ImposterWords.categories[category]!
        secretWord = words[Int.random(in: 0..<words.count, using: &rng)]
        let ids = Array(players.keys)
        imposterId = ids[Int.random(in: 0..<ids.count, using: &rng)]
        for p in players.values { p.isImposter = (p.id == imposterId) }
        phase = .playing
    }

    func beginVoting() {
        guard phase == .playing else { return }
        votes.removeAll()
        phase = .voting
    }

    @discardableResult
    func submitVote(voterId: String, targetId: String?) -> Bool {
        guard phase == .voting, players[voterId] != nil else { return false }
        if let t = targetId, players[t] == nil { return false }
        votes[voterId] = targetId
        return votes.count == players.count
    }

    func resolveVotes() {
        var tally: [String: Int] = [:]
        for case let .some(v) in votes.values { tally[v, default: 0] += 1 }
        var maxCount = 0, tied: [String] = []
        for (id, c) in tally {
            if c > maxCount { maxCount = c; tied = [id] }
            else if c == maxCount { tied.append(id) }
        }
        mostVotedId = tied.count == 1 ? tied[0] : nil
        imposterCaught = mostVotedId == imposterId
        winner = (imposterCaught == true) ? .town : .imposter
        phase = .result
    }

    func reset() {
        phase = .lobby
        category = ""; secretWord = ""; imposterId = nil
        votes.removeAll(); mostVotedId = nil; imposterCaught = nil; winner = nil
        for p in players.values { p.isImposter = false }
    }
}

enum ImposterWords {
    // TODO: full word list ported from lib/games/imposter/imposter_words.dart
    static let categories: [String: [String]] = [
        "Locations": ["Beach", "Library", "Casino", "Spaceship", "Hospital"],
        "Animals": ["Lion", "Penguin", "Octopus", "Kangaroo", "Hawk"],
        "Foods": ["Sushi", "Tacos", "Lasagna", "Falafel", "Dumplings"],
    ]
}
