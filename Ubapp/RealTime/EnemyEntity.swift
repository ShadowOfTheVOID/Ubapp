import SpriteKit
import GameplayKit

final class EnemyEntity: GKEntity {
    let sprite: SpriteComponent
    let agent: AgentComponent
    weak var target: SKNode?
    var chaseProxy: GKAgent2D?
    private(set) var stateMachine: GKStateMachine!

    init(target: SKNode) {
        sprite = SpriteComponent(color: .systemGray, radius: 14)
        agent = AgentComponent()
        self.target = target
        super.init()
        agent.sprite = sprite.node
        agent.maxSpeed = 110
        agent.maxAcceleration = 200
        addComponent(sprite)
        addComponent(agent)
        stateMachine = GKStateMachine(states: [WanderState(enemy: self), ChaseState(enemy: self)])
        stateMachine.enter(WanderState.self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func update(deltaTime seconds: TimeInterval) {
        super.update(deltaTime: seconds)
        stateMachine.update(deltaTime: seconds)
    }
}
