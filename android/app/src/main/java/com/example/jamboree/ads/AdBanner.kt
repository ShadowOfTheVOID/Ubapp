package com.example.jamboree.ads

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.example.jamboree.BuildConfig
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView

enum class AdBannerPlacement(private val liveAdUnitId: String) {
    LOBBY("ca-app-pub-8315138960777125/6515988219"),
    BETWEEN_ROUNDS("ca-app-pub-8315138960777125/6655589018");

    /** Debug builds use Google's sample banner unit so development/QA never
     *  request live ads (loading or clicking your own production ads is an
     *  AdMob policy violation). Release uses the real unit. */
    val adUnitId: String
        get() = if (BuildConfig.DEBUG) "ca-app-pub-3940256099942544/6300978111" else liveAdUnitId
}

@Composable
fun AdBanner(placement: AdBannerPlacement, modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    if (AdManager.isAdFree(ctx)) return

    AndroidView(
        modifier = modifier,
        factory = {
            AdView(it).apply {
                setAdSize(AdSize.BANNER)
                adUnitId = placement.adUnitId
                loadAd(AdRequest.Builder().build())
            }
        },
    )
}
