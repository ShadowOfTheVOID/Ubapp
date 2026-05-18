package com.example.ubapp.settings

import android.content.Context

/**
 * User-facing app preferences, persisted in `SharedPreferences`.
 *
 * - `hostName` is the display name this device uses when it hosts a
 *   browser-tier game (the player id is still `host`).
 * - `diagnosticsEnabled` is a developer toggle that reveals the on-screen
 *   host connection log in the hosting screen.
 */
object AppSettings {
    private const val PREFS = "ubapp.settings"
    private const val KEY_HOST_NAME = "hostName"
    private const val KEY_DIAGNOSTICS = "diagnosticsEnabled"

    @Volatile private var cachedDiagnostics = false

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Trimmed host name, never empty. */
    fun hostName(ctx: Context): String {
        val raw = prefs(ctx).getString(KEY_HOST_NAME, null)?.trim().orEmpty()
        return raw.ifEmpty { "Host" }
    }

    fun setHostName(ctx: Context, value: String) {
        prefs(ctx).edit().putString(KEY_HOST_NAME, value).apply()
    }

    fun diagnosticsEnabled(ctx: Context): Boolean {
        val v = prefs(ctx).getBoolean(KEY_DIAGNOSTICS, false)
        cachedDiagnostics = v
        return v
    }

    fun setDiagnostics(ctx: Context, value: Boolean) {
        cachedDiagnostics = value
        prefs(ctx).edit().putBoolean(KEY_DIAGNOSTICS, value).apply()
    }

    /** Last known diagnostics state; safe to read without a [Context] (used
     *  by `HostServer` logging on its socket threads). Seeded via
     *  [diagnosticsEnabled] / [setDiagnostics]. */
    val diagnosticsOn: Boolean get() = cachedDiagnostics
}
