package com.example.jamboree.shared

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.jamboree.join.JoinCode
import com.example.jamboree.settings.AppSettings
import com.example.jamboree.social.HostDiagnostics
import com.example.jamboree.ads.AdBanner
import com.example.jamboree.ads.AdBannerPlacement
import com.example.jamboree.theme.MonoLabel
import com.example.jamboree.theme.Ub
import com.example.jamboree.theme.UbPrimaryButton
import com.example.jamboree.theme.UbSecondaryButton
import com.example.jamboree.theme.ubCard
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter

/** Reusable lobby chrome — start CTA + QR card guests scan. */
@Composable
fun HostingChrome(joinUrl: String?, onStart: () -> Unit, onStop: (() -> Unit)? = null) {
    if (joinUrl == null) {
        UbPrimaryButton("Start hosting", onClick = onStart)
        return
    }

    val clipboard = LocalClipboardManager.current
    var copied by remember { mutableStateOf(false) }
    val uri = remember(joinUrl) { runCatching { java.net.URI(joinUrl) }.getOrNull() }
    val host = uri?.host
    val code = host?.let { JoinCode.encode(it) }
    val ipLine = host?.let { "$it:${uri.port.takeIf { p -> p > 0 } ?: JoinCode.DEFAULT_PORT}" } ?: joinUrl

    Column(
        Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(
            Modifier.fillMaxWidth().ubCard(radius = Ub.Radius.hero).padding(22.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            QRCode(
                joinUrl,
                size = 210,
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .background(Color.White)
                    .padding(10.dp),
            )
            if (code != null) {
                Row(verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    MonoLabel("Code")
                    Text(code, fontFamily = FontFamily.Monospace, fontSize = 26.sp,
                         fontWeight = FontWeight.Bold, letterSpacing = 3.sp, color = Color.White)
                    Box(
                        Modifier.size(28.dp).clip(RoundedCornerShape(8.dp))
                            .background(Color.White.copy(alpha = 0.08f))
                            .clickable {
                                clipboard.setText(AnnotatedString(code))
                                copied = true
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(if (copied) "✓" else "⧉", fontSize = 13.sp,
                             color = if (copied) Ub.Online else Ub.Muted)
                    }
                }
            }
            Text(ipLine, fontFamily = FontFamily.Monospace, fontSize = 11.sp, color = Ub.Faint)
            Text(
                "Browser guests scan the QR. App guests open \"Join a game\" and type the code.",
                fontSize = 12.sp, color = Ub.Muted, textAlign = TextAlign.Center,
            )
        }
        AdBanner(AdBannerPlacement.LOBBY)

        val ctx = LocalContext.current
        if (AppSettings.diagnosticsEnabled(ctx) && HostDiagnostics.lines.isNotEmpty()) {
            Text(
                HostDiagnostics.lines.joinToString("\n"),
                modifier = Modifier
                    .fillMaxWidth()
                    .ubCard()
                    .heightIn(max = 200.dp)
                    .verticalScroll(rememberScrollState())
                    .padding(14.dp),
                fontFamily = FontFamily.Monospace,
                fontSize = 10.sp,
                color = Ub.Muted,
            )
        }
        if (onStop != null) {
            UbSecondaryButton("Stop hosting", onClick = onStop)
        }
    }
}

@Composable
fun QRCode(text: String, size: Int, modifier: Modifier = Modifier) {
    val bitmap = remember(text, size) {
        val matrix = MultiFormatWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        for (x in 0 until size) for (y in 0 until size) {
            bmp.setPixel(x, y, if (matrix.get(x, y)) 0xFF000000.toInt() else 0xFFFFFFFF.toInt())
        }
        bmp
    }
    Image(
        bitmap.asImageBitmap(),
        contentDescription = "QR code",
        modifier = modifier.size(size.dp),
    )
}
