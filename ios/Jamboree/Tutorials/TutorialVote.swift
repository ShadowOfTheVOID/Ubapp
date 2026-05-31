import Foundation

/// Pure majority-wins yes/no vote used to decide whether a game's pre-game
/// tutorial should be shown. Engines and servers wrap this; it has no I/O.
final class TutorialVote {
    private(set) var isOpen = false
    private var votes: [String: Bool] = [:]
    private(set) var result: Bool?
    /// Tutorial was actually displayed to players — used to keep the vote
    /// button hidden after the tutorial has already run once.
    private(set) var tutorialShown = false
    private(set) var eligible: Set<String> = []

    var hasResult: Bool { result != nil }
    var yesCount: Int { votes.values.filter { $0 }.count }
    var noCount: Int { votes.values.filter { !$0 }.count }
    var eligibleCount: Int { eligible.count }

    func markShown() { tutorialShown = true }
    func isEligible(_ id: String) -> Bool { eligible.contains(id) }

    /// Reset and open a fresh vote. `eligibleIds` is the snapshot of players
    /// in the lobby when the vote was called.
    func open<S: Sequence>(eligibleIds: S) where S.Element == String {
        isOpen = true
        votes.removeAll()
        result = nil
        eligible = Set(eligibleIds)
    }

    /// Returns true once every eligible voter has submitted — at which point
    /// [result] is finalized.
    @discardableResult
    func submit(voterId: String, yes: Bool) -> Bool {
        guard isOpen, eligible.contains(voterId) else { return false }
        votes[voterId] = yes
        if votes.count >= eligible.count {
            finalize()
            return true
        }
        return false
    }

    func close() {
        guard isOpen else { return }
        finalize()
    }

    /// A voter dropped out (e.g. left the lobby).
    func removeVoter(_ id: String) {
        guard isOpen else { return }
        eligible.remove(id)
        votes[id] = nil
        if eligible.isEmpty {
            isOpen = false
            votes.removeAll()
            result = nil
            return
        }
        if votes.count >= eligible.count { finalize() }
    }

    private func finalize() {
        // Strict majority — ties resolve to "no" (skip tutorial).
        result = yesCount > noCount
        isOpen = false
    }
}
