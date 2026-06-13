package com.example.jamboree.ads

import android.content.Context

/**
 * Persists ad-free state. [BillingManager] drives this from the Google Play
 * purchase/restore callbacks once the SKU [SKU] is acknowledged; the ad call
 * sites ([AdBanner], [AdInterstitial]) read [isAdFree] to suppress placements.
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
