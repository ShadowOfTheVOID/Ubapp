import SwiftUI

/// Single-device demo: a player (blue) seeks the last tap; four enemies
/// (red) wander, then switch to chase mode when they get close.
/// Pure SwiftUI Canvas + TimelineView — no game engine dependency.
struct RealtimeView: View {
    @State private var world = RealtimeWorld()

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                world.tick(now: context.date, bounds: size)
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                // Player
                ctx.fill(Path(ellipseIn: CGRect(x: world.player.x - 12, y: world.player.y - 12,
                                                 width: 24, height: 24)),
                         with: .color(.blue))
                // Enemies
                for e in world.enemies {
                    let color: Color = e.chasing ? .red : .orange
                    ctx.fill(Path(ellipseIn: CGRect(x: e.position.x - 10, y: e.position.y - 10,
                                                     width: 20, height: 20)),
                             with: .color(color))
                }
            }
            .background(Color.black)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in world.target = .init(x: g.location.x, y: g.location.y) })
            .overlay(alignment: .topLeading) {
                Text("Drag to move. Enemies wander, then chase.")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                    .padding(12)
            }
        }
        .ubappChrome()
        .navigationTitle("Real-time")
        .ignoresSafeArea(edges: .bottom)
    }
}

struct CGVec { var x: CGFloat = 0; var y: CGFloat = 0
    static let zero = CGVec()
    func length() -> CGFloat { sqrt(x * x + y * y) }
    func normalized() -> CGVec {
        let l = length(); return l == 0 ? .zero : CGVec(x: x / l, y: y / l)
    }
    static func - (a: CGVec, b: CGVec) -> CGVec { .init(x: a.x - b.x, y: a.y - b.y) }
    static func + (a: CGVec, b: CGVec) -> CGVec { .init(x: a.x + b.x, y: a.y + b.y) }
    static func * (a: CGVec, k: CGFloat) -> CGVec { .init(x: a.x * k, y: a.y * k) }
}

final class RealtimeWorld {
    var player = CGVec(x: 200, y: 400)
    var target = CGVec(x: 200, y: 400)
    var enemies: [Enemy] = []
    private var lastTick: Date?
    private var bounds: CGSize = .zero
    private var spawned = false

    final class Enemy {
        var position: CGVec
        var heading: CGVec
        var chasing = false
        init(position: CGVec) {
            self.position = position
            let angle = Double.random(in: 0..<(2 * .pi))
            heading = CGVec(x: cos(angle), y: sin(angle))
        }
    }

    func tick(now: Date, bounds: CGSize) {
        self.bounds = bounds
        if !spawned, bounds.width > 0 {
            seed(); spawned = true
        }
        let dt = lastTick.map { CGFloat(now.timeIntervalSince($0)) } ?? 0
        lastTick = now
        let clampedDt = min(dt, 0.05)

        // Player seeks target.
        let toTarget = target - player
        if toTarget.length() > 2 {
            player = player + toTarget.normalized() * (180 * clampedDt)
        }

        // Enemies wander or chase.
        for e in enemies {
            let toPlayer = player - e.position
            e.chasing = toPlayer.length() < 160
            if e.chasing && toPlayer.length() > 1 {
                e.heading = toPlayer.normalized()
            } else {
                // Small random wobble.
                e.heading.x += CGFloat.random(in: -0.05...0.05)
                e.heading.y += CGFloat.random(in: -0.05...0.05)
                e.heading = e.heading.normalized()
            }
            let speed: CGFloat = e.chasing ? 140 : 60
            e.position = e.position + e.heading * (speed * clampedDt)
            // Bounce off walls.
            if e.position.x < 12 || e.position.x > bounds.width - 12 { e.heading.x = -e.heading.x }
            if e.position.y < 12 || e.position.y > bounds.height - 12 { e.heading.y = -e.heading.y }
            e.position.x = max(12, min(bounds.width - 12, e.position.x))
            e.position.y = max(12, min(bounds.height - 12, e.position.y))
        }
    }

    private func seed() {
        player = CGVec(x: bounds.width / 2, y: bounds.height / 2)
        target = player
        enemies = (0..<4).map { _ in
            Enemy(position: .init(
                x: CGFloat.random(in: 30...(bounds.width - 30)),
                y: CGFloat.random(in: 30...(bounds.height - 30))))
        }
    }
}
