import SpriteKit
import GameplayKit

final class RealTimeScene: SKScene {
    private let player = PlayerEntity()
    private var enemies: [EnemyEntity] = []
    private var entities: [GKEntity] = []
    private var lastUpdate: TimeInterval = 0

    override func didMove(to view: SKView) {
        backgroundColor = .black
        scaleMode = .resizeFill

        addEntity(player)
        player.sprite.node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        player.agent.position = SIMD2<Float>(Float(size.width / 2), Float(size.height / 2))

        for _ in 0..<4 {
            let enemy = EnemyEntity(target: player.sprite.node)
            let x = CGFloat.random(in: 40...(size.width - 40))
            let y = CGFloat.random(in: 40...(size.height - 40))
            enemy.sprite.node.position = CGPoint(x: x, y: y)
            enemy.agent.position = SIMD2<Float>(Float(x), Float(y))
            enemies.append(enemy)
            addEntity(enemy)
        }

        let label = SKLabelNode(text: "Tap to move. Enemies wander, then chase.")
        label.fontSize = 14
        label.fontColor = .white
        label.position = CGPoint(x: size.width / 2, y: 24)
        addChild(label)
    }

    private func addEntity(_ entity: GKEntity) {
        entities.append(entity)
        if let sprite = entity.component(ofType: SpriteComponent.self) {
            addChild(sprite.node)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: self) else { return }
        player.moveTowards(location)
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : currentTime - lastUpdate
        lastUpdate = currentTime
        for entity in entities {
            entity.update(deltaTime: dt)
        }
    }
}
