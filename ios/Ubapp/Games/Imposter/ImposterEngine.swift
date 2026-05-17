import Foundation

enum ImposterPhase { case lobby, playing, voting, result, gameOver }
enum ImposterWinner { case town, imposter }

/// Host-configurable knobs. Defaults reproduce the classic single-imposter
/// game so an unconfigured session plays exactly like before this struct
/// existed.
struct ImposterOptions: Equatable {
    var imposterCount: Int = 1
    /// When true, imposters see a different word drawn from the same
    /// category instead of nothing.
    var decoyWord: Bool = false
    /// When true, imposters see neither category nor word.
    var hideCategory: Bool = false
    /// When true, the secret word is drawn from the union of every
    /// category and the category banner reads "Mixed".
    var mixedPool: Bool = false
}

final class ImposterPlayer {
    let id: String, name: String, isHost: Bool
    var isImposter = false
    var decoyWord: String?
    init(id: String, name: String, isHost: Bool) { self.id = id; self.name = name; self.isHost = isHost }
}

final class ImposterEngine {
    private var rng: any RandomNumberGenerator
    private(set) var players: [String: ImposterPlayer] = [:]
    /// Insertion order of player ids, mirroring Android's linkedMapOf so the
    /// seeded imposter assignment is identical across platforms (an unordered
    /// Swift Dictionary would otherwise shuffle a hash-randomized sequence).
    private var playerOrder: [String] = []
    var phase: ImposterPhase = .lobby
    var options = ImposterOptions()

    var category = ""
    var secretWord = ""
    var imposterIds: Set<String> = []

    var votes: [String: String?] = [:]
    var mostVotedId: String?
    var imposterCaught: Bool?
    var winner: ImposterWinner?

    let tutorialVote = TutorialVote()

    init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) { self.rng = rng }

    @discardableResult
    func addPlayer(id: String, name: String, isHost: Bool = false) -> ImposterPlayer {
        let p = ImposterPlayer(id: id, name: name, isHost: isHost)
        if players[id] == nil { playerOrder.append(id) }
        players[id] = p
        return p
    }
    func removePlayer(_ id: String) {
        if phase == .lobby { players[id] = nil; playerOrder.removeAll { $0 == id } }
    }
    var canStart: Bool { phase == .lobby && players.count >= 3 }
    var availableCategories: [String] { ImposterWords.categoryNames }

    /// Max imposters the current lobby supports. At least one non-imposter
    /// must remain or there's no game.
    var maxImposterCount: Int { max(1, players.count - 1) }

    func setOptions(_ o: ImposterOptions) {
        guard phase == .lobby else { return }
        var clamped = o
        clamped.imposterCount = max(1, min(o.imposterCount, max(1, players.count - 1)))
        options = clamped
    }

    func start(categoryName: String? = nil) {
        guard canStart else { return }
        let cats = ImposterWords.categoryNames
        if options.mixedPool {
            category = "Mixed"
            let pool = ImposterWords.allWords
            secretWord = pool[Int.random(in: 0..<pool.count, using: &rng)]
        } else {
            category = (categoryName.flatMap { ImposterWords.categories[$0] != nil ? $0 : nil })
                ?? cats[Int.random(in: 0..<cats.count, using: &rng)]
            let words = ImposterWords.categories[category]!
            secretWord = words[Int.random(in: 0..<words.count, using: &rng)]
        }
        let ids = playerOrder.shuffled(using: &rng)
        let count = min(max(1, options.imposterCount), max(1, ids.count - 1))
        imposterIds = Set(ids.prefix(count))
        for p in players.values {
            p.isImposter = imposterIds.contains(p.id)
            p.decoyWord = nil
            if p.isImposter && options.decoyWord {
                let pool = options.mixedPool
                    ? ImposterWords.allWords
                    : (ImposterWords.categories[category] ?? [])
                let alternatives = pool.filter { $0 != secretWord }
                if !alternatives.isEmpty {
                    p.decoyWord = alternatives[Int.random(in: 0..<alternatives.count, using: &rng)]
                }
            }
        }
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
        imposterCaught = mostVotedId.map { imposterIds.contains($0) }
        winner = (imposterCaught == true) ? .town : .imposter
        phase = .result
    }

    func reset() {
        phase = .lobby
        category = ""; secretWord = ""; imposterIds.removeAll()
        votes.removeAll(); mostVotedId = nil; imposterCaught = nil; winner = nil
        for p in players.values { p.isImposter = false; p.decoyWord = nil }
    }
}

enum ImposterWords {
    /// Built-in word categories in a fixed order. An unordered Swift
    /// Dictionary would hash-randomize iteration, so category/word selection
    /// is driven by this list to stay deterministic and match Android's
    /// insertion-ordered map.
    static let ordered: [(name: String, words: [String])] = [
        ("Food", [
            "pizza", "sushi", "taco", "burger", "ramen", "cake", "ice cream",
            "pasta", "pancake", "sandwich", "curry", "salad", "soup", "bagel",
            "doughnut", "fries", "omelette", "lasagna", "kebab", "risotto",
        ]),
        ("Animal", [
            "dog", "cat", "elephant", "dolphin", "eagle", "snake", "panda",
            "lion", "tiger", "rabbit", "shark", "octopus", "penguin", "horse",
            "kangaroo", "sloth", "owl", "wolf", "fox", "bear",
        ]),
        ("Place", [
            "beach", "forest", "desert", "mountain", "city", "farm", "school",
            "hospital", "airport", "library", "museum", "theater", "park",
            "subway", "castle", "casino", "restaurant", "gym", "church", "bridge",
        ]),
        ("Movie", [
            "Star Wars", "Titanic", "Inception", "Avatar", "The Matrix", "Frozen",
            "Avengers", "Toy Story", "Jaws", "Up", "Coco", "Shrek", "Rocky",
            "Gladiator", "Interstellar", "Pulp Fiction", "The Godfather", "Joker",
            "La La Land", "Parasite",
        ]),
        ("Sport", [
            "soccer", "basketball", "tennis", "baseball", "hockey", "cricket",
            "golf", "rugby", "volleyball", "swimming", "cycling", "boxing",
            "fencing", "archery", "skiing", "surfing", "climbing", "judo",
            "rowing", "badminton",
        ]),
    ]

    static let categories: [String: [String]] =
        Dictionary(uniqueKeysWithValues: ordered.map { ($0.name, $0.words) })
    static var categoryNames: [String] { ordered.map { $0.name } }
    static var allWords: [String] { ordered.flatMap { $0.words } }
}
