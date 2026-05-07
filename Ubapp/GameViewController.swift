import UIKit
import SpriteKit

final class GameViewController: UIViewController {
    private let skView = SKView()

    override func loadView() {
        view = skView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Real-time"
        skView.ignoresSiblingOrder = true
        skView.preferredFramesPerSecond = 60
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if skView.scene == nil {
            let scene = RealTimeScene(size: skView.bounds.size)
            scene.scaleMode = .resizeFill
            skView.presentScene(scene)
        }
    }
}
