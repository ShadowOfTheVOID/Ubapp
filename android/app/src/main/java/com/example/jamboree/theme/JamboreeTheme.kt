package com.example.jamboree.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Brand tokens for the Jamboree UI redesign — black canvas, neon-magenta
 * accent, Roboto + monospaced labels. [Ub] is the single source of truth
 * used by every redesigned shared screen and atom (`JamboreeKit.kt`).
 *
 * Per-game screens are not wrapped in this theme — they keep the default
 * MaterialTheme from [MainActivity].
 */
object Ub {
    val Accent = Color(0xFFFF2E88)        // primary action, host pip, focus
    val OnAccent = Color(0xFF2A0010)      // ink on magenta
    val Foreground = Color.White          // body text, guest pips
    val Background = Color(0xFF000000)    // app bg
    val Canvas = Color(0xFF0A0A0A)        // screen canvas
    val Surface = Color(0xFF141416)       // card / list-row bg
    val SurfaceHi = Color(0xFF1C1C1F)     // hover / pressed / glyph tile
    val Line = Color.White.copy(alpha = 0.08f)        // hairline dividers
    val LineStrong = Color.White.copy(alpha = 0.14f)  // button outline
    val Muted = Color.White.copy(alpha = 0.58f)       // secondary text
    val Faint = Color.White.copy(alpha = 0.38f)       // tertiary / metadata
    val AccentSoft = Color(0xFFFF2E88).copy(alpha = 0.14f)  // selected-row fill
    val AccentLine = Color(0xFFFF2E88).copy(alpha = 0.45f)  // selected-row border
    val Online = Color(0xFF3DDC84)        // connected pip

    object Radius {
        val chip = 8.dp
        val button = 12.dp
        val row = 14.dp
        val card = 16.dp
        val panel = 18.dp
        val hero = 22.dp
    }
}

private val JamboreeColorScheme = darkColorScheme(
    primary = Ub.Accent,
    onPrimary = Ub.OnAccent,
    secondary = Ub.Accent,
    onSecondary = Ub.OnAccent,
    background = Ub.Canvas,
    onBackground = Ub.Foreground,
    surface = Ub.Surface,
    onSurface = Ub.Foreground,
    surfaceVariant = Ub.SurfaceHi,
    onSurfaceVariant = Ub.Muted,
    // Drift elevated surfaces magenta to match the mock.
    surfaceTint = Ub.Accent,
    outline = Ub.LineStrong,
    error = Ub.Accent,
)

@Composable
fun JamboreeTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = JamboreeColorScheme) {
        Surface(color = Ub.Canvas, contentColor = Ub.Foreground) {
            content()
        }
    }
}
