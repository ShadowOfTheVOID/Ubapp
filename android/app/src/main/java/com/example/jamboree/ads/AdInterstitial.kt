package com.example.jamboree.ads

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.UbPrimaryButton
import com.google.android.gms.ads.AdError
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.FullScreenContentCallback
import com.google.android.gms.ads.LoadAdError
import com.google.android.gms.ads.interstitial.InterstitialAd
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback
import kotlinx.coroutines.delay

private const val INTERSTITIAL_UNIT_ID = "ca-app-pub-8315138960777125/7174463769"

/**
 * Preloads and presents a real AdMob interstitial when [show] goes true.
 * Falls back to a ≤10 s skippable overlay if the ad hasn't loaded
 * (offline, no-fill, cold first session). No-op when ad-free.
 */
@Composable
fun AdInterstitialController(show: Boolean, onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    if (AdManager.isAdFree(ctx)) {
        LaunchedEffect(show) { if (show) onDismiss() }
        return
    }

    var interstitialAd by remember { mutableStateOf<InterstitialAd?>(null) }
    var showFallback by remember { mutableStateOf(false) }

    // Preload as soon as this composable enters composition.
    LaunchedEffect(Unit) {
        InterstitialAd.load(ctx, INTERSTITIAL_UNIT_ID, AdRequest.Builder().build(),
            object : InterstitialAdLoadCallback() {
                override fun onAdLoaded(ad: InterstitialAd) { interstitialAd = ad }
                override fun onAdFailedToLoad(error: LoadAdError) { interstitialAd = null }
            })
    }

    LaunchedEffect(show) {
        if (!show) return@LaunchedEffect
        val ad = interstitialAd
        if (ad != null) {
            ad.fullScreenContentCallback = object : FullScreenContentCallback() {
                override fun onAdDismissedFullScreenContent() {
                    interstitialAd = null
                    onDismiss()
                    // Reload for the next round.
                    InterstitialAd.load(ctx, INTERSTITIAL_UNIT_ID, AdRequest.Builder().build(),
                        object : InterstitialAdLoadCallback() {
                            override fun onAdLoaded(a: InterstitialAd) { interstitialAd = a }
                            override fun onAdFailedToLoad(e: LoadAdError) { interstitialAd = null }
                        })
                }
                override fun onAdFailedToShowFullScreenContent(error: AdError) {
                    interstitialAd = null; onDismiss()
                }
            }
            (ctx as? Activity)?.let { ad.show(it) } ?: onDismiss()
        } else {
            showFallback = true
        }
    }

    if (showFallback) {
        AdFallbackOverlay {
            showFallback = false
            onDismiss()
        }
    }
}

// Shown when the real ad hasn't loaded (offline / no-fill / cold start).
@Composable
private fun AdFallbackOverlay(onDismiss: () -> Unit) {
    var remaining by remember { mutableIntStateOf(10) }
    LaunchedEffect(Unit) {
        for (i in 10 downTo 1) { remaining = i; delay(1_000) }
        remaining = 0; onDismiss()
    }

    Box(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.88f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Spacer(Modifier.weight(1f))
            Column(
                Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("Ad", fontSize = 11.sp, color = Ub.Muted)
                Box(
                    Modifier.fillMaxWidth().height(240.dp)
                        .background(Ub.Surface, RoundedCornerShape(Ub.Radius.card)),
                    contentAlignment = Alignment.Center,
                ) { Text("Advertisement", fontSize = 15.sp, color = Ub.Faint) }
            }
            Spacer(Modifier.weight(1f))
            UbPrimaryButton(
                if (remaining > 0) "Skip ($remaining)" else "Skip",
                modifier = Modifier.padding(horizontal = 40.dp).padding(bottom = 40.dp),
                onClick = onDismiss,
            )
        }
    }
}
