package com.example.ubapp.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/**
 * Black + neon-magenta chrome for the menu and non-game shared screens
 * (Social, Join). Per-game screens are not wrapped in this theme — they
 * keep the default MaterialTheme from [MainActivity].
 */
private val Accent = Color(0xFFFF2E88)
private val Background = Color(0xFF000000)
private val OnDark = Color(0xFFFFFFFF)

private val UbappColorScheme = darkColorScheme(
    primary = Accent,
    onPrimary = Color(0xFF2A0010),
    secondary = Accent,
    onSecondary = Color(0xFF2A0010),
    background = Background,
    onBackground = OnDark,
    surface = Background,
    onSurface = OnDark,
    surfaceVariant = Color(0xFF1A1A1A),
    onSurfaceVariant = OnDark,
)

@Composable
fun UbappTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = UbappColorScheme) {
        Surface(color = UbappColorScheme.background, contentColor = OnDark) {
            content()
        }
    }
}
