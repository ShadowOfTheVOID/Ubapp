package com.example.ubapp.join

/**
 * Encodes / decodes a 7-character base-36 join code that maps to an IPv4
 * address. Port is fixed at 7654 on the host. Mirrors JoinCode.swift —
 * codes are case-insensitive and hyphens / whitespace are stripped.
 */
object JoinCode {
    const val DEFAULT_PORT: Int = 7654
    const val CODE_LENGTH = 7
    private val ALPHABET = "0123456789abcdefghijklmnopqrstuvwxyz"

    /** IPv4 string → 7-char uppercase code formatted as "ABCD-EFG". */
    fun encode(ip: String): String? {
        val n = ipToUInt32(ip) ?: return null
        var num = n.toLong() and 0xFFFFFFFFL
        val chars = CharArray(CODE_LENGTH)
        for (i in CODE_LENGTH - 1 downTo 0) {
            chars[i] = ALPHABET[(num % 36).toInt()]
            num /= 36
        }
        val raw = String(chars).uppercase()
        return "${raw.substring(0, 4)}-${raw.substring(4)}"
    }

    /** Code or raw IP → IPv4 string. Returns null if neither parses. */
    fun decode(input: String): String? {
        val trimmed = input.trim()
        if (trimmed.contains('.')) return parseIp(trimmed)
        val cleaned = trimmed.lowercase().filter { it.isLetterOrDigit() }
        if (cleaned.length != CODE_LENGTH) return null
        var n = 0L
        for (c in cleaned) {
            val i = ALPHABET.indexOf(c)
            if (i < 0) return null
            n = n * 36 + i
        }
        if (n > 0xFFFFFFFFL) return null
        return uint32ToIp(n.toInt())
    }

    private fun parseIp(s: String): String? {
        val parts = s.split('.')
        if (parts.size != 4) return null
        val bytes = parts.map { it.toIntOrNull() ?: return null }
        if (bytes.any { it !in 0..255 }) return null
        return bytes.joinToString(".")
    }

    private fun ipToUInt32(s: String): Int? {
        val ip = parseIp(s) ?: return null
        val bytes = ip.split('.').map { it.toInt() }
        return (bytes[0] shl 24) or (bytes[1] shl 16) or (bytes[2] shl 8) or bytes[3]
    }

    private fun uint32ToIp(n: Int): String {
        val a = (n ushr 24) and 0xFF
        val b = (n ushr 16) and 0xFF
        val c = (n ushr 8) and 0xFF
        val d = n and 0xFF
        return "$a.$b.$c.$d"
    }
}
