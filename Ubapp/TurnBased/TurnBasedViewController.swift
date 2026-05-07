import UIKit
import GameplayKit

final class TurnBasedViewController: UIViewController {
    private let model = TicTacToeModel()
    private let strategist = GKMinmaxStrategist()
    private let statusLabel = UILabel()
    private var cells: [UIButton] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Turn-based"
        view.backgroundColor = .systemBackground

        strategist.maxLookAheadDepth = 6
        strategist.randomSource = GKARC4RandomSource()
        strategist.gameModel = model

        statusLabel.text = "Your turn (X)"
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .title2)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        let grid = UIStackView()
        grid.axis = .vertical
        grid.spacing = 8
        grid.distribution = .fillEqually
        grid.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(grid)

        for row in 0..<3 {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually
            for col in 0..<3 {
                let index = row * 3 + col
                let button = UIButton(type: .system)
                button.backgroundColor = .secondarySystemBackground
                button.layer.cornerRadius = 12
                button.titleLabel?.font = .systemFont(ofSize: 48, weight: .bold)
                button.tag = index
                button.addTarget(self, action: #selector(cellTapped(_:)), for: .touchUpInside)
                cells.append(button)
                rowStack.addArrangedSubview(button)
            }
            grid.addArrangedSubview(rowStack)
        }

        let reset = UIButton(type: .system)
        reset.setTitle("New game", for: .normal)
        reset.addTarget(self, action: #selector(newGame), for: .touchUpInside)
        reset.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reset)

        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            grid.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            grid.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            grid.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.85),
            grid.heightAnchor.constraint(equalTo: grid.widthAnchor),

            reset.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 24),
            reset.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    @objc private func cellTapped(_ sender: UIButton) {
        let index = sender.tag
        guard model.board[index] == .empty, model.current.mark == .x, model.winner == nil else { return }
        model.apply(TicTacToeMove(index: index))
        refresh()
        guard !checkEndState() else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let move = self.strategist.bestMove(for: TicTacToePlayer.o) as? TicTacToeMove
            DispatchQueue.main.async {
                if let move {
                    self.model.apply(move)
                    self.refresh()
                    _ = self.checkEndState()
                }
            }
        }
    }

    @objc private func newGame() {
        model.board = Array(repeating: .empty, count: 9)
        model.current = .x
        refresh()
    }

    private func refresh() {
        for (i, mark) in model.board.enumerated() {
            cells[i].setTitle(mark.symbol, for: .normal)
        }
        if let w = model.winner {
            statusLabel.text = w.mark == .x ? "You win!" : "AI wins"
        } else if model.isDraw {
            statusLabel.text = "Draw"
        } else {
            statusLabel.text = model.current.mark == .x ? "Your turn (X)" : "AI thinking…"
        }
    }

    @discardableResult
    private func checkEndState() -> Bool {
        return model.winner != nil || model.isDraw
    }
}
