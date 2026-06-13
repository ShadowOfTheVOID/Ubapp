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
/// A legible ruling. The detector no longer hides behind a bare `Bool`: it
/// reports *which* prior statement was the closest clash, the NLI class label,
/// and a 0…1 confidence, so every client can show the player exactly why the
/// loophole stood (or didn't) instead of an opaque verdict.
struct ContradictionVerdict {
    /// True when the rebuttal contradicts a prior statement — the loophole stands.
    let contradicts: Bool
    /// Index into `priorStatements` of the most-contradicted line, or -1 if none.
    let priorIndex: Int
    /// NLI class for that line: "contradiction", "entailment", or "neutral".
    let label: String
    /// Confidence in `label`, 0…1.
    let confidence: Double

    static let none = ContradictionVerdict(contradicts: false, priorIndex: -1,
                                           label: "neutral", confidence: 0)
}

protocol ContradictionDetector {
    /// - Parameters:
    ///   - priorStatements: the statements the rebuttal may clash with
    ///     (the round's denials plus the challenger's claim — never the
    ///     request itself), oldest first.
    ///   - rebuttal: the bureaucrat's new statement.
    /// - Returns: a verdict naming the closest clashing line, its NLI label and
    ///   confidence. `contradicts == true` means the loophole stands.
    func judge(priorStatements: [String], rebuttal: String) -> ContradictionVerdict
}

extension ContradictionDetector {
    /// Convenience for callers (and tests) that only need the boolean.
    func contradicts(priorStatements: [String], rebuttal: String) -> Bool {
        judge(priorStatements: priorStatements, rebuttal: rebuttal).contradicts
    }
}

/// Offline, dependency-free contradiction check. Looks for the same content
/// word (typically a form name or subject) asserted with opposite polarity
/// across two statements. Mirrors the Kotlin `KeywordContradictionDetector`.
struct KeywordContradictionDetector: ContradictionDetector {

    func judge(priorStatements: [String], rebuttal: String) -> ContradictionVerdict {
        let rebuttalNeg = isNegative(rebuttal)
        let rebuttalKeys = contentKeys(rebuttal)
        if rebuttalKeys.isEmpty { return .none }
        for (i, prior) in priorStatements.enumerated() {
            let shared = contentKeys(prior).intersection(rebuttalKeys)
            if shared.isEmpty { continue }
            if isNegative(prior) != rebuttalNeg {
                // A hard polarity flip on a shared subject: report it as a
                // confident contradiction against that exact line.
                return ContradictionVerdict(contradicts: true, priorIndex: i,
                                            label: "contradiction", confidence: 1)
            }
        }
        return .none
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
