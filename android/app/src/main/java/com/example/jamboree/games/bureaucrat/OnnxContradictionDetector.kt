package com.example.jamboree.games.bureaucrat

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.nio.LongBuffer

/**
 * NLI-backed contradiction detector for `cross-encoder/nli-MiniLM2-L6-H768`.
 *
 * That model is MiniLM **distilled from RoBERTa**, so it uses RoBERTa's
 * byte-level BPE tokenizer (not BERT WordPiece). We read the self-contained
 * `tokenizer.json` (vocab + merges in one file) and encode a pair as
 * `<s> premise </s></s> hypothesis </s>`. The cross-encoder emits three logits
 * in the order `[contradiction, entailment, neutral]`; we run the rebuttal
 * (hypothesis) against each prior policy statement (premise) and if any pair's
 * arg-max is index 0 the loophole stands.
 *
 * Two assets must be present for this to activate (drop them into BOTH
 * `assets/` and iOS `Resources/` — see README):
 *   - `nli_minilm.onnx`     — pick `model_qint8_arm64.onnx` for phones (~83 MB)
 *   - `nli_tokenizer.json`  — the repo's tokenizer.json
 *
 * [tryCreate] returns null when either asset is missing or the runtime fails,
 * so the server falls back to [KeywordContradictionDetector]. All on-device,
 * fully offline.
 */
class OnnxContradictionDetector private constructor(
    private val env: OrtEnvironment,
    private val session: OrtSession,
    private val tokenizer: BpeTokenizer,
    private val usesTokenTypeIds: Boolean,
    private val fallback: ContradictionDetector,
) : ContradictionDetector {

    override fun contradicts(priorStatements: List<String>, rebuttal: String): Boolean {
        if (rebuttal.isBlank()) return false
        for (prior in priorStatements) {
            if (runPair(premise = prior, hypothesis = rebuttal)) return true
        }
        return false
    }

    private fun runPair(premise: String, hypothesis: String): Boolean {
        val enc = tokenizer.encodePair(premise, hypothesis, MAX_LEN)
        val shape = longArrayOf(1, enc.ids.size.toLong())
        val tensors = mutableMapOf<String, OnnxTensor>()
        return try {
            tensors["input_ids"] = OnnxTensor.createTensor(env, LongBuffer.wrap(enc.ids), shape)
            tensors["attention_mask"] = OnnxTensor.createTensor(env, LongBuffer.wrap(enc.mask), shape)
            if (usesTokenTypeIds) {
                tensors["token_type_ids"] = OnnxTensor.createTensor(env, LongBuffer.wrap(enc.typeIds), shape)
            }
            session.run(tensors).use { result ->
                @Suppress("UNCHECKED_CAST")
                val logits = (result[0].value as Array<FloatArray>)[0]
                argMax(logits) == CONTRADICTION_INDEX
            }
        } catch (t: Throwable) {
            fallback.contradicts(listOf(premise), hypothesis)
        } finally {
            tensors.values.forEach { it.close() }
        }
    }

    private fun argMax(a: FloatArray): Int {
        var best = 0
        for (i in 1 until a.size) if (a[i] > a[best]) best = i
        return best
    }

    fun close() { runCatching { session.close() } }

    companion object {
        private const val MAX_LEN = 256
        private const val CONTRADICTION_INDEX = 0
        const val MODEL_ASSET = "nli_minilm.onnx"
        const val TOKENIZER_ASSET = "nli_tokenizer.json"

        fun tryCreate(
            context: Context,
            fallback: ContradictionDetector = KeywordContradictionDetector(),
        ): OnnxContradictionDetector? = runCatching {
            val assets = context.assets
            val available = assets.list("")?.toSet() ?: emptySet()
            if (MODEL_ASSET !in available || TOKENIZER_ASSET !in available) return null
            val tokenizer = BpeTokenizer.fromJson(
                assets.open(TOKENIZER_ASSET).bufferedReader().use { it.readText() })
            val modelBytes = assets.open(MODEL_ASSET).use { it.readBytes() }
            val env = OrtEnvironment.getEnvironment()
            val session = env.createSession(modelBytes, OrtSession.SessionOptions())
            val usesTypes = session.inputNames.contains("token_type_ids")
            OnnxContradictionDetector(env, session, tokenizer, usesTypes, fallback)
        }.getOrNull()
    }
}

/** Encoded sentence pair ready for the model. */
class EncodedPair(val ids: LongArray, val mask: LongArray, val typeIds: LongArray)

/**
 * Byte-level BPE tokenizer (GPT-2 / RoBERTa style) driven by a HuggingFace
 * `tokenizer.json`. Deliberately identical in behaviour to the Swift
 * `BpeTokenizer`: byte-to-unicode mapping, GPT-2 pre-tokenization regex,
 * rank-ordered merges, then vocab lookup with `<unk>` fallback.
 */
class BpeTokenizer(
    private val vocab: Map<String, Int>,
    merges: List<String>,
    private val bos: Int,
    private val eos: Int,
    private val unk: Int,
) {
    private val byteEncoder: Map<Int, Char> = buildByteEncoder()
    private val mergeRanks: Map<Pair<String, String>, Int> = buildMergeRanks(merges)
    private val pattern = Regex(
        "'s|'t|'re|'ve|'m|'ll|'d| ?\\p{L}+| ?\\p{N}+| ?[^\\s\\p{L}\\p{N}]+|\\s+(?!\\S)|\\s+")

    fun encodePair(premise: String, hypothesis: String, maxLen: Int): EncodedPair {
        var a = encode(premise)
        var b = encode(hypothesis)
        val budget = maxLen - 4   // <s> a </s></s> b </s>
        while (a.size + b.size > budget && (a.isNotEmpty() || b.isNotEmpty())) {
            if (a.size > b.size) a = a.dropLast(1) else b = b.dropLast(1)
        }
        val ids = ArrayList<Long>()
        ids.add(bos.toLong())
        a.forEach { ids.add(it.toLong()) }
        ids.add(eos.toLong()); ids.add(eos.toLong())
        b.forEach { ids.add(it.toLong()) }
        ids.add(eos.toLong())
        val arr = ids.toLongArray()
        return EncodedPair(arr, LongArray(arr.size) { 1L }, LongArray(arr.size) { 0L })
    }

    private fun encode(text: String): List<Int> {
        val out = ArrayList<Int>()
        for (m in pattern.findAll(text)) {
            val mapped = StringBuilder()
            for (byte in m.value.toByteArray(Charsets.UTF_8)) {
                mapped.append(byteEncoder[byte.toInt() and 0xFF])
            }
            for (tok in bpe(mapped.toString())) out.add(vocab[tok] ?: unk)
        }
        return out
    }

    private fun bpe(token: String): List<String> {
        if (token.isEmpty()) return emptyList()
        var word = token.map { it.toString() }.toMutableList()
        while (word.size > 1) {
            var bestRank = Int.MAX_VALUE
            var best: Pair<String, String>? = null
            for (i in 0 until word.size - 1) {
                val rank = mergeRanks[word[i] to word[i + 1]] ?: continue
                if (rank < bestRank) { bestRank = rank; best = word[i] to word[i + 1] }
            }
            val pair = best ?: break
            val merged = ArrayList<String>()
            var i = 0
            while (i < word.size) {
                if (i < word.size - 1 && word[i] == pair.first && word[i + 1] == pair.second) {
                    merged.add(pair.first + pair.second); i += 2
                } else { merged.add(word[i]); i++ }
            }
            word = merged
        }
        return word
    }

    private fun buildMergeRanks(merges: List<String>): Map<Pair<String, String>, Int> {
        val map = HashMap<Pair<String, String>, Int>()
        merges.forEachIndexed { i, m ->
            val sp = m.indexOf(' ')
            if (sp > 0) map[m.substring(0, sp) to m.substring(sp + 1)] = i
        }
        return map
    }

    /** GPT-2 reversible byte ↔ unicode mapping so every byte is a printable char. */
    private fun buildByteEncoder(): Map<Int, Char> {
        val bs = ArrayList<Int>()
        (('!'.code)..('~'.code)).forEach { bs.add(it) }
        (('¡'.code)..('¬'.code)).forEach { bs.add(it) }
        (('®'.code)..('ÿ'.code)).forEach { bs.add(it) }
        val cs = bs.toMutableList()
        var n = 0
        for (b in 0..255) if (b !in bs) { bs.add(b); cs.add(256 + n); n++ }
        val map = HashMap<Int, Char>()
        for (i in bs.indices) map[bs[i]] = cs[i].toChar()
        return map
    }

    companion object {
        fun fromJson(text: String): BpeTokenizer {
            val model = JSONObject(text).getJSONObject("model")
            val vocabObj = model.getJSONObject("vocab")
            val vocab = HashMap<String, Int>()
            vocabObj.keys().forEach { vocab[it] = vocabObj.getInt(it) }
            val mergesArr: JSONArray = model.optJSONArray("merges") ?: JSONArray()
            val merges = ArrayList<String>(mergesArr.length())
            for (i in 0 until mergesArr.length()) {
                when (val e = mergesArr.get(i)) {
                    is JSONArray -> merges.add("${e.getString(0)} ${e.getString(1)}")
                    else -> merges.add(e.toString())
                }
            }
            return BpeTokenizer(
                vocab, merges,
                bos = vocab["<s>"] ?: 0,
                eos = vocab["</s>"] ?: 2,
                unk = vocab["<unk>"] ?: 3,
            )
        }
    }
}
