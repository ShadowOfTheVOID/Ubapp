import Foundation

/// NLI-backed contradiction detector for `cross-encoder/nli-MiniLM2-L6-H768`.
///
/// The model is a BERT cross-encoder: `[CLS] premise [SEP] hypothesis [SEP]`
/// → three logits in the order `[contradiction, entailment, neutral]`. We run
/// the rebuttal (hypothesis) against each prior policy statement (premise); if
/// any pair's arg-max is index 0 the loophole stands.
///
/// **Integration (one-time, on your machine — see CLAUDE.md):**
///  1. Add the ONNX Runtime Objective-C package to the Xcode project
///     (`onnxruntime-objc` via CocoaPods, or the equivalent SPM/xcframework).
///  2. Drop `nli_minilm.onnx` and `nli_vocab.txt` into `Resources/` (and the
///     Android `assets/`). The model file is intentionally not committed.
///
/// The ONNX call sites are gated behind `#if canImport(onnxruntime_objc)`, so
/// the app compiles and runs **today** on the keyword fallback; adding the
/// dependency flips on real inference with no other code change. Everything is
/// synchronous CPU compute — no network, fully offline.
enum OnnxContradictionDetector {
    static let modelResource = "nli_minilm"
    static let vocabResource = "nli_vocab"

    /// Builds the NLI detector if the runtime and bundled assets are present,
    /// otherwise returns nil so the caller can fall back. Never throws.
    static func tryCreate(fallback: ContradictionDetector = KeywordContradictionDetector()) -> ContradictionDetector? {
        #if canImport(onnxruntime_objc)
        return NliDetector(fallback: fallback)
        #else
        return nil
        #endif
    }
}

#if canImport(onnxruntime_objc)
import onnxruntime_objc

/// Real ONNX-Runtime implementation, compiled only when the dependency exists.
private final class NliDetector: ContradictionDetector {
    private let session: ORTSession
    private let env: ORTEnv
    private let tokenizer: WordPieceTokenizer
    private let fallback: ContradictionDetector
    private let maxLen = 128
    private let contradictionIndex = 0

    init?(fallback: ContradictionDetector) {
        self.fallback = fallback
        guard let modelPath = Bundle.main.path(forResource: OnnxContradictionDetector.modelResource, ofType: "onnx"),
              let vocabURL = Bundle.main.url(forResource: OnnxContradictionDetector.vocabResource, withExtension: "txt"),
              let vocabText = try? String(contentsOf: vocabURL, encoding: .utf8),
              let env = try? ORTEnv(loggingLevel: .warning),
              let opts = try? ORTSessionOptions(),
              let session = try? ORTSession(env: env, modelPath: modelPath, sessionOptions: opts)
        else { return nil }
        var vocab: [String: Int] = [:]
        for (i, line) in vocabText.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            vocab[line.trimmingCharacters(in: .whitespaces)] = i
        }
        self.env = env
        self.session = session
        self.tokenizer = WordPieceTokenizer(vocab: vocab)
    }

    func contradicts(priorStatements: [String], rebuttal: String) -> Bool {
        if rebuttal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        for prior in priorStatements {
            if runPair(premise: prior, hypothesis: rebuttal) { return true }
        }
        return false
    }

    private func runPair(premise: String, hypothesis: String) -> Bool {
        let enc = tokenizer.encodePair(premise: premise, hypothesis: hypothesis, maxLen: maxLen)
        do {
            let shape: [NSNumber] = [1, NSNumber(value: enc.ids.count)]
            let ids = try tensor(enc.ids, shape: shape)
            let mask = try tensor(enc.mask, shape: shape)
            let types = try tensor(enc.typeIds, shape: shape)
            let outputs = try session.run(
                withInputs: ["input_ids": ids, "attention_mask": mask, "token_type_ids": types],
                outputNames: ["logits"], runOptions: nil)
            guard let logitsValue = outputs["logits"],
                  let data = try? logitsValue.tensorData() as Data else {
                return fallback.contradicts(priorStatements: [premise], rebuttal: hypothesis)
            }
            let logits = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            return argMax(logits) == contradictionIndex
        } catch {
            return fallback.contradicts(priorStatements: [premise], rebuttal: hypothesis)
        }
    }

    private func tensor(_ values: [Int64], shape: [NSNumber]) throws -> ORTValue {
        var v = values
        let data = NSMutableData(bytes: &v, length: v.count * MemoryLayout<Int64>.stride)
        return try ORTValue(tensorData: data, elementType: .int64, shape: shape)
    }

    private func argMax(_ a: [Float]) -> Int {
        guard !a.isEmpty else { return -1 }
        var best = 0
        for i in 1..<a.count where a[i] > a[best] { best = i }
        return best
    }
}
#endif

/// Encoded sentence pair ready for the model.
struct EncodedPair {
    let ids: [Int64]
    let mask: [Int64]
    let typeIds: [Int64]
}

/// Minimal uncased BERT WordPiece tokenizer — enough to feed the cross-encoder.
/// Deliberately identical in behaviour to the Kotlin `WordPieceTokenizer`:
/// lowercase, split on whitespace + punctuation, then greedy longest-match
/// subword lookup with `##` continuations and `[UNK]` fallback.
struct WordPieceTokenizer {
    private let vocab: [String: Int]
    private let unk: Int
    private let cls: Int
    private let sep: Int

    init(vocab: [String: Int]) {
        self.vocab = vocab
        self.unk = vocab["[UNK]"] ?? 100
        self.cls = vocab["[CLS]"] ?? 101
        self.sep = vocab["[SEP]"] ?? 102
    }

    func encodePair(premise: String, hypothesis: String, maxLen: Int) -> EncodedPair {
        var ta = wordpiece(premise)
        var tb = wordpiece(hypothesis)
        let budget = maxLen - 3
        while ta.count + tb.count > budget {
            if ta.count > tb.count { ta.removeLast() } else { tb.removeLast() }
        }
        var ids: [Int64] = [Int64(cls)]
        var types: [Int64] = [0]
        for t in ta { ids.append(Int64(t)); types.append(0) }
        ids.append(Int64(sep)); types.append(0)
        for t in tb { ids.append(Int64(t)); types.append(1) }
        ids.append(Int64(sep)); types.append(1)
        let mask = [Int64](repeating: 1, count: ids.count)
        return EncodedPair(ids: ids, mask: mask, typeIds: types)
    }

    private func wordpiece(_ text: String) -> [Int] {
        var out: [Int] = []
        for token in basicTokenize(text) {
            let chars = Array(token)
            var start = 0
            var sub: [Int] = []
            var bad = false
            while start < chars.count {
                var end = chars.count
                var cur: Int?
                while start < end {
                    let piece = (start > 0 ? "##" : "") + String(chars[start..<end])
                    if let id = vocab[piece] { cur = id; break }
                    end -= 1
                }
                guard let id = cur else { bad = true; break }
                sub.append(id); start = end
            }
            if bad { out.append(unk) } else { out.append(contentsOf: sub) }
        }
        return out
    }

    /// Lowercase, then split on whitespace with punctuation as its own token.
    private func basicTokenize(_ text: String) -> [String] {
        var out: [String] = []
        var sb = ""
        func flush() { if !sb.isEmpty { out.append(sb); sb = "" } }
        for ch in text.lowercased() {
            if ch.isWhitespace { flush() }
            else if !(ch.isLetter || ch.isNumber) { flush(); out.append(String(ch)) }
            else { sb.append(ch) }
        }
        flush()
        return out
    }
}
