package com.example.ubapp.shared

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.ubapp.join.JoinCode
import com.example.ubapp.settings.AppSettings
import com.example.ubapp.social.HostDiagnostics
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter

/** Reusable lobby chrome — start CTA + QR card guests scan. */
@Composable
fun HostingChrome(joinUrl: String?, onStart: () -> Unit, onStop: (() -> Unit)? = null) {
    if (joinUrl == null) {
        Button(
            onClick = onStart,
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) {
            Text("Start hosting", style = MaterialTheme.typography.titleMedium)
        }
    } else {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            ElevatedCard(Modifier.fillMaxWidth()) {
                Column(
                    Modifier.fillMaxWidth().padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("Guests join here", style = MaterialTheme.typography.titleMedium)
                    QRCode(
                        joinUrl,
                        size = 220,
                        modifier = Modifier
                            .clip(RoundedCornerShape(8.dp))
                            .background(Color.White)
                            .padding(8.dp),
                    )
                    val host = runCatching { java.net.URI(joinUrl).host }.getOrNull()
                    val code = host?.let { JoinCode.encode(it) }
                    if (code != null) {
                        Column(horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("App code",
                                 style = MaterialTheme.typography.bodySmall,
                                 color = MaterialTheme.colorScheme.onSurfaceVariant)
                            Text(
                                code,
                                fontFamily = FontFamily.Monospace,
                                fontSize = 28.sp,
                                style = MaterialTheme.typography.titleLarge,
                            )
                        }
                    }
                    Text(
                        joinUrl,
                        style = MaterialTheme.typography.bodySmall,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                    Text(
                        "Browser guests scan the QR. App guests open \"Join a game\" and type the code or IP.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            val ctx = LocalContext.current
            if (AppSettings.diagnosticsEnabled(ctx) && HostDiagnostics.lines.isNotEmpty()) {
                ElevatedCard(Modifier.fillMaxWidth()) {
                    Text(
                        HostDiagnostics.lines.joinToString("\n"),
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(max = 240.dp)
                            .verticalScroll(rememberScrollState())
                            .padding(12.dp),
                        fontFamily = FontFamily.Monospace,
                        fontSize = 10.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (onStop != null) {
                OutlinedButton(
                    onClick = onStop,
                    modifier = Modifier.fillMaxWidth().height(48.dp),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = MaterialTheme.colorScheme.error,
                    ),
                ) {
                    Text("Stop hosting", style = MaterialTheme.typography.titleMedium)
                }
            }
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
