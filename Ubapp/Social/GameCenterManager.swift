import UIKit
import GameKit

final class GameCenterManager: NSObject {
    static let shared = GameCenterManager()

    private(set) var isAuthenticated = false
    private weak var pendingAuthPresenter: UIViewController?

    func authenticate() {
        let local = GKLocalPlayer.local
        local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController {
                self.pendingAuthPresenter?.present(viewController, animated: true)
            } else if local.isAuthenticated {
                self.isAuthenticated = true
            } else {
                self.isAuthenticated = false
                if let error { print("Game Center auth error: \(error.localizedDescription)") }
            }
        }
    }

    func presentDashboard(from presenter: UIViewController) {
        pendingAuthPresenter = presenter
        guard isAuthenticated else {
            let alert = UIAlertController(
                title: "Sign in to Game Center",
                message: "Open Settings → Game Center to sign in, then return to the app.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            presenter.present(alert, animated: true)
            return
        }
        let vc = GKGameCenterViewController(state: .dashboard)
        vc.gameCenterDelegate = self
        presenter.present(vc, animated: true)
    }

    func submit(score: Int, leaderboard: String) {
        guard isAuthenticated else { return }
        GKLeaderboard.submitScore(
            score,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [leaderboard],
            completionHandler: { error in
                if let error { print("Score submit error: \(error.localizedDescription)") }
            }
        )
    }
}

extension GameCenterManager: GKGameCenterControllerDelegate {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
