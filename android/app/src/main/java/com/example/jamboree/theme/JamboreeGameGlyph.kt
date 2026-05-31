package com.example.jamboree.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// Per-game abstract glyphs — square tiles in the same visual vocabulary as
// the cards. Games without a bespoke mark fall back to a [GameGlyph.Letter].

sealed interface GameGlyph {
    data object Crazy8s : GameGlyph
    data object Cheat : GameGlyph
    data object President : GameGlyph
    data object BluffMarket : GameGlyph
    data object Mafia : GameGlyph
    data object Werewolf : GameGlyph
    data object Imposter : GameGlyph
    data class Letter(val ch: String) : GameGlyph
}

@Composable
fun GameGlyphView(glyph: GameGlyph, size: Dp = 56.dp) {
    Box(
        Modifier
            .size(size)
            .clip(RoundedCornerShape(size * 0.18f))
            .background(Ub.SurfaceHi),
        contentAlignment = Alignment.Center,
    ) {
        when (glyph) {
            GameGlyph.Crazy8s -> {
                Text("8", color = Color.White, fontWeight = FontWeight.Black,
                     fontSize = (size.value * 0.62f).sp, letterSpacing = (-size.value * 0.06f).sp)
                Canvas(Modifier.matchParentSize()) {
                    rotate(-22f, pivot = Offset(w * 0.5f, h * 0.55f)) {
                        drawRect(Ub.Accent,
                                 topLeft = Offset(-0.1f * w, 0.50f * h),
                                 size = Size(1.2f * w, 0.10f * h))
                    }
                }
            }
            GameGlyph.Cheat -> Canvas(Modifier.matchParentSize()) {
                for (i in 0..2) {
                    val cw = 0.42f * w; val ch = 0.56f * h
                    val tl = Offset((0.20f + i * 0.06f) * w, (0.22f + i * 0.04f) * h)
                    rotate(-6f + i * 6f, pivot = Offset(tl.x + cw / 2, tl.y + ch / 2)) {
                        drawRoundRect(Color(0xFF222222), tl, Size(cw, ch), CornerRadius(0.04f * w))
                        drawRoundRect(Ub.LineStrong, tl, Size(cw, ch), CornerRadius(0.04f * w),
                                      style = Stroke(width = 1f))
                    }
                }
            }
            GameGlyph.President -> Canvas(Modifier.matchParentSize()) {
                val inset = 0.16f * w; val barH = 0.07f * h; val gap = 0.05f * h
                val total = barH * 4 + gap * 3
                var y = (h - total) / 2
                val widths = listOf(0.95f, 0.70f, 0.70f, 0.38f)
                val colors = listOf(Ub.Accent, Color.White, Color.White, Color.White.copy(alpha = 0.45f))
                for (i in 0..3) {
                    drawRoundRect(colors[i], Offset(inset, y),
                                  Size((w - inset * 2) * widths[i], barH), CornerRadius(2f))
                    y += barH + gap
                }
            }
            GameGlyph.Mafia -> Canvas(Modifier.matchParentSize()) {
                val r = 0.18f * w
                val cx = 0.74f * w; val cy = 0.28f * h
                drawCircle(
                    Brush.radialGradient(
                        listOf(Color(0xFFD8D2C5), Color(0xFF45402F)),
                        center = Offset(cx - r * 0.4f, cy - r * 0.4f), radius = r),
                    radius = r, center = Offset(cx, cy))
                drawRoundRect(Ub.Accent, Offset(0.14f * w, 0.70f * h),
                              Size(0.72f * w, 0.10f * h), CornerRadius(0.05f * w))
                drawRoundRect(Ub.Accent, Offset(0.30f * w, 0.48f * h),
                              Size(0.40f * w, 0.22f * h), CornerRadius(0.06f * w))
                drawRect(Color.Black, Offset(0.30f * w, 0.66f * h), Size(0.40f * w, 0.04f * h))
            }
            GameGlyph.Werewolf -> Canvas(Modifier.matchParentSize()) {
                val bx = 0.22f * w; val by = 0.22f * h; val bw = 0.56f * w; val bh = 0.48f * h
                val pts = listOf(
                    0f to 0.30f, 0.20f to 0f, 0.35f to 0.25f, 0.65f to 0.25f,
                    0.80f to 0f, 1f to 0.30f, 1f to 0.80f, 0.50f to 1f, 0f to 0.80f)
                val path = Path()
                pts.forEachIndexed { i, (px, py) ->
                    val p = Offset(bx + px * bw, by + py * bh)
                    if (i == 0) path.moveTo(p.x, p.y) else path.lineTo(p.x, p.y)
                }
                path.close()
                drawPath(path, Color.White)
                drawOval(Ub.Accent, Offset(0.36f * w - 0.04f * w, 0.49f * h - 0.03f * h),
                         Size(0.08f * w, 0.06f * h))
                drawOval(Ub.Accent, Offset(0.64f * w - 0.04f * w, 0.49f * h - 0.03f * h),
                         Size(0.08f * w, 0.06f * h))
                drawCircle(Color.White.copy(alpha = 0.45f), 0.09f * w, Offset(0.19f * w, 0.19f * h))
            }
            GameGlyph.Imposter -> {
                Canvas(Modifier.matchParentSize()) {
                    drawRoundRect(Ub.Accent, Offset(0.14f * w, 0.18f * h),
                                  Size(0.72f * w, 0.52f * h), CornerRadius(0.12f * w))
                    val tail = Path().apply {
                        moveTo(0.22f * w, 0.64f * h)
                        lineTo(0.42f * w, 0.64f * h)
                        lineTo(0.26f * w, 0.82f * h)
                        close()
                    }
                    drawPath(tail, Ub.Accent)
                }
                Text("?", color = Ub.OnAccent, fontWeight = FontWeight.Black,
                     fontSize = (size.value * 0.34f).sp,
                     modifier = Modifier.padding(bottom = (size.value * 0.10f).dp))
            }
            GameGlyph.BluffMarket -> Canvas(Modifier.matchParentSize()) {
                drawRect(Color.White, Offset(0.22f * w, 0.20f * h), Size(0.04f * w, 0.40f * h))
                drawPath(triangle(Offset(0.24f * w, 0.16f * h), 0.16f * w, up = true, h = h, w = w), Color.White)
                drawRect(Color.White, Offset(0.68f * w, 0.40f * h), Size(0.04f * w, 0.40f * h))
                drawPath(triangle(Offset(0.70f * w, 0.84f * h), 0.16f * w, up = false, h = h, w = w), Color.White)
                drawCircle(Ub.Accent, 0.08f * w, Offset(0.74f * w, 0.74f * h))
            }
            is GameGlyph.Letter -> Text(
                glyph.ch, color = Ub.Accent, fontWeight = FontWeight.Bold,
                fontSize = (size.value * 0.4f).sp)
        }
    }
}

private val DrawScope.w get() = size.width
private val DrawScope.h get() = size.height

// Centered up/down triangle of the given [side], apex on [center].
private fun triangle(center: Offset, side: Float, up: Boolean, w: Float, h: Float): Path {
    val half = side / 2
    return Path().apply {
        if (up) {
            moveTo(center.x, center.y)
            lineTo(center.x + half, center.y + side)
            lineTo(center.x - half, center.y + side)
        } else {
            moveTo(center.x - half, center.y - side)
            lineTo(center.x + half, center.y - side)
            lineTo(center.x, center.y)
        }
        close()
    }
}
