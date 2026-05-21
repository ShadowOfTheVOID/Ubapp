package com.example.ubapp.games.cards

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.TextUnitType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text

/**
 * Shared Noir card system used by Crazy Eights, Cheat, President, and
 * the face-down Grid back used by every game (including Bluff Market).
 *
 * Geometry follows the design handoff — all sizes are fractions of card
 * width `W`, so cards scale cleanly from in-hand (~64–80dp) to focus
 * size (~200dp). Aspect is locked at W : 1.4·W.
 */

enum class CardSuit(val glyph: String, val wire: String) {
    SPADES("♠", "spades"),
    HEARTS("♥", "hearts"),
    DIAMONDS("♦", "diamonds"),
    CLUBS("♣", "clubs");

    val ink: Color get() = when (this) {
        SPADES, CLUBS -> CardTokens.inkBlack
        HEARTS, DIAMONDS -> CardTokens.inkRed
    }

    companion object {
        fun fromWire(s: String): CardSuit? =
            entries.firstOrNull { it.wire.equals(s, ignoreCase = true) }
    }
}

object CardTokens {
    val noirBg = Color(0xFF101013)
    val noirBorder = Color(0x1AFFFFFF)
    val inkBlack = Color(0xFFF4F4F6)
    val inkRed = Color(0xFFFF3D5A)
    val wildAccent = Color(0xFFFF2E88)
    val wildAccentSoft = Color(0x1EFF2E88)
    val wildAccentRing = Color(0x59FF2E88)
    val bombBorder = Color(0x8CFF2E88)
}

data class PipPosition(val xPct: Double, val yPct: Double, val rotate: Boolean = false)

object PipLayout {
    fun positions(rank: Int): List<PipPosition> = when (rank) {
        2 -> listOf(p(50,15), p(50,85,true))
        3 -> listOf(p(50,15), p(50,50), p(50,85,true))
        4 -> listOf(p(28,15), p(72,15), p(28,85,true), p(72,85,true))
        5 -> listOf(p(28,15), p(72,15), p(50,50),
                    p(28,85,true), p(72,85,true))
        6 -> listOf(p(28,15), p(72,15), p(28,50), p(72,50),
                    p(28,85,true), p(72,85,true))
        7 -> listOf(p(28,15), p(72,15), p(50,30),
                    p(28,50), p(72,50),
                    p(28,85,true), p(72,85,true))
        8 -> listOf(p(28,15), p(72,15), p(50,30),
                    p(28,50), p(72,50), p(50,70,true),
                    p(28,85,true), p(72,85,true))
        9 -> listOf(p(28,12), p(72,12), p(28,36), p(72,36),
                    p(50,50),
                    p(28,64,true), p(72,64,true),
                    p(28,88,true), p(72,88,true))
        10 -> listOf(p(28,10), p(72,10), p(50,24),
                     p(28,38), p(72,38),
                     p(28,62,true), p(72,62,true), p(50,76,true),
                     p(28,90,true), p(72,90,true))
        else -> emptyList()
    }
    private fun p(x: Int, y: Int, r: Boolean = false) =
        PipPosition(x.toDouble(), y.toDouble(), r)
}

/** Card frame — 1 : 1.4 aspect, 6% corner radius, soft shadow. */
@Composable
fun CardFrame(
    width: androidx.compose.ui.unit.Dp,
    background: Color = CardTokens.noirBg,
    borderColor: Color = CardTokens.noirBorder,
    content: @Composable BoxScope.() -> Unit,
) {
    val height = width * 1.4f
    val radius = (width.value * 0.06f).dp.coerceAtLeast(6.dp)
    Box(
        modifier = Modifier
            .size(width, height)
            .shadow(8.dp, RoundedCornerShape(radius), clip = false)
            .clip(RoundedCornerShape(radius))
            .background(background)
            .border(1.dp, borderColor, RoundedCornerShape(radius)),
        content = content,
    )
}

/** Suit glyph rendered as flat text (not emoji). */
@Composable
fun SuitGlyph(
    suit: CardSuit,
    sizeDp: androidx.compose.ui.unit.Dp,
    color: Color = suit.ink,
    rotated: Boolean = false,
) {
    Text(
        text = suit.glyph,
        color = color,
        style = TextStyle(
            fontFamily = FontFamily.SansSerif,
            fontWeight = FontWeight.Bold,
            fontSize = sizeDp.value.sp,
            textAlign = TextAlign.Center,
        ),
        modifier = if (rotated) Modifier.rotate(180f) else Modifier,
    )
}

@Composable
private fun WildDot(sizeDp: androidx.compose.ui.unit.Dp) {
    Box(
        Modifier
            .size(sizeDp)
            .background(CardTokens.wildAccent, androidx.compose.foundation.shape.CircleShape),
    )
}

/** Corner index — rank, suit, optional wild dot. */
@Composable
fun CornerIndex(
    rank: Int,
    suit: CardSuit,
    cardWidth: androidx.compose.ui.unit.Dp,
    alignment: Alignment = Alignment.TopStart,
    showWild: Boolean = false,
) {
    val rankSize = (cardWidth.value * 0.12f).coerceAtLeast(12f).dp
    val suitSize = (rankSize.value * 0.85f).dp
    val padIn = (rankSize.value * 0.55f).dp
    val padOut = (rankSize.value * 0.45f).dp

    val padding = when (alignment) {
        Alignment.TopStart -> PaddingValues(top = padOut, start = padIn)
        Alignment.BottomEnd -> PaddingValues(bottom = padOut, end = padIn)
        else -> PaddingValues(0.dp)
    }

    Box(modifier = Modifier.padding(padding)) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = if (alignment == Alignment.BottomEnd) Modifier.rotate(180f) else Modifier,
        ) {
            Text(
                text = rankShort(rank),
                color = suit.ink,
                style = TextStyle(
                    fontFamily = FontFamily.SansSerif,
                    fontWeight = FontWeight.ExtraBold,
                    fontSize = rankSize.value.sp,
                    letterSpacing = (-rankSize.value * 0.04f).sp,
                ),
            )
            Text(
                text = suit.glyph,
                color = suit.ink,
                style = TextStyle(
                    fontFamily = FontFamily.SansSerif,
                    fontWeight = FontWeight.Bold,
                    fontSize = suitSize.value.sp,
                ),
                modifier = Modifier.padding(top = (rankSize.value * 0.05f).dp),
            )
            if (showWild) {
                Box(modifier = Modifier.padding(top = (rankSize.value * 0.15f).dp)) {
                    WildDot(sizeDp = (rankSize.value * 0.30f).dp)
                }
            }
        }
    }
}

/** Pip arrangement for ranks 2–10. */
@Composable
fun PipArrangement(rank: Int, suit: CardSuit, cardWidth: androidx.compose.ui.unit.Dp) {
    val pipSize = (cardWidth.value * 0.13f).coerceAtLeast(10f).dp
    val cardHeight = cardWidth * 1.4f
    val insetX = cardWidth * 0.15f
    val insetY = cardHeight * 0.18f
    val areaW = cardWidth - insetX * 2
    val areaH = cardHeight - insetY * 2
    val positions = PipLayout.positions(rank)
    Box(modifier = Modifier.fillMaxSize()) {
        for (p in positions) {
            val x = insetX + areaW * (p.xPct / 100.0).toFloat()
            val y = insetY + areaH * (p.yPct / 100.0).toFloat()
            Box(
                modifier = Modifier
                    .padding(start = x - pipSize / 2, top = y - pipSize / 2)
                    .rotate(if (p.rotate) 180f else 0f),
            ) {
                Text(
                    text = suit.glyph,
                    color = suit.ink,
                    style = TextStyle(
                        fontFamily = FontFamily.SansSerif,
                        fontWeight = FontWeight.Bold,
                        fontSize = pipSize.value.sp,
                    ),
                )
            }
        }
    }
}

@Composable
fun AceCenter(
    suit: CardSuit,
    cardWidth: androidx.compose.ui.unit.Dp,
    accent: Boolean = false,
) {
    val size = (cardWidth.value * 0.55f).dp
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        if (accent) {
            Box(
                Modifier
                    .size((size.value * 1.35f).dp)
                    .background(CardTokens.wildAccentSoft,
                                androidx.compose.foundation.shape.CircleShape)
                    .border(1.dp, CardTokens.wildAccentRing,
                            androidx.compose.foundation.shape.CircleShape),
            )
        }
        Text(
            text = suit.glyph,
            color = suit.ink,
            style = TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Bold,
                fontSize = size.value.sp,
            ),
        )
    }
}

@Composable
fun CourtMonogram(rank: Int, suit: CardSuit, cardWidth: androidx.compose.ui.unit.Dp) {
    val letterSize = (cardWidth.value * 0.62f).dp
    val suitSize = (letterSize.value * 0.34f).dp
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy((letterSize.value * 0.08f).dp),
        ) {
            Text(suit.glyph, color = suit.ink, style = TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Bold,
                fontSize = suitSize.value.sp,
            ))
            Text(rankLetter(rank), color = suit.ink, style = TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.ExtraBold,
                fontSize = letterSize.value.sp,
                letterSpacing = (-letterSize.value * 0.06f).sp,
            ))
            Text(suit.glyph, color = suit.ink, style = TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.Bold,
                fontSize = suitSize.value.sp,
            ), modifier = Modifier.rotate(180f))
        }
    }
}

/** Noir front-face card. Dispatches on rank. */
@Composable
fun NoirCardFace(
    rank: Int,
    suit: CardSuit,
    width: androidx.compose.ui.unit.Dp,
    wildAccent: Boolean = false,
) {
    val isEight = rank == 8 && wildAccent
    CardFrame(width = width) {
        when {
            rank == 1 || rank == 14 -> AceCenter(suit, width, accent = isEight)
            rank in 11..13 -> CourtMonogram(rank, suit, width)
            else -> PipArrangement(rank, suit, width)
        }
        Box(modifier = Modifier.align(Alignment.TopStart)) {
            CornerIndex(rank, suit, width, alignment = Alignment.TopStart, showWild = isEight)
        }
        Box(modifier = Modifier.align(Alignment.BottomEnd)) {
            CornerIndex(rank, suit, width, alignment = Alignment.BottomEnd, showWild = isEight)
        }
    }
}

/** Grid card back — same on every game. */
@Composable
fun GridCardBack(width: androidx.compose.ui.unit.Dp) {
    CardFrame(width = width, background = Color.Black) {
        val density = LocalDensity.current
        Box(modifier = Modifier
            .fillMaxSize()
            .drawBehind {
                val step = size.width * 0.10f
                val dot = size.width * 0.025f
                val cols = 8
                val rows = (((size.height - step * 2) / step)).toInt() + 1
                val cR = rows / 2
                val cC = cols / 2
                for (r in 0 until rows) {
                    for (c in 0 until cols) {
                        val accent = (r == cR && c == cC)
                            || (r == cR - 2 && c == cC - 2)
                            || (r == cR - 2 && c == cC + 1)
                            || (r == cR + 2 && c == cC - 2)
                            || (r == cR + 2 && c == cC + 1)
                        val color = if (accent) CardTokens.wildAccent
                                    else Color.White.copy(alpha = 0.45f)
                        drawCircle(
                            color = color,
                            radius = dot / 2,
                            center = Offset(step + c * step + dot / 2,
                                            step + r * step + dot / 2),
                        )
                    }
                }
            })
    }
}

// ----- Bluff Market specifics -----

/** Point card — big numeral, 20pt cards get magenta border + peak ribbon. */
@Composable
fun BluffPointCard(value: Int, width: androidx.compose.ui.unit.Dp) {
    val isPeak = value >= 20
    CardFrame(
        width = width,
        borderColor = if (isPeak) CardTokens.bombBorder else CardTokens.noirBorder,
    ) {
        // Hero numeral centered.
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            val heroSize = if (value >= 10) width.value * 0.78f else width.value * 0.92f
            Text(
                text = "$value",
                color = CardTokens.inkBlack,
                style = TextStyle(
                    fontFamily = FontFamily.SansSerif,
                    fontWeight = FontWeight.ExtraBold,
                    fontSize = heroSize.sp,
                    letterSpacing = (-heroSize * 0.07f).sp,
                ),
            )
        }
        // Corner labels.
        Box(modifier = Modifier.align(Alignment.TopStart)
            .padding(top = (width.value * 0.07f).dp, start = (width.value * 0.09f).dp)) {
            PointCornerLabel(value)
        }
        Box(modifier = Modifier.align(Alignment.BottomEnd)
            .padding(bottom = (width.value * 0.07f).dp, end = (width.value * 0.09f).dp)
            .rotate(180f)) {
            PointCornerLabel(value)
        }
        if (isPeak) {
            Box(modifier = Modifier.align(Alignment.BottomCenter)
                .padding(bottom = (width.value * 0.30f).dp)) {
                Text(
                    text = "PEAK VALUE",
                    color = CardTokens.wildAccent,
                    style = TextStyle(
                        fontFamily = FontFamily.Monospace,
                        fontWeight = FontWeight.Medium,
                        fontSize = (width.value * 0.055f).sp,
                        letterSpacing = (width.value * 0.055f * 0.18f).sp,
                    ),
                )
            }
        }
    }
}

@Composable
private fun PointCornerLabel(value: Int) {
    Column {
        Text(
            text = "$value",
            color = CardTokens.inkBlack,
            style = TextStyle(
                fontFamily = FontFamily.SansSerif,
                fontWeight = FontWeight.ExtraBold,
                fontSize = labelRankSize.sp,
                letterSpacing = (-labelRankSize * 0.04f).sp,
            ),
        )
        Text(
            text = if (value == 1) "PT" else "PTS",
            color = CardTokens.inkBlack.copy(alpha = 0.55f),
            style = TextStyle(
                fontFamily = FontFamily.Monospace,
                fontWeight = FontWeight.Medium,
                fontSize = labelUnitSize.sp,
                letterSpacing = (labelUnitSize * 0.10f).sp,
            ),
        )
    }
}

// These mirror width * 0.15 / 0.065 but are computed at composition time via
// the closest enclosing width. We default to a single base used by the
// PointCornerLabel helper; callers pass an explicit width override via the
// surrounding box's width — here we use a sane reference size.
private const val labelRankSize: Float = 12f
private const val labelUnitSize: Float = 6f

/** Bomb card — concentric magenta rulings, ⚠ "CAUTION / −25 / BOMB". */
@Composable
fun BluffBombCard(width: androidx.compose.ui.unit.Dp) {
    CardFrame(width = width, borderColor = CardTokens.bombBorder) {
        // Inner ruling 1: solid magenta 35% at 7% inset.
        Box(modifier = Modifier
            .padding((width.value * 0.07f).dp)
            .fillMaxSize()
            .border(1.dp, CardTokens.wildAccent.copy(alpha = 0.35f),
                    RoundedCornerShape((width.value * 0.04f).dp)))
        // Inner ruling 2: dashed magenta 25% at 10% inset.
        Box(modifier = Modifier
            .padding((width.value * 0.10f).dp)
            .fillMaxSize()
            .drawBehind {
                val dashLen = size.width * 0.04f
                drawRoundRect(
                    color = CardTokens.wildAccent.copy(alpha = 0.25f),
                    size = Size(size.width, size.height),
                    style = Stroke(
                        width = 1.dp.toPx(),
                        pathEffect = PathEffect.dashPathEffect(floatArrayOf(dashLen, dashLen), 0f),
                    ),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(
                        (width.value * 0.035f).dp.toPx(),
                        (width.value * 0.035f).dp.toPx(),
                    ),
                )
            })

        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text("CAUTION",
                 color = CardTokens.wildAccent.copy(alpha = 0.70f),
                 style = TextStyle(
                     fontFamily = FontFamily.Monospace,
                     fontWeight = FontWeight.Medium,
                     fontSize = (width.value * 0.085f).sp,
                     letterSpacing = (width.value * 0.085f * 0.30f).sp,
                 ))
            Spacer(Modifier.height((width.value * 0.04f).dp))
            Text("−25",
                 color = CardTokens.inkBlack,
                 style = TextStyle(
                     fontFamily = FontFamily.SansSerif,
                     fontWeight = FontWeight.ExtraBold,
                     fontSize = (width.value * 0.55f).sp,
                     letterSpacing = (-(width.value * 0.55f) * 0.07f).sp,
                 ))
            Spacer(Modifier.height((width.value * 0.04f).dp))
            Text("BOMB",
                 color = CardTokens.wildAccent,
                 style = TextStyle(
                     fontFamily = FontFamily.SansSerif,
                     fontWeight = FontWeight.ExtraBold,
                     fontSize = (width.value * 0.15f).sp,
                     letterSpacing = (width.value * 0.15f * 0.10f).sp,
                 ))
        }
        Box(modifier = Modifier.align(Alignment.TopStart)
            .padding(top = (width.value * 0.07f).dp, start = (width.value * 0.09f).dp)) {
            BombCornerLabel()
        }
        Box(modifier = Modifier.align(Alignment.BottomEnd)
            .padding(bottom = (width.value * 0.07f).dp, end = (width.value * 0.09f).dp)
            .rotate(180f)) {
            BombCornerLabel()
        }
    }
}

@Composable
private fun BombCornerLabel() {
    Column {
        Text("−25",
             color = CardTokens.inkRed,
             style = TextStyle(
                 fontFamily = FontFamily.SansSerif,
                 fontWeight = FontWeight.ExtraBold,
                 fontSize = labelRankSize.sp,
                 letterSpacing = (-labelRankSize * 0.04f).sp,
             ))
        Text("BOMB",
             color = CardTokens.inkRed.copy(alpha = 0.85f),
             style = TextStyle(
                 fontFamily = FontFamily.Monospace,
                 fontWeight = FontWeight.Medium,
                 fontSize = labelUnitSize.sp,
                 letterSpacing = (labelUnitSize * 0.20f).sp,
             ))
    }
}

// ----- Helpers -----

fun rankShort(r: Int): String = when (r) {
    1, 14 -> "A"
    11 -> "J"
    12 -> "Q"
    13 -> "K"
    else -> "$r"
}

fun rankLetter(r: Int): String = when (r) {
    11 -> "J"; 12 -> "Q"; 13 -> "K"; else -> "?"
}
