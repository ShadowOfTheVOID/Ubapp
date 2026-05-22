package com.example.ubapp.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Reusable brand atoms for the redesigned shared screens. Everything reads
// from [Ub] — no literal colors or sizes.

/** Surface card with hairline border at [radius]. */
fun Modifier.ubCard(
    radius: Dp = Ub.Radius.card,
    fill: Color = Ub.Surface,
    stroke: Color = Ub.Line,
): Modifier = this
    .clip(RoundedCornerShape(radius))
    .background(fill)
    .border(1.dp, stroke, RoundedCornerShape(radius))

/** Accent-tinted hero/callout container. */
fun Modifier.ubAccentCard(radius: Dp = Ub.Radius.card): Modifier =
    ubCard(radius, fill = Ub.AccentSoft, stroke = Ub.AccentLine)

/** Uppercase monospaced micro-label (codes, section headers, metadata). */
@Composable
fun MonoLabel(text: String, size: Int = 11, color: Color = Ub.Muted) {
    Text(
        text.uppercase(),
        fontFamily = FontFamily.Monospace,
        fontSize = size.sp,
        fontWeight = FontWeight.Medium,
        letterSpacing = (size * 0.14f).sp,
        color = color,
    )
}

/** `ubapp` wordmark with optional magenta dot. */
@Composable
fun Wordmark(size: Int = 22, color: Color = Color.White, dot: Boolean = false) {
    androidx.compose.foundation.layout.Row(
        verticalAlignment = Alignment.Bottom,
        horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy((size * 0.04f).dp),
    ) {
        Text(
            "ubapp",
            fontSize = size.sp,
            fontWeight = FontWeight.ExtraBold,
            letterSpacing = (-size * 0.04f).sp,
            color = color,
        )
        if (dot) {
            Box(
                Modifier
                    .padding(bottom = (size * 0.12f).dp)
                    .size((size * 0.16f).dp)
                    .clip(CircleShape)
                    .background(Ub.Accent),
            )
        }
    }
}

/** 4-pip die-face mark; the [accentIndex] pip is magenta. */
@Composable
fun PipMark(size: Dp = 24.dp, color: Color = Color.White, accentIndex: Int = 0) {
    Canvas(Modifier.size(size)) {
        val s = this.size.minDimension
        val r = s * 0.22f
        val inset = s * 0.18f
        val centers = listOf(
            Offset(inset + r / 2, inset + r / 2),
            Offset(s - inset - r / 2, inset + r / 2),
            Offset(inset + r / 2, s - inset - r / 2),
            Offset(s - inset - r / 2, s - inset - r / 2),
        )
        centers.forEachIndexed { i, c ->
            drawCircle(if (i == accentIndex) Ub.Accent else color, radius = r / 2, center = c)
        }
    }
}

/** Round guest/host avatar — host is solid magenta, guest is a faint chip. */
@Composable
fun Avatar(name: String, host: Boolean = false, size: Dp = 28.dp) {
    Box(
        Modifier
            .size(size)
            .clip(CircleShape)
            .background(if (host) Ub.Accent else Color.White.copy(alpha = 0.10f))
            .then(if (host) Modifier else Modifier.border(1.dp, Ub.Line, CircleShape)),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            name.take(1),
            color = if (host) Ub.OnAccent else Ub.Foreground,
            fontWeight = FontWeight.Bold,
            fontSize = (size.value * 0.42f).sp,
        )
    }
}

/** Filled magenta primary action. */
@Composable
fun UbPrimaryButton(
    text: String,
    modifier: Modifier = Modifier.fillMaxWidth(),
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        shape = RoundedCornerShape(Ub.Radius.button),
        contentPadding = PaddingValues(vertical = 16.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Ub.Accent,
            contentColor = Ub.OnAccent,
            disabledContainerColor = Ub.Accent.copy(alpha = 0.4f),
            disabledContentColor = Ub.OnAccent.copy(alpha = 0.7f),
        ),
    ) {
        Text(text, fontSize = 16.sp, fontWeight = FontWeight.Bold)
    }
}

/** Outlined translucent secondary action. */
@Composable
fun UbSecondaryButton(
    text: String,
    modifier: Modifier = Modifier.fillMaxWidth(),
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        shape = RoundedCornerShape(Ub.Radius.button),
        contentPadding = PaddingValues(vertical = 14.dp),
        border = androidx.compose.foundation.BorderStroke(1.dp, Ub.Line),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = Color.White.copy(alpha = 0.06f),
            contentColor = Ub.Foreground,
        ),
    ) {
        Text(text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}
