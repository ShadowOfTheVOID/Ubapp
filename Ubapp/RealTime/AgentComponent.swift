import SpriteKit
import GameplayKit

final class AgentComponent: GKAgent2D, GKAgentDelegate {
    weak var sprite: SKNode?

    override init() {
        super.init()
        delegate = self
        maxSpeed = 140
        maxAcceleration = 220
        radius = 16
        mass = 0.1
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func agentWillUpdate(_ agent: GKAgent) {
        guard let sprite else { return }
        position = SIMD2<Float>(Float(sprite.position.x), Float(sprite.position.y))
    }

    func agentDidUpdate(_ agent: GKAgent) {
        guard let sprite else { return }
        sprite.position = CGPoint(x: CGFloat(position.x), y: CGFloat(position.y))
        sprite.zRotation = CGFloat(rotation)
    }
}
