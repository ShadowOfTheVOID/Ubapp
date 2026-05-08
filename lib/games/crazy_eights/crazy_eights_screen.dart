import 'dart:async';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter/material.dart' as m show Card;
import 'package:qr_flutter/qr_flutter.dart';

import 'card.dart';
import 'crazy_eights_engine.dart';
import 'crazy_eights_server.dart';

class CrazyEightsScreen extends StatefulWidget {
  const CrazyEightsScreen({super.key});

  @override
  State<CrazyEightsScreen> createState() => _CrazyEightsScreenState();
}

class _CrazyEightsScreenState extends State<CrazyEightsScreen> {
  CrazyEightsServer? _server;
  Uri? _uri;
  bool _starting = false;
  StreamSubscription<void>? _sub;

  @override
  void dispose() {
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
    final s = CrazyEightsServer();
    final uri = await s.start();
    _sub = s.onStateChange.listen((_) => setState(() {}));
    setState(() { _server = s; _uri = uri; _starting = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = _server;
    return Scaffold(
      appBar: AppBar(title: const Text('Crazy Eights')),
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
            const Icon(Icons.style, size: 80),
            const SizedBox(height: 16),
            Text('Crazy Eights', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            const Text(
              'Match suit or rank. Eights are wild.\nFirst to empty hand wins.',
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

  Widget _hosting(CrazyEightsServer server) {
    final engine = server.engine;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_uri != null) _QrCard(uri: _uri!, guestCount: server.guestCount),
        const SizedBox(height: 12),
        if (engine.phase == CrazyEightsPhase.lobby) _lobby(server),
        if (engine.phase == CrazyEightsPhase.playing) _table(server),
        if (engine.phase == CrazyEightsPhase.gameOver) _over(server),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: _toggleHost, child: const Text('Stop hosting')),
      ],
    );
  }

  Widget _lobby(CrazyEightsServer server) {
    final engine = server.engine;
    return m.Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lobby', style: Theme.of(context).textTheme.titleMedium),
            Text('${engine.players.length} player${engine.players.length == 1 ? '' : 's'} — need 2 to 8',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            ...engine.players.values.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
                  title: Text(p.name),
                  trailing: p.isHost ? const Chip(label: Text('Host')) : null,
                )),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: engine.canStart ? () => server.hostStart() : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Deal cards'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _table(CrazyEightsServer server) {
    final engine = server.engine;
    final me = engine.players[CrazyEightsServer.hostId]!;
    final isMyTurn = engine.current?.id == me.id;
    final top = engine.topCard;
    final activeSuit = engine.activeOrTopSuit;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final p in engine.players.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: engine.current?.id == p.id
                          ? Colors.green.shade700
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name + (p.id == me.id ? ' (you)' : ''),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('${p.hand.length} cards', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.green.shade900,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: isMyTurn && !engine.justDrew ? () => server.hostDraw() : null,
                    child: Container(
                      width: 88,
                      height: 128,
                      decoration: BoxDecoration(
                        color: Colors.green.shade800,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white24, width: 2),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${engine.drawPile.length}',
                                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            const Text('draw', style: TextStyle(color: Colors.white60, fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  if (top != null) _CardWidget(card: top),
                ],
              ),
              const SizedBox(height: 12),
              Text('Active suit: ${activeSuit.glyph}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                isMyTurn ? '— Your turn —' : '${engine.current?.name ?? ''}\'s turn',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              if (engine.lastEvent != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(engine.lastEvent!,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in me.hand)
              _PlayableCard(
                card: c,
                playable: isMyTurn && engine.canPlay(c),
                onTap: () => _onCardTap(server, c),
              ),
          ],
        ),
        if (isMyTurn && engine.justDrew)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton(
              onPressed: () => server.hostPass(),
              child: const Text('Pass'),
            ),
          ),
      ],
    );
  }

  Future<void> _onCardTap(CrazyEightsServer server, Card c) async {
    final engine = server.engine;
    if (engine.current?.id != CrazyEightsServer.hostId) return;
    if (!engine.canPlay(c)) return;
    if (c.rank == 8) {
      final s = await _pickSuit();
      if (s == null) return;
      server.hostPlay(c, declaredSuit: s);
    } else {
      server.hostPlay(c);
    }
    if (mounted) setState(() {});
  }

  Future<Suit?> _pickSuit() async {
    return showDialog<Suit>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Declare a new suit'),
        content: SizedBox(
          width: 200,
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final s in Suit.values)
                InkWell(
                  onTap: () => Navigator.of(context).pop(s),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        s.glyph,
                        style: TextStyle(
                          fontSize: 36,
                          color: s.isRed ? Colors.red : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _over(CrazyEightsServer server) {
    final engine = server.engine;
    final winner = engine.players[engine.winnerId]!;
    return m.Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Text('${winner.name} wins!', style: Theme.of(context).textTheme.headlineSmall)),
            const SizedBox(height: 16),
            ...engine.players.values.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
                  title: Text(p.name),
                  trailing: Text('${p.hand.length} left'),
                )),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => server.hostNewGame(),
              child: const Text('New game'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardWidget extends StatelessWidget {
  const _CardWidget({required this.card});
  final Card card;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 128,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(card.rankShort,
              style: TextStyle(
                  color: card.suit.isRed ? Colors.red.shade700 : Colors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(card.suit.glyph,
                style: TextStyle(
                    color: card.suit.isRed ? Colors.red.shade700 : Colors.black,
                    fontSize: 36)),
          ),
        ],
      ),
    );
  }
}

class _PlayableCard extends StatelessWidget {
  const _PlayableCard({
    required this.card,
    required this.playable,
    required this.onTap,
  });
  final Card card;
  final bool playable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: playable ? onTap : null,
      child: Opacity(
        opacity: playable ? 1.0 : 0.4,
        child: Container(
          width: 64,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: playable
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))]
                : null,
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(card.rankShort,
                  style: TextStyle(
                      color: card.suit.isRed ? Colors.red.shade700 : Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(card.suit.glyph,
                    style: TextStyle(
                        color: card.suit.isRed ? Colors.red.shade700 : Colors.black,
                        fontSize: 22)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.uri, required this.guestCount});
  final Uri uri;
  final int guestCount;

  @override
  Widget build(BuildContext context) {
    return m.Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(6), color: Colors.white,
              child: QrImageView(data: uri.toString(), size: 110)),
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
