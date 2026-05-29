import Foundation

/// Decides whether a freshly typed rebuttal collapses under the policy the
/// Bureaucrat already committed to. A deliberately tiny interface — like
/// `ProximitySource` / `HostServer` — so the pure engine stays I/O-free and the
/// detector is hot-swappable:
///
///  - `KeywordContradictionDetector` is the always-available offline default.
///  - `OnnxContradictionDetector` upgrades to a bundled NLI model when its
///    assets are present, falling back to the keyword detector otherwise.
///
/// The server is the only caller. Implementations must be synchronous and
/// side-effect free. Mirrors `ContradictionDetector.kt`.
protocol ContradictionDetector {
    /// - Parameters:
    ///   - priorStatements: the binding policy log, oldest first.
    ///   - rebuttal: the bureaucrat's new statement.
    /// - Returns: true if `rebuttal` contradicts any prior statement, meaning
    ///   the loophole stands.
    func contradicts(priorStatements: [String], rebuttal: String) -> Bool
}

/// Offline, dependency-free contradiction check. Looks for the same content
/// word (typically a form name or subject) asserted with opposite polarity
/// across two statements. Mirrors the Kotlin `KeywordContradictionDetector`.
struct KeywordContradictionDetector: ContradictionDetector {

    func contradicts(priorStatements: [String], rebuttal: String) -> Bool {
        let rebuttalNeg = isNegative(rebuttal)
        let rebuttalKeys = contentKeys(rebuttal)
        if rebuttalKeys.isEmpty { return false }
        for prior in priorStatements {
            let shared = contentKeys(prior).intersection(rebuttalKeys)
            if shared.isEmpty { continue }
            if isNegative(prior) != rebuttalNeg { return true }
        }
        return false
    }

    private func isNegative(_ s: String) -> Bool {
        let lower = " \(normalize(s)) "
        return Self.negationMarkers.contains { lower.contains(" \($0) ") }
    }

    private func contentKeys(_ s: String) -> Set<String> {
        var out: Set<String> = []
        for raw in normalize(s).split(separator: " ").map(String.init) {
            if raw.isEmpty { continue }
            if Self.stopWords.contains(raw) || Self.negationMarkers.contains(raw)
                || Self.positiveMarkers.contains(raw) { continue }
            if raw.contains(where: { $0.isNumber }) { out.insert(raw); continue }
            if raw.count >= 3 { out.insert(raw) }
        }
        return out
    }

    private func normalize(_ s: String) -> String {
        String(s.lowercased().map { ($0.isLetter || $0.isNumber || $0 == " ") ? $0 : " " })
    }

    private static let negationMarkers: Set<String> = [
        "not", "no", "never", "cannot", "cant", "wont", "without",
        "discontinued", "prohibited", "forbidden", "banned", "void",
        "invalid", "denied", "ineligible", "expired", "unavailable",
    ]
    private static let positiveMarkers: Set<String> = [
        "required", "must", "mandatory", "allowed", "permitted", "valid",
        "available", "eligible", "approved", "needed", "necessary",
    ]
    private static let stopWords: Set<String> = [
        "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
        "for", "all", "any", "of", "to", "and", "or", "in", "on", "at", "by",
        "your", "you", "this", "that", "these", "those", "it", "its", "as",
        "with", "from", "has", "have", "had", "will", "would", "can", "may",
        "longer", "only", "but", "so", "which", "case", "cases",
    ]
}
