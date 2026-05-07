import SpriteKit
import GameplayKit

final class SpriteComponent: GKComponent {
    let node: SKShapeNode

    init(color: UIColor, radius: CGFloat) {
        self.node = SKShapeNode(circleOfRadius: radius)
        self.node.fillColor = color
        self.node.strokeColor = .white
        self.node.lineWidth = 1.5
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
