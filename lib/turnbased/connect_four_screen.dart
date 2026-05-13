import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../tutorials/tutorial_content.dart';
import '../tutorials/tutorial_view.dart';
import 'connect_four_ai.dart';
import 'connect_four_model.dart';

class ConnectFourScreen extends StatefulWidget {
  const ConnectFourScreen({super.key});

  @override
  State<ConnectFourScreen> createState() => _ConnectFourScreenState();
}

class _ConnectFourScreenState extends State<ConnectFourScreen> {
  final _model = ConnectFourModel();
  bool _aiThinking = false;

  String get _statusText {
    final w = _model.winner;
    if (w == Disc.red) return 'You win!';
    if (w == Disc.yellow) return 'AI wins';
    if (_model.isDraw) return 'Draw';
    if (_aiThinking) return 'AI thinking…';
    return _model.current == Disc.red ? 'Your turn (red)' : 'AI turn (yellow)';
  }

  Future<void> _onColumnTap(int col) async {
    if (_aiThinking || _model.isOver) return;
    if (_model.current != Disc.red || !_model.isLegal(col)) return;

    setState(() => _model.apply(col));
    if (_model.isOver) return;

    setState(() => _aiThinking = true);
    final move = await compute(_pickAi, _model.copy());
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
        title: const Text('Connect Four'),
        actions: const [TutorialAppBarButton(tutorial: GameTutorials.connectFour)],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_statusText, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: kCols / kRows,
                  child: _Board(model: _model, onTapColumn: _onColumnTap),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: _newGame, child: const Text('New game')),
          ],
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board({required this.model, required this.onTapColumn});
  final ConnectFourModel model;
  final void Function(int col) onTapColumn;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cellW = c.maxWidth / kCols;
        final cellH = c.maxHeight / kRows;
        final cell = cellW < cellH ? cellW : cellH;
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.shade800,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var r = kRows - 1; r >= 0; r--)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var col = 0; col < kCols; col++)
                      GestureDetector(
                        onTap: () => onTapColumn(col),
                        child: Container(
                          width: cell - 8,
                          height: cell - 8,
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _color(model.at(col, r)),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Color _color(Disc d) => switch (d) {
        Disc.red => Colors.red.shade600,
        Disc.yellow => Colors.amber.shade400,
        Disc.empty => Colors.blue.shade900,
      };
}

int? _pickAi(ConnectFourModel m) => bestMove(m, Disc.yellow, depth: 6);
