package com.example.jamboree.ads

import android.content.Context

/**
 * Manages ad-free state.
 *
 * IAP wiring: integrate Google Play Billing Library and call [setAdFree] from
 * the purchase callback when the SKU "com.jamboree.adfree" is acknowledged.
 * The Play Billing dependency is in build.gradle.kts.
 */
object AdManager {
    private const val PREFS = "jamboree.ads"
    private const val KEY_AD_FREE = "adFree"
    const val SKU = "com.jamboree.adfree"

    private fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isAdFree(ctx: Context): Boolean = prefs(ctx).getBoolean(KEY_AD_FREE, false)

    fun setAdFree(ctx: Context, value: Boolean) {
        prefs(ctx).edit().putBoolean(KEY_AD_FREE, value).apply()
    }
}
