package com.example.jamboree.ads

import android.app.Activity
import com.google.android.gms.ads.MobileAds
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Handles GDPR / CCPA consent via Google's User Messaging Platform.
 *
 * Call [initialize] from Activity.onCreate(). It:
 *   1. Asks the UMP SDK if a consent form is required for this user's region.
 *   2. Shows the form if needed (first launch in EU, or consent expired).
 *   3. Calls MobileAds.initialize() only once consent is confirmed (or not
 *      required — e.g. users outside GDPR / CCPA jurisdictions see no form).
 *
 * Subsequent launches where consent is already on-file skip the form and
 * initialize ads immediately via the canRequestAds() fast-path.
 */
object ConsentManager {

    /** Guards against starting the Ads SDK more than once — the fast-path and
     *  the async callbacks below can each reach the init point. */
    private val adsStarted = AtomicBoolean(false)

    private fun startAdsOnce(activity: Activity) {
        if (adsStarted.compareAndSet(false, true)) MobileAds.initialize(activity)
    }

    fun initialize(activity: Activity) {
        val consentInfo = UserMessagingPlatform.getConsentInformation(activity)
        val params = ConsentRequestParameters.Builder()
            .setTagForUnderAgeOfConsent(false)
            .build()

        // Fast-path: consent already on file from a previous session.
        if (consentInfo.canRequestAds()) {
            startAdsOnce(activity)
        }

        consentInfo.requestConsentInfoUpdate(activity, params,
            {
                // Info updated — show form if required (EU first launch, etc.)
                UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) {
                    // Form dismissed (with or without an error).
                    // Initialize ads now if we can — covers the first-launch path.
                    if (consentInfo.canRequestAds()) {
                        startAdsOnce(activity)
                    }
                }
            },
            {
                // Failed to fetch consent status (offline, etc.).
                // Initialize anyway — safe outside GDPR/CCPA zones.
                startAdsOnce(activity)
            }
        )
    }
}
