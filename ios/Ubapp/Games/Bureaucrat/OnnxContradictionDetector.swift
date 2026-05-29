import Foundation

/// NLI-backed contradiction detector for `cross-encoder/nli-MiniLM2-L6-H768`.
///
/// That model is MiniLM **distilled from RoBERTa**, so it uses RoBERTa's
/// byte-level BPE tokenizer (not BERT WordPiece). We read the self-contained
/// `tokenizer.json` (vocab + merges) and encode a pair as
/// `<s> premise </s></s> hypothesis </s>`. The cross-encoder emits three logits
/// in the order `[contradiction, entailment, neutral]`; we run the rebuttal
/// against each prior policy statement and treat arg-max index 0 as a
/// contradiction (loophole stands).
///
/// **Integration (one-time, on your machine — see README):**
///  1. Add the ONNX Runtime Objective-C package (`onnxruntime-objc`).
///  2. Drop `nli_minilm.onnx` (use `model_qint8_arm64.onnx` for devices) and
///     `nli_tokenizer.json` into `Resources/` (and Android `assets/`).
///
/// The ONNX call sites are gated behind `#if canImport(onnxruntime_objc)`, so
/// the app builds and runs **today** on the keyword fallback; adding the
/// dependency flips on real inference. All on-device, fully offline.
enum OnnxContradictionDetector {
    static let modelResource = "nli_minilm"
    static let tokenizerResource = "nli_tokenizer"

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

private final class NliDetector: ContradictionDetector {
    private let session: ORTSession
    private let env: ORTEnv
    private let tokenizer: BpeTokenizer
    private let usesTokenTypeIds: Bool
    private let fallback: ContradictionDetector
    private let maxLen = 256
    private let contradictionIndex = 0

    init?(fallback: ContradictionDetector) {
        self.fallback = fallback
        guard let modelPath = Bundle.main.path(forResource: OnnxContradictionDetector.modelResource, ofType: "onnx"),
              let tokURL = Bundle.main.url(forResource: OnnxContradictionDetector.tokenizerResource, withExtension: "json"),
              let tokData = try? Data(contentsOf: tokURL),
              let tokenizer = BpeTokenizer(tokenizerJSON: tokData),
              let env = try? ORTEnv(loggingLevel: .warning),
              let opts = try? ORTSessionOptions(),
              let session = try? ORTSession(env: env, modelPath: modelPath, sessionOptions: opts)
        else { return nil }
        self.env = env
        self.session = session
        self.tokenizer = tokenizer
        let names = (try? session.inputNames()) ?? []
        self.usesTokenTypeIds = names.contains("token_type_ids")
    }

    func contradicts(priorStatements: [String], rebuttal: String) -> Bool {
        if rebuttal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        for prior in priorStatements where runPair(premise: prior, hypothesis: rebuttal) { return true }
        return false
    }

    private func runPair(premise: String, hypothesis: String) -> Bool {
        let enc = tokenizer.encodePair(premise: premise, hypothesis: hypothesis, maxLen: maxLen)
        do {
            let shape: [NSNumber] = [1, NSNumber(value: enc.ids.count)]
            var inputs: [String: ORTValue] = [
                "input_ids": try tensor(enc.ids, shape: shape),
                "attention_mask": try tensor(enc.mask, shape: shape),
            ]
            if usesTokenTypeIds { inputs["token_type_ids"] = try tensor(enc.typeIds, shape: shape) }
            let outputs = try session.run(withInputs: inputs, outputNames: ["logits"], runOptions: nil)
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

/// Byte-level BPE tokenizer (GPT-2 / RoBERTa style) driven by a HuggingFace
/// `tokenizer.json`. Behaviour-identical to the Kotlin `BpeTokenizer`.
struct BpeTokenizer {
    private let vocab: [String: Int]
    private let mergeRanks: [String: Int]   // "a\u{0001}b" -> rank
    private let byteEncoder: [UInt8: Character]
    private let bos: Int
    private let eos: Int
    private let unk: Int
    private let regex: NSRegularExpression

    private static let pairSep = "\u{0001}"

    init?(tokenizerJSON data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? [String: Any],
              let rawVocab = model["vocab"] as? [String: Int] else { return nil }
        self.vocab = rawVocab

        var ranks: [String: Int] = [:]
        if let merges = model["merges"] as? [Any] {
            for (i, m) in merges.enumerated() {
                if let s = m as? String {
                    if let sp = s.firstIndex(of: " ") {
                        let a = String(s[s.startIndex..<sp]), b = String(s[s.index(after: sp)...])
                        ranks[a + Self.pairSep + b] = i
                    }
                } else if let arr = m as? [String], arr.count == 2 {
                    ranks[arr[0] + Self.pairSep + arr[1]] = i
                }
            }
        }
        self.mergeRanks = ranks
        self.byteEncoder = Self.buildByteEncoder()
        self.bos = rawVocab["<s>"] ?? 0
        self.eos = rawVocab["</s>"] ?? 2
        self.unk = rawVocab["<unk>"] ?? 3
        let pattern = "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        self.regex = re
    }

    func encodePair(premise: String, hypothesis: String, maxLen: Int) -> EncodedPair {
        var a = encode(premise)
        var b = encode(hypothesis)
        let budget = maxLen - 4
        while a.count + b.count > budget && (!a.isEmpty || !b.isEmpty) {
            if a.count > b.count { a.removeLast() } else if !b.isEmpty { b.removeLast() } else { a.removeLast() }
        }
        var ids: [Int64] = [Int64(bos)]
        ids.append(contentsOf: a.map(Int64.init))
        ids.append(Int64(eos)); ids.append(Int64(eos))
        ids.append(contentsOf: b.map(Int64.init))
        ids.append(Int64(eos))
        let mask = [Int64](repeating: 1, count: ids.count)
        let types = [Int64](repeating: 0, count: ids.count)
        return EncodedPair(ids: ids, mask: mask, typeIds: types)
    }

    private func encode(_ text: String) -> [Int] {
        var out: [Int] = []
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            let piece = ns.substring(with: m.range)
            var mapped = ""
            for byte in Array(piece.utf8) {
                if let c = byteEncoder[byte] { mapped.append(c) }
            }
            for tok in bpe(mapped) { out.append(vocab[tok] ?? unk) }
        }
        return out
    }

    private func bpe(_ token: String) -> [String] {
        if token.isEmpty { return [] }
        var word = token.map { String($0) }
        while word.count > 1 {
            var bestRank = Int.max
            var bestIdx = -1
            for i in 0..<(word.count - 1) {
                if let rank = mergeRanks[word[i] + Self.pairSep + word[i + 1]], rank < bestRank {
                    bestRank = rank; bestIdx = i
                }
            }
            if bestIdx < 0 { break }
            let first = word[bestIdx], second = word[bestIdx + 1]
            var merged: [String] = []
            var i = 0
            while i < word.count {
                if i < word.count - 1 && word[i] == first && word[i + 1] == second {
                    merged.append(first + second); i += 2
                } else { merged.append(word[i]); i += 1 }
            }
            word = merged
        }
        return word
    }

    /// GPT-2 reversible byte ↔ unicode mapping so every byte is a printable char.
    private static func buildByteEncoder() -> [UInt8: Character] {
        var bs: [Int] = []
        bs.append(contentsOf: Int(Character("!").asciiValue!)...Int(Character("~").asciiValue!))
        bs.append(contentsOf: 0xA1...0xAC)   // ¡..¬
        bs.append(contentsOf: 0xAE...0xFF)   // ®..ÿ
        var cs = bs
        var n = 0
        for b in 0...255 where !bs.contains(b) { bs.append(b); cs.append(256 + n); n += 1 }
        var map: [UInt8: Character] = [:]
        for i in 0..<bs.count {
            if let scalar = UnicodeScalar(cs[i]) { map[UInt8(bs[i])] = Character(scalar) }
        }
        return map
    }
}
