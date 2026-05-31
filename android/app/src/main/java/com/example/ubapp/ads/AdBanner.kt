package com.example.ubapp.ads

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ubapp.theme.Ub
import com.example.ubapp.theme.ubCard

/**
 * Lobby / between-rounds banner slot.
 * Replace the placeholder with a GADBannerView composable once the AdMob SDK is wired up.
 */
@Composable
fun AdBanner(modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    if (AdManager.isAdFree(ctx)) return

    // Placeholder — swap for real ad view in production.
    Box(
        modifier
            .fillMaxWidth()
            .height(50.dp)
            .ubCard(),
        contentAlignment = Alignment.Center,
    ) {
        Text("Ad", fontSize = 11.sp, color = Ub.Muted)
    }
}
