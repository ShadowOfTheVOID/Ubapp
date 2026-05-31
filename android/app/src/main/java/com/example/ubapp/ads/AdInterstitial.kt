package com.example.ubapp.ads

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ubapp.theme.Ub
import com.example.ubapp.theme.UbPrimaryButton
import kotlinx.coroutines.delay

/**
 * ≤10 s skippable ad overlay. Pass `onDismiss` to remove the interstitial once
 * the countdown ends or the user taps Skip.
 * No-op when the user has the ad-free upgrade.
 *
 * Replace the placeholder rectangle with an actual AdMob full-screen ad
 * (or a GADBannerView composable) once the SDK is wired up.
 */
@Composable
fun AdInterstitialOverlay(onDismiss: () -> Unit) {
    val ctx = LocalContext.current
    if (AdManager.isAdFree(ctx)) {
        LaunchedEffect(Unit) { onDismiss() }
        return
    }

    var remaining by remember { mutableIntStateOf(10) }
    LaunchedEffect(Unit) {
        for (i in 10 downTo 1) {
            remaining = i
            delay(1_000)
        }
        remaining = 0
        onDismiss()
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.88f)),
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
                // Placeholder rectangle — replace with AdMob view.
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(240.dp)
                        .background(Ub.Surface, RoundedCornerShape(Ub.Radius.card)),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("Advertisement", fontSize = 15.sp, color = Ub.Faint)
                }
            }
            Spacer(Modifier.weight(1f))
            val label = if (remaining > 0) "Skip ($remaining)" else "Skip"
            UbPrimaryButton(label, modifier = Modifier.padding(horizontal = 40.dp).padding(bottom = 40.dp),
                            onClick = onDismiss)
        }
    }
}
