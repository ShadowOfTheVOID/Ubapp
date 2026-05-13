import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../tutorials/tutorial_content.dart';
import '../../tutorials/tutorial_view.dart';
import 'mafia_engine.dart';
import 'mafia_role.dart';
import 'mafia_server.dart';

class MafiaScreen extends StatefulWidget {
  const MafiaScreen({super.key});

  @override
  State<MafiaScreen> createState() => _MafiaScreenState();
}

class _MafiaScreenState extends State<MafiaScreen> {
  MafiaServer? _server;
  Uri? _uri;
  bool _starting = false;
  StreamSubscription<void>? _stateSub;
  String? _pickedTarget;

  @override
  void dispose() {
    _stateSub?.cancel();
    _server?.stop();
    super.dispose();
  }

  Future<void> _toggleHost() async {
    if (_server != null) {
      await _server!.stop();
      await _stateSub?.cancel();
      setState(() {
        _server = null;
        _uri = null;
        _stateSub = null;
        _pickedTarget = null;
      });
      return;
    }
    setState(() => _starting = true);
    final s = MafiaServer();
    final uri = await s.start();
    _stateSub = s.onStateChange.listen((_) => setState(() {}));
    setState(() {
      _server = s;
      _uri = uri;
      _starting = false;
    });
  }

  void _hostStart() {
    _server?.hostStart();
    setState(() {});
  }

  void _hostNightAction() {
    final t = _pickedTarget;
    if (t == null) return;
    _server?.hostNightAction(t);
    setState(() => _pickedTarget = null);
  }

  void _hostDayVote() {
    final t = _pickedTarget;
    if (t == null) return;
    _server?.hostDayVote(t == '__skip' ? null : t);
    setState(() => _pickedTarget = null);
  }

  void _advance() {
    _server?.advanceFromReveal();
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    return Scaffold(
      appBar: AppBar(title: const Text('Mafia')),
      body: server == null ? _buildSplash() : _buildHosting(server),
    );
  }

  Widget _buildSplash() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.theater_comedy, size: 80),
            const SizedBox(height: 16),
            Text(
              'Mafia',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Host a game on this device. Anyone with a phone can join via QR — no install needed.',
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

  Widget _buildHosting(MafiaServer server) {
    final engine = server.engine;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_uri != null) _QrCard(uri: _uri!, guestCount: server.guestCount),
        const SizedBox(height: 16),
        if (engine.phase == MafiaPhase.lobby) _buildLobby(engine),
        if (engine.phase == MafiaPhase.night) _buildNight(engine),
        if (engine.phase == MafiaPhase.dayReveal) _buildDayReveal(engine),
        if (engine.phase == MafiaPhase.dayVote) _buildDayVote(engine),
        if (engine.phase == MafiaPhase.gameOver) _buildGameOver(engine),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _toggleHost,
          child: const Text('Stop hosting'),
        ),
      ],
    );
  }

  Widget _buildLobby(MafiaEngine engine) {
    final theme = Theme.of(context);
    final vote = engine.tutorialVote;
    final showTutorial = vote.result == true && !vote.tutorialShown;
    final myVote = vote.votes[MafiaServer.hostId];
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
          onCallVote: () => _server?.hostCallTutorialVote(),
          onVote: (yes) => _server?.hostTutorialVote(yes),
        ),
        if (showTutorial) ...[
          const SizedBox(height: 12),
          TutorialView(
            tutorial: GameTutorials.mafia,
            onDone: () => _server?.hostDismissTutorial(),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Lobby', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  '${engine.players.length} player${engine.players.length == 1 ? '' : 's'} — need at least 4',
                  style: theme.textTheme.bodySmall,
                ),
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
                  onPressed: engine.canStart ? _hostStart : null,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start game'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNight(MafiaEngine engine) {
    final me = engine.players[MafiaServer.hostId];
    if (me == null || !me.alive) return _buildSpectator(engine);
    final role = me.role;
    if (role == MafiaRole.mafia) {
      return _PickTargetCard(
        title: 'Night ${engine.day} — pick a kill target',
        accent: Colors.red.shade700,
        targets: engine.alive.where((p) => p.id != me.id).toList(),
        picked: _pickedTarget,
        onPick: (id) => setState(() => _pickedTarget = id),
        onConfirm: _hostNightAction,
      );
    }
    if (role == MafiaRole.doctor) {
      return _PickTargetCard(
        title: 'Night ${engine.day} — pick a player to save',
        accent: Colors.green.shade700,
        targets: engine.alive.toList(),
        picked: _pickedTarget,
        onPick: (id) => setState(() => _pickedTarget = id),
        onConfirm: _hostNightAction,
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.bedtime, size: 48),
            const SizedBox(height: 12),
            Text('Night ${engine.day}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('You\'re a Villager. Wait for the mafia and doctor to act.'),
          ],
        ),
      ),
    );
  }

  Widget _buildDayReveal(MafiaEngine engine) {
    final n = engine.lastNight!;
    final body = n.killedId != null
        ? '${engine.players[n.killedId]!.name} was killed in the night.'
        : (n.savedId != null
            ? 'The doctor saved someone — no one died.'
            : 'A quiet night. No one died.');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('Day ${engine.day}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(body, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _advance,
              child: const Text('Begin discussion + vote'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayVote(MafiaEngine engine) {
    final me = engine.players[MafiaServer.hostId];
    if (me == null || !me.alive) return _buildSpectator(engine);
    final targets = engine.alive.where((p) => p.id != me.id).toList();
    return _PickTargetCard(
      title: 'Day ${engine.day} — vote to eliminate',
      accent: Colors.amber.shade700,
      targets: targets,
      extraSkip: true,
      picked: _pickedTarget,
      onPick: (id) => setState(() => _pickedTarget = id),
      onConfirm: _hostDayVote,
    );
  }

  Widget _buildSpectator(MafiaEngine engine) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.visibility_off, size: 48),
            SizedBox(height: 12),
            Text('You\'re out — watching the rest of the round.'),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOver(MafiaEngine engine) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                engine.winner == Winner.mafia ? 'Mafia win' : 'Town wins',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 16),
            ...engine.players.values.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
                  title: Text(p.name),
                  trailing: Text(p.role!.displayName),
                )),
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
                  Text('Hosting',
                      style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  SelectableText(uri.toString(),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    '$guestCount guest${guestCount == 1 ? '' : 's'} connected',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickTargetCard extends StatelessWidget {
  const _PickTargetCard({
    required this.title,
    required this.accent,
    required this.targets,
    required this.picked,
    required this.onPick,
    required this.onConfirm,
    this.extraSkip = false,
  });

  final String title;
  final Color accent;
  final List<Player> targets;
  final String? picked;
  final void Function(String) onPick;
  final VoidCallback onConfirm;
  final bool extraSkip;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: accent.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...targets.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TargetButton(
                    label: p.name,
                    selected: picked == p.id,
                    accent: accent,
                    onTap: () => onPick(p.id),
                  ),
                )),
            if (extraSkip)
              _TargetButton(
                label: 'Skip vote',
                selected: picked == '__skip',
                accent: accent,
                onTap: () => onPick('__skip'),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: picked == null ? null : onConfirm,
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetButton extends StatelessWidget {
  const _TargetButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? accent : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? Colors.white : null,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: selected ? Colors.white : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
