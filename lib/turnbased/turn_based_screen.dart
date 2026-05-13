import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../tutorials/tutorial_content.dart';
import '../tutorials/tutorial_view.dart';
import 'minimax.dart';
import 'tic_tac_toe_model.dart';

class TurnBasedScreen extends StatefulWidget {
  const TurnBasedScreen({super.key});

  @override
  State<TurnBasedScreen> createState() => _TurnBasedScreenState();
}

class _TurnBasedScreenState extends State<TurnBasedScreen> {
  final TicTacToeModel _model = TicTacToeModel();
  bool _aiThinking = false;

  String get _statusText {
    if (_model.winner == Mark.x) return 'You win!';
    if (_model.winner == Mark.o) return 'AI wins';
    if (_model.isDraw) return 'Draw';
    if (_aiThinking) return 'AI thinking…';
    return _model.current == Mark.x ? 'Your turn (X)' : 'AI turn (O)';
  }

  Future<void> _onCellTap(int index) async {
    if (_aiThinking || _model.isOver) return;
    if (_model.board[index] != Mark.empty || _model.current != Mark.x) return;

    setState(() => _model.apply(index));
    if (_model.isOver) return;

    setState(() => _aiThinking = true);
    final move = await compute(_pickMove, _model.copy());
    if (!mounted) return;
    setState(() {
      if (move != null) _model.apply(move);
      _aiThinking = false;
    });
  }

  void _newGame() {
    setState(() {
      _model.reset();
      _aiThinking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Turn-based'),
        actions: const [TutorialAppBarButton(tutorial: GameTutorials.ticTacToe)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              _statusText,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 1,
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: 9,
                itemBuilder: (_, i) => _Cell(
                  mark: _model.board[i],
                  onTap: () => _onCellTap(i),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: _newGame,
              child: const Text('New game'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.mark, required this.onTap});

  final Mark mark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: Text(
            mark.symbol,
            style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}

int? _pickMove(TicTacToeModel model) => bestMove(model, Mark.o);
