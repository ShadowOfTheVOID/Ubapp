import UIKit

final class MainMenuViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Ubapp"
        view.backgroundColor = .systemBackground

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        stack.addArrangedSubview(makeButton(title: "Real-time", action: #selector(openRealTime)))
        stack.addArrangedSubview(makeButton(title: "Turn-based", action: #selector(openTurnBased)))
        stack.addArrangedSubview(makeButton(title: "Social (Game Center)", action: #selector(openSocial)))

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor, constant: -24),
        ])
    }

    private func makeButton(title: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.cornerStyle = .large
        config.buttonSize = .large
        let button = UIButton(configuration: config, primaryAction: nil)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func openRealTime() {
        navigationController?.pushViewController(GameViewController(), animated: true)
    }

    @objc private func openTurnBased() {
        navigationController?.pushViewController(TurnBasedViewController(), animated: true)
    }

    @objc private func openSocial() {
        GameCenterManager.shared.presentDashboard(from: self)
    }
}
