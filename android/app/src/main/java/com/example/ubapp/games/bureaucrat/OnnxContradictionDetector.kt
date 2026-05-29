package com.example.ubapp.games.bureaucrat

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import java.nio.LongBuffer

/**
 * NLI-backed contradiction detector for `cross-encoder/nli-MiniLM2-L6-H768`.
 *
 * The model is a BERT cross-encoder: feed it `[CLS] premise [SEP] hypothesis
 * [SEP]` and it emits three logits in the order
 * `[contradiction, entailment, neutral]`. We run the bureaucrat's rebuttal
 * (hypothesis) against each prior policy statement (premise); if any pair's
 * arg-max is index 0 the loophole stands.
 *
 * Two assets must be present for this to activate (see CLAUDE.md — drop them
 * into BOTH `assets/` and iOS `Resources/`):
 *   - `nli_minilm.onnx`  — the int8-quantised model (~85 MB)
 *   - `nli_vocab.txt`    — the WordPiece vocabulary, one token per line
 *
 * [tryCreate] returns null when either asset is missing or the runtime fails
 * to initialise, and the server falls back to [KeywordContradictionDetector].
 * Everything here is synchronous CPU compute — no network, fully offline.
 */
class OnnxContradictionDetector private constructor(
    private val env: OrtEnvironment,
    private val session: OrtSession,
    private val tokenizer: WordPieceTokenizer,
    private val fallback: ContradictionDetector,
) : ContradictionDetector {

    override fun contradicts(priorStatements: List<String>, rebuttal: String): Boolean {
        if (rebuttal.isBlank()) return false
        for (prior in priorStatements) {
            if (runPair(premise = prior, hypothesis = rebuttal)) return true
        }
        return false
    }

    /** True when the model labels (premise, hypothesis) as contradiction. */
    private fun runPair(premise: String, hypothesis: String): Boolean {
        val enc = tokenizer.encodePair(premise, hypothesis, MAX_LEN)
        val shape = longArrayOf(1, enc.ids.size.toLong())
        val ids = OnnxTensor.createTensor(env, LongBuffer.wrap(enc.ids), shape)
        val mask = OnnxTensor.createTensor(env, LongBuffer.wrap(enc.mask), shape)
        val types = OnnxTensor.createTensor(env, LongBuffer.wrap(enc.typeIds), shape)
        return try {
            val inputs = mapOf(
                "input_ids" to ids,
                "attention_mask" to mask,
                "token_type_ids" to types,
            )
            session.run(inputs).use { result ->
                @Suppress("UNCHECKED_CAST")
                val logits = (result[0].value as Array<FloatArray>)[0]
                argMax(logits) == CONTRADICTION_INDEX
            }
        } catch (t: Throwable) {
            // A malformed model or unexpected I/O shape should degrade, not crash.
            fallback.contradicts(listOf(premise), hypothesis)
        } finally {
            ids.close(); mask.close(); types.close()
        }
    }

    private fun argMax(a: FloatArray): Int {
        var best = 0
        for (i in 1 until a.size) if (a[i] > a[best]) best = i
        return best
    }

    fun close() {
        runCatching { session.close() }
    }

    companion object {
        private const val MAX_LEN = 128
        private const val CONTRADICTION_INDEX = 0
        const val MODEL_ASSET = "nli_minilm.onnx"
        const val VOCAB_ASSET = "nli_vocab.txt"

        /**
         * Builds the detector if the bundled assets load, otherwise null so the
         * caller can fall back. Never throws.
         */
        fun tryCreate(
            context: Context,
            fallback: ContradictionDetector = KeywordContradictionDetector(),
        ): OnnxContradictionDetector? = runCatching {
            val assets = context.assets
            val available = assets.list("")?.toSet() ?: emptySet()
            if (MODEL_ASSET !in available || VOCAB_ASSET !in available) return null
            val vocab = assets.open(VOCAB_ASSET).bufferedReader().useLines { lines ->
                val map = HashMap<String, Int>()
                lines.forEachIndexed { i, line -> map[line.trim()] = i }
                map
            }
            val modelBytes = assets.open(MODEL_ASSET).use { it.readBytes() }
            val env = OrtEnvironment.getEnvironment()
            val session = env.createSession(modelBytes, OrtSession.SessionOptions())
            OnnxContradictionDetector(env, session, WordPieceTokenizer(vocab), fallback)
        }.getOrNull()
    }
}

/** Encoded sentence pair ready for the model. */
class EncodedPair(val ids: LongArray, val mask: LongArray, val typeIds: LongArray)

/**
 * Minimal uncased BERT WordPiece tokenizer — enough to feed the cross-encoder.
 * Mirrors the reference HuggingFace `BertTokenizer` behaviour for the bits
 * that matter: lowercase, split on whitespace + punctuation, then greedy
 * longest-match subword lookup with `##` continuations and `[UNK]` fallback.
 * Deliberately identical to the Swift `WordPieceTokenizer`.
 */
class WordPieceTokenizer(private val vocab: Map<String, Int>) {
    private val unk = vocab["[UNK]"] ?: 100
    private val cls = vocab["[CLS]"] ?: 101
    private val sep = vocab["[SEP]"] ?: 102
    private val pad = vocab["[PAD]"] ?: 0

    fun encodePair(premise: String, hypothesis: String, maxLen: Int): EncodedPair {
        val a = wordpiece(premise)
        val b = wordpiece(hypothesis)
        // [CLS] a [SEP] b [SEP], truncating the longer side first.
        val budget = maxLen - 3
        var ta = a; var tb = b
        while (ta.size + tb.size > budget) {
            if (ta.size > tb.size) ta = ta.dropLast(1) else tb = tb.dropLast(1)
        }
        val ids = ArrayList<Long>(maxLen)
        val types = ArrayList<Long>(maxLen)
        ids.add(cls.toLong()); types.add(0L)
        ta.forEach { ids.add(it.toLong()); types.add(0L) }
        ids.add(sep.toLong()); types.add(0L)
        tb.forEach { ids.add(it.toLong()); types.add(1L) }
        ids.add(sep.toLong()); types.add(1L)
        val mask = LongArray(ids.size) { 1L }
        // Dynamic sequence length is valid for ONNX Runtime — no padding needed.
        return EncodedPair(ids.toLongArray(), mask, types.toLongArray())
    }

    private fun wordpiece(text: String): List<Int> {
        val out = ArrayList<Int>()
        for (token in basicTokenize(text)) {
            var start = 0
            val chars = token
            var bad = false
            val sub = ArrayList<Int>()
            while (start < chars.length) {
                var end = chars.length
                var cur: Int? = null
                while (start < end) {
                    val piece = (if (start > 0) "##" else "") + chars.substring(start, end)
                    val id = vocab[piece]
                    if (id != null) { cur = id; break }
                    end--
                }
                if (cur == null) { bad = true; break }
                sub.add(cur); start = end
            }
            if (bad) out.add(unk) else out.addAll(sub)
        }
        return out
    }

    /** Lowercase, then split on whitespace with punctuation as its own token. */
    private fun basicTokenize(text: String): List<String> {
        val out = ArrayList<String>()
        val sb = StringBuilder()
        fun flush() { if (sb.isNotEmpty()) { out.add(sb.toString()); sb.clear() } }
        for (ch in text.lowercase()) {
            when {
                ch.isWhitespace() -> flush()
                !ch.isLetterOrDigit() -> { flush(); out.add(ch.toString()) }
                else -> sb.append(ch)
            }
        }
        flush()
        return out
    }
}
