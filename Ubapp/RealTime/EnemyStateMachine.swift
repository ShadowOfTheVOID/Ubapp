import SpriteKit
import GameplayKit

class EnemyState: GKState {
    unowned let enemy: EnemyEntity
    init(enemy: EnemyEntity) { self.enemy = enemy }
}

final class WanderState: EnemyState {
    override func didEnter(from previousState: GKState?) {
        enemy.agent.behavior = GKBehavior(goal: GKGoal(toWander: 60), weight: 1)
        (enemy.component(ofType: SpriteComponent.self))?.node.fillColor = .systemGray
    }

    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == ChaseState.self
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard let target = enemy.target else { return }
        let dx = Float(target.position.x) - enemy.agent.position.x
        let dy = Float(target.position.y) - enemy.agent.position.y
        if (dx * dx + dy * dy) < 250 * 250 {
            stateMachine?.enter(ChaseState.self)
        }
    }
}

final class ChaseState: EnemyState {
    override func didEnter(from previousState: GKState?) {
        guard let target = enemy.target else { return }
        let proxy = AgentComponent.proxy(at: SIMD2<Float>(Float(target.position.x), Float(target.position.y)))
        enemy.chaseProxy = proxy
        enemy.agent.behavior = GKBehavior(goal: GKGoal(toSeekAgent: proxy), weight: 1)
        (enemy.component(ofType: SpriteComponent.self))?.node.fillColor = .systemRed
    }

    override func isValidNextState(_ stateClass: AnyClass) -> Bool {
        stateClass == WanderState.self
    }

    override func update(deltaTime seconds: TimeInterval) {
        guard let target = enemy.target, let proxy = enemy.chaseProxy else { return }
        proxy.position = SIMD2<Float>(Float(target.position.x), Float(target.position.y))
        let dx = proxy.position.x - enemy.agent.position.x
        let dy = proxy.position.y - enemy.agent.position.y
        if (dx * dx + dy * dy) > 400 * 400 {
            stateMachine?.enter(WanderState.self)
        }
    }
}
