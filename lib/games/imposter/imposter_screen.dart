import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../tutorials/tutorial_content.dart';
import '../../tutorials/tutorial_view.dart';
import 'imposter_engine.dart';
import 'imposter_server.dart';

class ImposterScreen extends StatefulWidget {
  const ImposterScreen({super.key});

  @override
  State<ImposterScreen> createState() => _ImposterScreenState();
}

class _ImposterScreenState extends State<ImposterScreen> {
  ImposterServer? _server;
  Uri? _uri;
  bool _starting = false;
  StreamSubscription<void>? _sub;
  String? _picked;

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
      setState(() { _server = null; _uri = null; _sub = null; _picked = null; });
      return;
    }
    setState(() => _starting = true);
    final s = ImposterServer();
    final uri = await s.start();
    _sub = s.onStateChange.listen((_) => setState(() {}));
    setState(() { _server = s; _uri = uri; _starting = false; });
  }

  @override
  Widget build(BuildContext context) {
    final s = _server;
    return Scaffold(
      appBar: AppBar(title: const Text('Imposter')),
      body: s == null ? _buildSplash() : _buildHosting(s),
    );
  }

  Widget _buildSplash() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.psychology_alt, size: 80),
            const SizedBox(height: 16),
            Text('Imposter', style: Theme.of(context).textTheme.displaySmall),
            const SizedBox(height: 8),
            const Text(
              'Everyone gets a secret word — except one Imposter who only sees the category. Bluff and vote.',
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

  Widget _buildHosting(ImposterServer server) {
    final engine = server.engine;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_uri != null) _QrCard(uri: _uri!, guestCount: server.guestCount),
        const SizedBox(height: 12),
        if (engine.phase == ImposterPhase.lobby) _buildLobby(server),
        if (engine.phase == ImposterPhase.playing) _buildPlaying(server),
        if (engine.phase == ImposterPhase.voting) _buildVoting(server),
        if (engine.phase == ImposterPhase.result) _buildResult(server),
        const SizedBox(height: 16),
        OutlinedButton(onPressed: _toggleHost, child: const Text('Stop hosting')),
      ],
    );
  }

  Widget _buildLobby(ImposterServer server) {
    final engine = server.engine;
    final vote = engine.tutorialVote;
    final showTutorial = vote.result == true && !vote.tutorialShown;
    final myVote = vote.votes[ImposterServer.hostId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TutorialVoteCard(
          isOpen: vote.isOpen,
          tutorialShown: vote.tutorialShown,
          yesCount: vote.yesCount,
          noCount: vote.noCount,
          eligibleCount: vote.eligibleCount,
          myVote: myVote,
          result: vote.result,
          onCallVote: server.hostCallTutorialVote,
          onVote: server.hostTutorialVote,
        ),
        if (showTutorial) ...[
          const SizedBox(height: 12),
          TutorialView(
            tutorial: GameTutorials.imposter,
            onDone: server.hostDismissTutorial,
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Lobby', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                    '${engine.players.length} player${engine.players.length == 1 ? '' : 's'} — need at least 3',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                ...engine.players.values.map((p) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading:
                          CircleAvatar(child: Text(p.name[0].toUpperCase())),
                      title: Text(p.name),
                      trailing:
                          p.isHost ? const Chip(label: Text('Host')) : null,
                    )),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: engine.canStart ? () => server.hostStart() : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start round'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaying(ImposterServer server) {
    final engine = server.engine;
    final me = engine.players[ImposterServer.hostId]!;
    final isImposter = me.isImposter;
    return Card(
      color: isImposter ? Colors.red.shade900 : Colors.green.shade900,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(isImposter ? 'YOUR ROLE' : 'SECRET WORD',
                style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(
              isImposter ? 'IMPOSTER' : engine.secretWord.toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text('Category: ${engine.category}',
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 24),
            Text(
              isImposter
                  ? 'Bluff your way through. Don\'t get voted out.'
                  : 'Discuss in person. Find the imposter.',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: () => server.hostBeginVoting(),
              child: const Text('Call a vote'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoting(ImposterServer server) {
    final engine = server.engine;
    final me = engine.players[ImposterServer.hostId]!;
    final targets = engine.players.values.where((p) => p.id != me.id).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Vote — pick the imposter',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...targets.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _Pick(
                    label: p.name,
                    selected: _picked == p.id,
                    onTap: () => setState(() => _picked = p.id),
                  ),
                )),
            _Pick(
              label: 'Skip',
              selected: _picked == '__skip',
              onTap: () => setState(() => _picked = '__skip'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _picked == null
                  ? null
                  : () {
                      server.hostVote(_picked == '__skip' ? null : _picked);
                      setState(() => _picked = null);
                    },
              child: const Text('Lock in vote'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(ImposterServer server) {
    final engine = server.engine;
    final imposter = engine.players[engine.imposterId]!;
    final accused = engine.mostVotedId == null ? null : engine.players[engine.mostVotedId]!;
    final won = engine.winner == ImposterWinner.town ? 'Town wins' : 'Imposter wins';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(won, style: Theme.of(context).textTheme.headlineSmall),
            ),
            const SizedBox(height: 16),
            Text('Imposter: ${imposter.name}'),
            if (accused != null)
              Text('Voted out: ${accused.name}${(engine.imposterCaught ?? false) ? ' — correct!' : ' — wrong'}')
            else
              const Text('Vote tied — no one was eliminated'),
            const SizedBox(height: 8),
            Text('Secret word: ${engine.secretWord} (${engine.category})'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () { setState(() => _picked = null); server.hostNewRound(); },
              child: const Text('New round'),
            ),
          ],
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
    return Card(
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

class _Pick extends StatelessWidget {
  const _Pick({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? Colors.white : null),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(fontSize: 16, color: selected ? Colors.white : null)),
            ],
          ),
        ),
      ),
    );
  }
}
