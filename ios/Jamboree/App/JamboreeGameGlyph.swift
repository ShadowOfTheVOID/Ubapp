import SwiftUI

// Per-game abstract glyphs — square, in the same visual vocabulary as the
// cards (stripes, suits, faces). Each is a fixed `size`×`size` tile on a
// `surfaceHi` rounded background. Games without a bespoke mark fall back to
// an SF Symbol on the same tile.

enum GameGlyph: Equatable {
    case crazy8s, cheat, president, bluffMarket, mafia, werewolf, imposter
    case symbol(String)
}

struct GameGlyphView: View {
    let glyph: GameGlyph
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(UbappTheme.surfaceHi)
            content
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        switch glyph {
        case .crazy8s: crazy8s
        case .cheat: cheat
        case .president: president
        case .bluffMarket: bluffMarket
        case .mafia: mafia
        case .werewolf: werewolf
        case .imposter: imposter
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(UbappTheme.accent)
        }
    }

    // Splayed "8" with a magenta diagonal slash.
    private var crazy8s: some View {
        ZStack {
            Text("8")
                .font(.system(size: size * 0.7, weight: .black))
                .kerning(-size * 0.06)
                .foregroundStyle(.white)
            Rectangle()
                .fill(UbappTheme.accent)
                .frame(width: size * 1.2, height: size * 0.10)
                .rotationEffect(.degrees(-22))
                .position(x: size * 0.5, y: size * 0.55)
        }
    }

    // Three stacked face-down cards.
    private var cheat: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let w = size * 0.42, h = size * 0.56
                RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                    .fill(Color(white: 0.13))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                            .stroke(UbappTheme.lineStrong, lineWidth: 1),
                    )
                    .overlay(CardBackGrid().stroke(Color.white.opacity(0.18), lineWidth: 0.5).padding(w * 0.12))
                    .frame(width: w, height: h)
                    .rotationEffect(.degrees(Double(-6 + i * 6)))
                    .position(x: size * (0.20 + Double(i) * 0.06) + w / 2,
                              y: size * (0.22 + Double(i) * 0.04) + h / 2)
            }
        }
    }

    // Tier bars — president on top.
    private var president: some View {
        let inset = size * 0.16
        let bars: [(CGFloat, Color)] = [
            (0.95, UbappTheme.accent),
            (0.70, .white),
            (0.70, .white),
            (0.38, Color.white.opacity(0.45)),
        ]
        return VStack(alignment: .leading, spacing: size * 0.05) {
            ForEach(0..<bars.count, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(bars[i].1)
                    .frame(width: (size - inset * 2) * bars[i].0, height: size * 0.07)
            }
        }
        .frame(width: size - inset * 2, alignment: .leading)
    }

    // Fedora over a moon.
    private var mafia: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0xD8D2C5), Color(hex: 0x45402F)],
                    center: .init(x: 0.3, y: 0.3), startRadius: 0, endRadius: size * 0.3))
                .frame(width: size * 0.36, height: size * 0.36)
                .position(x: size * 0.74, y: size * 0.28)
            RoundedRectangle(cornerRadius: size * 0.05)
                .fill(UbappTheme.accent)
                .frame(width: size * 0.72, height: size * 0.10)
                .position(x: size * 0.50, y: size * 0.75)
            UnevenRoundedRectangle(topLeadingRadius: size * 0.06, topTrailingRadius: size * 0.06)
                .fill(UbappTheme.accent)
                .frame(width: size * 0.40, height: size * 0.22)
                .position(x: size * 0.50, y: size * 0.59)
            Rectangle()
                .fill(Color.black)
                .frame(width: size * 0.40, height: size * 0.04)
                .position(x: size * 0.50, y: size * 0.68)
        }
    }

    // Wolf head + magenta eyes + faint moon.
    private var werewolf: some View {
        ZStack {
            WolfHead()
                .fill(Color.white)
                .frame(width: size * 0.56, height: size * 0.48)
                .position(x: size * 0.5, y: size * 0.46)
            Ellipse().fill(UbappTheme.accent)
                .frame(width: size * 0.08, height: size * 0.06)
                .position(x: size * 0.36, y: size * 0.49)
            Ellipse().fill(UbappTheme.accent)
                .frame(width: size * 0.08, height: size * 0.06)
                .position(x: size * 0.64, y: size * 0.49)
            Circle().fill(Color.white.opacity(0.45))
                .frame(width: size * 0.18, height: size * 0.18)
                .position(x: size * 0.19, y: size * 0.19)
        }
    }

    // Speech bubble with "?".
    private var imposter: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                .fill(UbappTheme.accent)
                .frame(width: size * 0.72, height: size * 0.52)
                .overlay(
                    Text("?")
                        .font(.system(size: size * 0.42, weight: .black))
                        .kerning(-size * 0.06)
                        .foregroundStyle(UbappTheme.onAccent),
                )
                .position(x: size * 0.50, y: size * 0.42)
            TriangleDown()
                .fill(UbappTheme.accent)
                .frame(width: size * 0.20, height: size * 0.16)
                .position(x: size * 0.32, y: size * 0.70)
        }
    }

    // Trade arrows + bomb dot.
    private var bluffMarket: some View {
        ZStack {
            // up arrow
            Rectangle().fill(.white)
                .frame(width: size * 0.04, height: size * 0.40)
                .position(x: size * 0.24, y: size * 0.40)
            TriangleUp().fill(.white)
                .frame(width: size * 0.16, height: size * 0.16)
                .position(x: size * 0.24, y: size * 0.28)
            // down arrow
            Rectangle().fill(.white)
                .frame(width: size * 0.04, height: size * 0.40)
                .position(x: size * 0.70, y: size * 0.60)
            TriangleDown().fill(.white)
                .frame(width: size * 0.16, height: size * 0.16)
                .position(x: size * 0.70, y: size * 0.72)
            // bomb
            Circle().fill(UbappTheme.accent)
                .frame(width: size * 0.16, height: size * 0.16)
                .position(x: size * 0.74, y: size * 0.74)
        }
    }
}

// MARK: - Helper shapes

private struct TriangleUp: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

private struct TriangleDown: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

private struct WolfHead: Shape {
    // polygon(0 30%, 20% 0, 35% 25%, 65% 25%, 80% 0, 100% 30%, 100% 80%, 50% 100%, 0 80%)
    func path(in r: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (0, 0.30), (0.20, 0), (0.35, 0.25), (0.65, 0.25),
            (0.80, 0), (1, 0.30), (1, 0.80), (0.50, 1), (0, 0.80),
        ]
        return Path { p in
            for (i, pt) in pts.enumerated() {
                let point = CGPoint(x: r.minX + pt.0 * r.width, y: r.minY + pt.1 * r.height)
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
            p.closeSubpath()
        }
    }
}

private struct CardBackGrid: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            let step = max(r.width, r.height) / 5
            var x = r.minX
            while x <= r.maxX {
                p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY)); x += step
            }
            var y = r.minY
            while y <= r.maxY {
                p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y)); y += step
            }
        }
    }
}
