import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'codenames_engine.dart';
import 'codenames_server.dart';

class CodenamesScreen extends StatefulWidget {
  const CodenamesScreen({super.key});

  @override
  State<CodenamesScreen> createState() => _CodenamesScreenState();
}

class _CodenamesScreenState extends State<CodenamesScreen> {
  CodenamesServer? _server;
  Uri? _uri;
  bool _starting = false;
  StreamSubscription<void>? _sub;
  final _clueController = TextEditingController();
  int _clueNumber = 1;

  @override
  void dispose() {
    _clueController.dispose();
    _sub?.cancel();
    _server?.stop();
    super.dispose();
  }

  Future<void> _toggleHost() async {
    if (_server != null) {
      await _server!.stop();
      await _sub?.cancel();
      setState(() { _server = null; _uri = null; _sub = null; });
      return;
    }
    setState(() => _starting = true);
    final s = CodenamesServer();
    final uri = await s.start();
    _sub = s.onStateChange.listen((_) => setState(() {}));
    setState(() { _server = s; _uri = uri; _starting = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = _server;
    return Scaffold(
      appBar: AppBar(title: const Text('Codenames')),
      body: s == null ? _splash() : _hosting(s),
    );
  }

  Widget _splash() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.grid_view, size: 80),
            const SizedBox(height: 16),
            Text('Codenames', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            const Text(
              'Two teams. Spymasters give one-word clues; agents guess words on a 5×5 grid.\nDon\'t pick the assassin.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _starting ? null : _toggleHost,
              icon: const Icon(Icons.wifi_tethering),
              label: Text(_starting ? 'Starting…' : 'Host a game'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hosting(CodenamesServer server) {
    final engine = server.engine;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_uri != null) _QrCard(uri: _uri!, guestCount: server.guestCount),
        const SizedBox(height: 12),
        if (engine.phase == CodenamesPhase.lobby) _lobby(server),
        if (engine.phase != CodenamesPhase.lobby) _game(server),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: _toggleHost, child: const Text('Stop hosting')),
      ],
    );
  }

  Widget _lobby(CodenamesServer server) {
    final engine = server.engine;
    final me = engine.players[CodenamesServer.hostId]!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lobby', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                    onPressed: () => server.hostJoinTeam(Team.red),
                    child: const Text('Join Red'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600),
                    onPressed: () => server.hostJoinTeam(Team.blue),
                    child: const Text('Join Blue'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: me.team == null
                  ? null
                  : () => server.hostSetSpymaster(!me.isSpymaster),
              child: Text(me.isSpymaster ? 'Step down as spymaster' : 'Be spymaster'),
            ),
            const Divider(height: 24),
            ...engine.players.values.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: p.team == null
                        ? null
                        : (p.team == Team.red ? Colors.red.shade600 : Colors.blue.shade600),
                    child: Text(p.name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(p.name),
                  subtitle: Text([
                    if (p.team != null) p.team!.name2,
                    if (p.isSpymaster) 'spymaster',
                    if (p.isHost) 'host',
                  ].join(' · ')),
                )),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: engine.canStart ? () => server.hostStart() : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start game'),
            ),
            const SizedBox(height: 4),
            if (!engine.canStart)
              Text(
                'Need 2+ players per team and a spymaster on each side.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _game(CodenamesServer server) {
    final engine = server.engine;
    final me = engine.players[CodenamesServer.hostId]!;
    final isSm = me.isSpymaster;
    final myTurn = engine.currentTeam == me.team;
    final over = engine.phase == CodenamesPhase.gameOver;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('RED · ${engine.cardsLeftFor(Team.red)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade600,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('BLUE · ${engine.cardsLeftFor(Team.blue)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: over
                ? (engine.winner == Team.red ? Colors.red.shade900 : Colors.blue.shade900)
                : (engine.currentTeam == Team.red ? Colors.red.shade900 : Colors.blue.shade900),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            over
                ? '${engine.winner!.name2.toUpperCase()} wins. ${engine.endReason ?? ''}'
                : '${engine.currentTeam.name2.toUpperCase()}\'s turn${myTurn ? ' — you' : ''}${isSm ? ' (spymaster)' : ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        if (!over && engine.currentClue != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Clue: "${engine.currentClue}" · ${engine.currentNumber} · ${engine.guessesLeftThisTurn} guesses left',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        if (!over && isSm && myTurn && engine.currentClue == null) _clueInput(server),
        const SizedBox(height: 8),
        _boardGrid(server),
        if (!over && myTurn && !isSm && engine.currentClue != null &&
            engine.guessesLeftThisTurn < engine.currentNumber + 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              onPressed: () => server.hostEndTurn(),
              child: const Text('End turn'),
            ),
          ),
        if (over)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FilledButton(
              onPressed: () => server.hostNewGame(),
              child: const Text('New game'),
            ),
          ),
        if (engine.lastEvent != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(engine.lastEvent!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _clueInput(CodenamesServer server) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your clue (one word + number)',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _clueController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'WORD',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: DropdownButtonFormField<int>(
                    initialValue: _clueNumber,
                    isDense: true,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: [for (var i = 0; i <= 9; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                    onChanged: (v) => setState(() => _clueNumber = v ?? 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                final c = _clueController.text.trim();
                if (c.isEmpty) return;
                server.hostSubmitClue(c, _clueNumber);
                _clueController.clear();
              },
              child: const Text('Submit clue'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _boardGrid(CodenamesServer server) {
    final engine = server.engine;
    final me = engine.players[CodenamesServer.hostId]!;
    final isSm = me.isSpymaster;
    final myTurn = engine.currentTeam == me.team;
    final canGuess = !isSm && myTurn && engine.currentClue != null &&
        engine.guessesLeftThisTurn > 0 && engine.phase == CodenamesPhase.playing;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1.5,
      ),
      itemCount: 25,
      itemBuilder: (_, i) {
        final card = engine.board[i];
        return GestureDetector(
          onTap: canGuess && !card.revealed ? () => server.hostGuess(i) : null,
          child: Container(
            decoration: BoxDecoration(
              color: _tileColor(card, isSm),
              borderRadius: BorderRadius.circular(6),
              border: !card.revealed && isSm
                  ? Border.all(color: _borderColor(card), width: 4)
                  : null,
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.all(4),
            child: Text(
              card.word,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _textColor(card, isSm),
                fontSize: 11,
              ),
            ),
          ),
        );
      },
    );
  }

  Color _tileColor(CodenamesCard c, bool isSm) {
    if (c.revealed) return switch (c.kind) {
      CardKind.red => Colors.red.shade600,
      CardKind.blue => Colors.blue.shade600,
      CardKind.neutral => Colors.brown.shade300,
      CardKind.assassin => Colors.black,
    };
    return const Color(0xFFD9C89B);
  }

  Color _borderColor(CodenamesCard c) => switch (c.kind) {
        CardKind.red => Colors.red.shade600,
        CardKind.blue => Colors.blue.shade600,
        CardKind.neutral => const Color(0xFF8D7959),
        CardKind.assassin => Colors.black,
      };

  Color _textColor(CodenamesCard c, bool isSm) {
    if (c.revealed) {
      return c.kind == CardKind.neutral ? Colors.black : Colors.white;
    }
    return Colors.black87;
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.uri, required this.guestCount});
  final Uri uri;
  final int guestCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              color: Colors.white,
              child: QrImageView(data: uri.toString(), size: 110),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hosting', style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  SelectableText(uri.toString(),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text('$guestCount guest${guestCount == 1 ? '' : 's'} connected',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
