import SwiftUI

/// Shared Noir card system used by Crazy Eights, Cheat, President, and
/// the face-down Grid back used by every game (including Bluff Market).
///
/// Geometry follows the design handoff — all sizes are fractions of the
/// card width `W`, so cards scale cleanly from in-hand (~64–80pt) to
/// focus size (~200pt). Aspect is locked at W : 1.4·W.
///
/// Token reference:
///   card.noir.bg     #101013
///   card.noir.border rgba(255,255,255,0.10)
///   suit.ink.black   #F4F4F6  (spades & clubs on noir face)
///   suit.ink.red     #FF3D5A  (hearts & diamonds on noir face)
///   wild.accent      #FF2E88  (Crazy 8s wild dot, Bomb framing, peak ribbon)

enum CardSuit: String, CaseIterable {
    case spades, hearts, diamonds, clubs
    var glyph: String {
        switch self { case .spades: "♠"; case .hearts: "♥"; case .diamonds: "♦"; case .clubs: "♣" }
    }
    /// Noir-face ink color.
    var ink: Color {
        switch self {
        case .spades, .clubs: CardTokens.inkBlack
        case .hearts, .diamonds: CardTokens.inkRed
        }
    }
    /// Wire string used by browser/server protocols ("spades" etc.).
    var wire: String { rawValue }
    static func fromWire(_ s: String) -> CardSuit? { CardSuit(rawValue: s) }
}

enum CardTokens {
    static let noirBg = Color(red: 0x10/255.0, green: 0x10/255.0, blue: 0x13/255.0)
    static let noirBorder = Color.white.opacity(0.10)
    static let inkBlack = Color(red: 0xF4/255.0, green: 0xF4/255.0, blue: 0xF6/255.0)
    static let inkRed = Color(red: 1.00, green: 0x3D/255.0, blue: 0x5A/255.0)
    static let wildAccent = Color(red: 1.0, green: 0.180, blue: 0.533) // #FF2E88
    /// Soft fill behind a wild Ace's center glyph.
    static let wildAccentSoft = Color(red: 1.0, green: 0.180, blue: 0.533, opacity: 0.12)
    static let wildAccentRing = Color(red: 1.0, green: 0.180, blue: 0.533, opacity: 0.35)
    static let bombBorder = Color(red: 1.0, green: 0.180, blue: 0.533, opacity: 0.55)
}

/// Pip layout table — positions in % within the inset pip area, with an
/// optional `rotate180` flag to flip bottom-half pips.
struct PipPosition {
    let xPct: Double
    let yPct: Double
    let rotate: Bool
    init(_ x: Double, _ y: Double, _ r: Bool = false) {
        xPct = x; yPct = y; rotate = r
    }
}

enum PipLayout {
    static func positions(for rank: Int) -> [PipPosition] {
        switch rank {
        case 2: return [.init(50,15), .init(50,85,true)]
        case 3: return [.init(50,15), .init(50,50), .init(50,85,true)]
        case 4: return [.init(28,15), .init(72,15), .init(28,85,true), .init(72,85,true)]
        case 5: return [.init(28,15), .init(72,15), .init(50,50),
                        .init(28,85,true), .init(72,85,true)]
        case 6: return [.init(28,15), .init(72,15), .init(28,50), .init(72,50),
                        .init(28,85,true), .init(72,85,true)]
        case 7: return [.init(28,15), .init(72,15), .init(50,30),
                        .init(28,50), .init(72,50),
                        .init(28,85,true), .init(72,85,true)]
        case 8: return [.init(28,15), .init(72,15), .init(50,30),
                        .init(28,50), .init(72,50), .init(50,70,true),
                        .init(28,85,true), .init(72,85,true)]
        case 9: return [.init(28,12), .init(72,12), .init(28,36), .init(72,36),
                        .init(50,50),
                        .init(28,64,true), .init(72,64,true),
                        .init(28,88,true), .init(72,88,true)]
        case 10: return [.init(28,10), .init(72,10), .init(50,24),
                         .init(28,38), .init(72,38),
                         .init(28,62,true), .init(72,62,true), .init(50,76,true),
                         .init(28,90,true), .init(72,90,true)]
        default: return []
        }
    }
}

private extension PipPosition {
    init(_ x: Int, _ y: Int, _ r: Bool = false) { self.init(Double(x), Double(y), r) }
}

/// Noir card frame — 1 : 1.4 aspect, 6% corner radius, soft inner highlight.
/// Children are absolutely positioned via overlay alignment.
struct CardFrame<Content: View>: View {
    let width: CGFloat
    var background: Color = CardTokens.noirBg
    var borderColor: Color = CardTokens.noirBorder
    /// 0–1, additional border width fraction (defaults to a 1pt hairline).
    var borderWidthPt: CGFloat = 1
    let content: () -> Content

    init(width: CGFloat, background: Color = CardTokens.noirBg,
         borderColor: Color = CardTokens.noirBorder, borderWidthPt: CGFloat = 1,
         @ViewBuilder content: @escaping () -> Content) {
        self.width = width; self.background = background
        self.borderColor = borderColor; self.borderWidthPt = borderWidthPt
        self.content = content
    }

    var body: some View {
        let h = width * 1.4
        let r = max(6, width * 0.06)
        ZStack {
            RoundedRectangle(cornerRadius: r)
                .fill(background)
            content()
            RoundedRectangle(cornerRadius: r)
                .strokeBorder(borderColor, lineWidth: borderWidthPt)
        }
        .frame(width: width, height: h)
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
    }
}

/// Suit glyph rendered as a flat text symbol — never the emoji variant.
struct SuitGlyph: View {
    let suit: CardSuit
    let size: CGFloat
    var color: Color?
    var rotated: Bool = false

    var body: some View {
        Text(suit.glyph)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color ?? suit.ink)
            .rotationEffect(.degrees(rotated ? 180 : 0))
    }
}

/// Magenta wild dot rendered under the corner index suit on Crazy 8s' 8s.
struct WildDot: View {
    let size: CGFloat
    var body: some View {
        Circle().fill(CardTokens.wildAccent)
            .frame(width: size, height: size)
    }
}

/// Corner index — rank glyph, suit glyph below, optional wild dot.
/// `alignment = .topLeading` for top-left; `.bottomTrailing` rotates 180°.
struct CornerIndex: View {
    let rank: Int
    let suit: CardSuit
    let cardWidth: CGFloat
    var alignment: Alignment = .topLeading
    var showWild: Bool = false

    var body: some View {
        let rankSize = max(12, cardWidth * 0.12)
        let suitSize = rankSize * 0.85
        VStack(alignment: .center, spacing: rankSize * 0.05) {
            Text(rankShort(rank))
                .font(.system(size: rankSize, weight: .heavy))
                .tracking(-rankSize * 0.04)
                .foregroundStyle(suit.ink)
            Text(suit.glyph)
                .font(.system(size: suitSize, weight: .bold))
                .foregroundStyle(suit.ink)
            if showWild { WildDot(size: rankSize * 0.30) }
        }
        .lineLimit(1)
        .fixedSize()
        .rotationEffect(.degrees(alignment == .bottomTrailing ? 180 : 0))
        .padding(EdgeInsets(
            top: alignment == .topLeading ? rankSize * 0.45 : 0,
            leading: alignment == .topLeading ? rankSize * 0.55 : 0,
            bottom: alignment == .bottomTrailing ? rankSize * 0.45 : 0,
            trailing: alignment == .bottomTrailing ? rankSize * 0.55 : 0))
    }
}

/// Pip arrangement for ranks 2–10.
struct PipArrangement: View {
    let rank: Int
    let suit: CardSuit
    let cardWidth: CGFloat

    var body: some View {
        let pipSize = max(10, cardWidth * 0.13)
        let cardHeight = cardWidth * 1.4
        // Pip area = inset 15% W on left/right, 18% H on top/bottom.
        let insetX = cardWidth * 0.15
        let insetY = cardHeight * 0.18
        let areaW = cardWidth - insetX * 2
        let areaH = cardHeight - insetY * 2
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(PipLayout.positions(for: rank).enumerated()), id: \.offset) { _, p in
                Text(suit.glyph)
                    .font(.system(size: pipSize, weight: .bold))
                    .foregroundStyle(suit.ink)
                    .rotationEffect(.degrees(p.rotate ? 180 : 0))
                    .position(x: insetX + areaW * p.xPct / 100.0,
                              y: insetY + areaH * p.yPct / 100.0)
            }
        }
    }
}

/// Single large suit glyph centered. Used for Aces.
struct AceCenter: View {
    let suit: CardSuit
    let cardWidth: CGFloat
    var accent: Bool = false

    var body: some View {
        let size = cardWidth * 0.55
        ZStack {
            if accent {
                Circle()
                    .fill(CardTokens.wildAccentSoft)
                    .frame(width: size * 1.35, height: size * 1.35)
                    .overlay(Circle().stroke(CardTokens.wildAccentRing, lineWidth: 1))
            }
            Text(suit.glyph)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(suit.ink)
        }
    }
}

/// Court monogram — small suit, big rank letter, small suit rotated.
struct CourtMonogram: View {
    let rank: Int
    let suit: CardSuit
    let cardWidth: CGFloat

    var body: some View {
        let letterSize = cardWidth * 0.62
        let suitSize = letterSize * 0.34
        VStack(spacing: letterSize * 0.08) {
            Text(suit.glyph)
                .font(.system(size: suitSize, weight: .bold))
                .foregroundStyle(suit.ink)
            Text(rankLetter(rank))
                .font(.system(size: letterSize, weight: .heavy))
                .tracking(-letterSize * 0.06)
                .foregroundStyle(suit.ink)
            Text(suit.glyph)
                .font(.system(size: suitSize, weight: .bold))
                .foregroundStyle(suit.ink)
                .rotationEffect(.degrees(180))
        }
    }
}

/// Noir front-face card. Dispatches on rank: Ace → AceCenter,
/// J/Q/K → CourtMonogram, else → PipArrangement.
struct NoirCardFace: View {
    let rank: Int
    let suit: CardSuit
    let width: CGFloat
    var wildAccent: Bool = false

    var body: some View {
        let isEight = rank == 8 && wildAccent
        CardFrame(width: width) {
            content(isEight: isEight)
            CornerIndex(rank: rank, suit: suit, cardWidth: width,
                        alignment: .topLeading, showWild: isEight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            CornerIndex(rank: rank, suit: suit, cardWidth: width,
                        alignment: .bottomTrailing, showWild: isEight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    @ViewBuilder private func content(isEight: Bool) -> some View {
        if rank == 1 || rank == 14 {
            AceCenter(suit: suit, cardWidth: width, accent: isEight)
        } else if rank >= 11 && rank <= 13 {
            CourtMonogram(rank: rank, suit: suit, cardWidth: width)
        } else {
            PipArrangement(rank: rank, suit: suit, cardWidth: width)
        }
    }
}

/// Grid card back — same on every game so face-down cards are
/// indistinguishable (critical for Bluff Market's hidden Bomb).
struct GridCardBack: View {
    let width: CGFloat

    var body: some View {
        CardFrame(width: width, background: .black) {
            let cardHeight = width * 1.4
            let step = width * 0.10
            let dot = width * 0.025
            let cols = 8
            let rows = Int(((cardHeight - step * 2) / step).rounded(.down)) + 1
            let cR = rows / 2
            let cC = cols / 2
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(0..<rows, id: \.self) { r in
                    ForEach(0..<cols, id: \.self) { c in
                        let accent = (r == cR && c == cC)
                            || (r == cR - 2 && c == cC - 2)
                            || (r == cR - 2 && c == cC + 1)
                            || (r == cR + 2 && c == cC - 2)
                            || (r == cR + 2 && c == cC + 1)
                        Circle()
                            .fill(accent ? CardTokens.wildAccent : Color.white.opacity(0.45))
                            .frame(width: dot, height: dot)
                            .position(x: step + CGFloat(c) * step + dot / 2,
                                      y: step + CGFloat(r) * step + dot / 2)
                    }
                }
            }
        }
    }
}

// MARK: - Bluff Market specifics

/// Point card — big white numeral on the Noir face. 20pt cards carry a
/// magenta border + "peak value" ribbon.
struct BluffPointCard: View {
    let value: Int
    let width: CGFloat

    var body: some View {
        let isPeak = value >= 20
        CardFrame(width: width,
                  borderColor: isPeak ? CardTokens.bombBorder : CardTokens.noirBorder) {
            cornerLabel(alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            cornerLabel(alignment: .bottomTrailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            // Hero numeral
            Text("\(value)")
                .font(.system(size: value >= 10 ? width * 0.78 : width * 0.92, weight: .heavy))
                .tracking(-(width * 0.78) * 0.07)
                .foregroundStyle(CardTokens.inkBlack)
            if isPeak {
                VStack {
                    Spacer()
                    Text("PEAK VALUE")
                        .font(.system(size: width * 0.055, weight: .medium, design: .monospaced))
                        .tracking(width * 0.055 * 0.18)
                        .foregroundStyle(CardTokens.wildAccent)
                        .padding(.bottom, width * 0.30)
                }
            }
        }
    }

    @ViewBuilder
    private func cornerLabel(alignment: Alignment) -> some View {
        let rankSize = width * 0.15
        let unitSize = width * 0.065
        VStack(alignment: .leading, spacing: width * 0.02) {
            Text("\(value)")
                .font(.system(size: rankSize, weight: .heavy))
                .tracking(-rankSize * 0.04)
                .foregroundStyle(CardTokens.inkBlack)
            Text(value == 1 ? "PT" : "PTS")
                .font(.system(size: unitSize, weight: .medium, design: .monospaced))
                .tracking(unitSize * 0.10)
                .foregroundStyle(CardTokens.inkBlack.opacity(0.55))
        }
        .lineLimit(1)
        .fixedSize()
        .rotationEffect(.degrees(alignment == .bottomTrailing ? 180 : 0))
        .padding(EdgeInsets(
            top: alignment == .topLeading ? width * 0.07 : 0,
            leading: alignment == .topLeading ? width * 0.09 : 0,
            bottom: alignment == .bottomTrailing ? width * 0.07 : 0,
            trailing: alignment == .bottomTrailing ? width * 0.09 : 0))
    }
}

/// Bomb card — concentric magenta rulings, ⚠ "CAUTION / −25 / BOMB" stack.
struct BluffBombCard: View {
    let width: CGFloat

    var body: some View {
        CardFrame(width: width, borderColor: CardTokens.bombBorder) {
            // Inner concentric warning rulings.
            RoundedRectangle(cornerRadius: width * 0.04)
                .stroke(CardTokens.wildAccent.opacity(0.35), lineWidth: max(1, width * 0.006))
                .padding(width * 0.07)
            RoundedRectangle(cornerRadius: width * 0.035)
                .stroke(style: StrokeStyle(lineWidth: max(1, width * 0.006), dash: [width * 0.03]))
                .foregroundStyle(CardTokens.wildAccent.opacity(0.25))
                .padding(width * 0.10)

            cornerLabel(alignment: .topLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            cornerLabel(alignment: .bottomTrailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

            VStack(spacing: width * 0.04) {
                Text("CAUTION")
                    .font(.system(size: width * 0.085, weight: .medium, design: .monospaced))
                    .tracking(width * 0.085 * 0.30)
                    .foregroundStyle(CardTokens.wildAccent.opacity(0.70))
                Text("\u{2212}25")
                    .font(.system(size: width * 0.55, weight: .heavy))
                    .tracking(-(width * 0.55) * 0.07)
                    .foregroundStyle(CardTokens.inkBlack)
                Text("BOMB")
                    .font(.system(size: width * 0.15, weight: .heavy))
                    .tracking(width * 0.15 * 0.10)
                    .foregroundStyle(CardTokens.wildAccent)
            }
        }
    }

    @ViewBuilder
    private func cornerLabel(alignment: Alignment) -> some View {
        let rankSize = width * 0.12
        let unitSize = width * 0.065
        VStack(alignment: .leading, spacing: width * 0.02) {
            Text("\u{2212}25")
                .font(.system(size: rankSize, weight: .heavy))
                .tracking(-rankSize * 0.04)
                .foregroundStyle(CardTokens.inkRed)
            Text("BOMB")
                .font(.system(size: unitSize, weight: .medium, design: .monospaced))
                .tracking(unitSize * 0.20)
                .foregroundStyle(CardTokens.inkRed.opacity(0.85))
        }
        .lineLimit(1)
        .fixedSize()
        .rotationEffect(.degrees(alignment == .bottomTrailing ? 180 : 0))
        .padding(EdgeInsets(
            top: alignment == .topLeading ? width * 0.07 : 0,
            leading: alignment == .topLeading ? width * 0.09 : 0,
            bottom: alignment == .bottomTrailing ? width * 0.07 : 0,
            trailing: alignment == .bottomTrailing ? width * 0.09 : 0))
    }
}

// MARK: - Helpers

func rankShort(_ r: Int) -> String {
    switch r {
    case 1, 14: "A"
    case 11: "J"
    case 12: "Q"
    case 13: "K"
    default: "\(r)"
    }
}

func rankLetter(_ r: Int) -> String {
    switch r {
    case 11: "J"
    case 12: "Q"
    case 13: "K"
    default: "?"
    }
}
