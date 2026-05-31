package com.example.ubapp.games.bureaucrat

/**
 * Decides whether a freshly typed rebuttal collapses under the weight of the
 * policy the Bureaucrat already committed to. Deliberately a tiny interface —
 * exactly like `ProximitySource` / `HostServer` — so the transport-free engine
 * stays pure and the *detector* is hot-swappable:
 *
 *  - [KeywordContradictionDetector] is the always-available offline default. It
 *    needs no model, runs instantly, and is deterministic (so it is unit
 *    tested directly).
 *  - [OnnxContradictionDetector] upgrades to a bundled NLI model when its
 *    assets are present, and transparently falls back to the keyword detector
 *    otherwise.
 *
 * The server is the only caller: on each rebuttal it asks the detector whether
 * the rebuttal contradicts the prior log, then feeds the boolean into
 * [BureaucratEngine.submitRebuttal]. Implementations must be synchronous and
 * side-effect free.
 */
interface ContradictionDetector {
    /**
     * @param priorStatements the binding policy log, oldest first.
     * @param rebuttal the bureaucrat's new statement.
     * @return true if [rebuttal] contradicts any prior statement (or the prior
     *         statements contradict each other in a way the rebuttal fails to
     *         resolve), meaning the loophole stands.
     */
    fun contradicts(priorStatements: List<String>, rebuttal: String): Boolean
}

/**
 * Offline, dependency-free contradiction check. Not as nuanced as an NLI
 * model, but good enough to make the game self-officiating without a network:
 * it looks for the same noun (a shared content word — typically a form name or
 * subject) asserted with opposite polarity across two statements.
 *
 * Example caught:
 *   "Form 7B is required for all exemptions."
 *   "Form 7B was discontinued and is no longer available."
 * Shared key token `7b`; one statement is positive ("required"), the other
 * negative ("discontinued", "no longer") → contradiction.
 */
class KeywordContradictionDetector : ContradictionDetector {

    override fun contradicts(priorStatements: List<String>, rebuttal: String): Boolean {
        val rebuttalNeg = isNegative(rebuttal)
        val rebuttalKeys = contentKeys(rebuttal)
        if (rebuttalKeys.isEmpty()) return false
        for (prior in priorStatements) {
            val shared = contentKeys(prior).intersect(rebuttalKeys)
            if (shared.isEmpty()) continue
            // Opposite polarity on a shared subject is the contradiction signal.
            if (isNegative(prior) != rebuttalNeg) return true
        }
        return false
    }

    private fun isNegative(s: String): Boolean {
        val lower = " ${normalize(s)} "
        return NEGATION_MARKERS.any { lower.contains(" $it ") }
    }

    /** Content words (>=3 chars, not stop/polarity words) plus form-code tokens. */
    private fun contentKeys(s: String): Set<String> {
        val out = mutableSetOf<String>()
        for (raw in normalize(s).split(' ')) {
            if (raw.isBlank()) continue
            if (raw in STOP_WORDS || raw in NEGATION_MARKERS || raw in POSITIVE_MARKERS) continue
            // Form codes like "7b", "4", "12c" are strong subject anchors.
            if (raw.any { it.isDigit() }) { out.add(raw); continue }
            if (raw.length >= 3) out.add(raw)
        }
        return out
    }

    private fun normalize(s: String): String =
        s.lowercase().map { if (it.isLetterOrDigit() || it == ' ') it else ' ' }.joinToString("")

    private companion object {
        val NEGATION_MARKERS = setOf(
            "not", "no", "never", "cannot", "cant", "wont", "without",
            "discontinued", "prohibited", "forbidden", "banned", "void",
            "invalid", "denied", "ineligible", "expired", "unavailable",
        )
        val POSITIVE_MARKERS = setOf(
            "required", "must", "mandatory", "allowed", "permitted", "valid",
            "available", "eligible", "approved", "needed", "necessary",
        )
        val STOP_WORDS = setOf(
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "for", "all", "any", "of", "to", "and", "or", "in", "on", "at", "by",
            "your", "you", "this", "that", "these", "those", "it", "its", "as",
            "with", "from", "has", "have", "had", "will", "would", "can", "may",
            "longer", "only", "but", "so", "which", "case", "cases",
        )
    }
}
