import SpriteKit
import GameplayKit

final class PlayerEntity: GKEntity {
    let sprite: SpriteComponent
    let agent: AgentComponent

    override init() {
        sprite = SpriteComponent(color: .systemBlue, radius: 18)
        agent = AgentComponent()
        super.init()
        agent.sprite = sprite.node
        agent.maxSpeed = 200
        agent.maxAcceleration = 400
        addComponent(sprite)
        addComponent(agent)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func moveTowards(_ point: CGPoint) {
        let target = GKGraphNode2D(point: SIMD2<Float>(Float(point.x), Float(point.y)))
        agent.behavior = GKBehavior(goal: GKGoal(toSeekAgent: AgentComponent.proxy(at: target.position)), weight: 1)
    }
}

extension AgentComponent {
    static func proxy(at position: SIMD2<Float>) -> GKAgent2D {
        let proxy = GKAgent2D()
        proxy.position = position
        proxy.mass = 1
        return proxy
    }
}
