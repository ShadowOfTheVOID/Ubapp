package com.example.ubapp.shared

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter

/** Reusable lobby chrome — start CTA + QR card guests scan. */
@Composable
fun HostingChrome(joinUrl: String?, onStart: () -> Unit) {
    if (joinUrl == null) {
        Button(onClick = onStart) { Text("Start hosting") }
    } else {
        ElevatedCard {
            Column(Modifier.padding(16.dp)) {
                Text("Guests join here", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                QRCode(joinUrl, size = 200)
                Text(joinUrl, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
fun QRCode(text: String, size: Int) {
    val bitmap = remember(text, size) {
        val matrix = MultiFormatWriter().encode(text, BarcodeFormat.QR_CODE, size, size)
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        for (x in 0 until size) for (y in 0 until size) {
            bmp.setPixel(x, y, if (matrix.get(x, y)) 0xFF000000.toInt() else 0xFFFFFFFF.toInt())
        }
        bmp
    }
    Image(bitmap.asImageBitmap(), contentDescription = "QR code",
          modifier = Modifier.size(size.dp))
}
