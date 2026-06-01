package com.example.jamboree.ads

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView

enum class AdBannerPlacement(val adUnitId: String) {
    LOBBY("ca-app-pub-8315138960777125/6515988219"),
    BETWEEN_ROUNDS("ca-app-pub-8315138960777125/6655589018"),
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
