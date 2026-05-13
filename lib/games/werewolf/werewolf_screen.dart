import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'werewolf_engine.dart';
import 'werewolf_role.dart';
import 'werewolf_server.dart';

class WerewolfScreen extends StatefulWidget {
  const WerewolfScreen({super.key});

  @override
  State<WerewolfScreen> createState() => _WerewolfScreenState();
}

class _WerewolfScreenState extends State<WerewolfScreen> {
  WerewolfServer? _server;
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
    final s = WerewolfServer();
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

  void _hostHunterShot() {
    final t = _pickedTarget;
    if (t == null) return;
    _server?.hostHunterShot(t);
    setState(() => _pickedTarget = null);
  }

  void _advance() {
    _server?.advanceFromReveal();
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    return Scaffold(
      appBar: AppBar(title: const Text('Werewolf')),
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
            const Icon(Icons.nightlight_round, size: 80),
            const SizedBox(height: 16),
            Text(
              'Werewolf',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'A richer take on Mafia — adds the Seer (investigates one player per night) and the Hunter (takes a player with them when killed). Host on this device; guests join via QR.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _starting ? null : _toggleHost,
              icon: const Icon(Icons.wifi_tethering),
              label: Text(_starting ? 'Starting…' : 'Host a game'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHosting(WerewolfServer server) {
    final engine = server.engine;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_uri != null) _QrCard(uri: _uri!, guestCount: server.guestCount),
        const SizedBox(height: 16),
        if (engine.phase == WerewolfPhase.lobby) _buildLobby(engine),
        if (engine.phase == WerewolfPhase.night) _buildNight(engine),
        if (engine.phase == WerewolfPhase.dayReveal) _buildDayReveal(engine),
        if (engine.phase == WerewolfPhase.dayVote) _buildDayVote(engine),
        if (engine.phase == WerewolfPhase.hunterShot) _buildHunterShot(engine),
        if (engine.phase == WerewolfPhase.gameOver) _buildGameOver(engine),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _toggleHost,
          child: const Text('Stop hosting'),
        ),
      ],
    );
  }

  Widget _buildLobby(WerewolfEngine engine) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Lobby', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '${engine.players.length} player${engine.players.length == 1 ? '' : 's'} — need at least 5',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ...engine.players.values.map((p) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
                  title: Text(p.name),
                  trailing: p.isHost ? const Chip(label: Text('Host')) : null,
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
    );
  }

  Widget _buildNight(WerewolfEngine engine) {
    final me = engine.players[WerewolfServer.hostId];
    if (me == null || !me.alive) return _buildSpectator();
    final role = me.role;
    if (role == WerewolfRole.werewolf) {
      final targets = engine.alive
          .where((p) => p.role != WerewolfRole.werewolf)
          .toList();
      return _PickTargetCard(
        title: 'Night ${engine.day} — pick a victim',
        accent: Colors.red.shade700,
        targets: targets,
        picked: _pickedTarget,
        onPick: (id) => setState(() => _pickedTarget = id),
        onConfirm: _hostNightAction,
      );
    }
    if (role == WerewolfRole.seer) {
      return _PickTargetCard(
        title: 'Night ${engine.day} — investigate',
        accent: Colors.indigo.shade400,
        targets: engine.alive.where((p) => p.id != me.id).toList(),
        picked: _pickedTarget,
        onPick: (id) => setState(() => _pickedTarget = id),
        onConfirm: _hostNightAction,
        footer: _buildSeerHistory(engine),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.bedtime, size: 48),
            const SizedBox(height: 12),
            Text('Night ${engine.day}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text("You're a ${role!.displayName}. ${role.tagline}",
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget? _buildSeerHistory(WerewolfEngine engine) {
    final r = engine.lastSeerResult;
    if (r == null) return null;
    final me = engine.players[WerewolfServer.hostId];
    if (me?.role != WerewolfRole.seer) return null;
    final target = engine.players[r.targetId];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (r.isWerewolf ? Colors.red : Colors.green).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Last night: ${target?.name ?? '?'} ${r.isWerewolf ? 'IS a werewolf' : 'is not a werewolf'}.',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildDayReveal(WerewolfEngine engine) {
    final n = engine.lastNight!;
    final body = n.killedId != null
        ? '${engine.players[n.killedId]!.name} was killed in the night.'
        : 'A quiet night. No one died.';
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

  Widget _buildDayVote(WerewolfEngine engine) {
    final me = engine.players[WerewolfServer.hostId];
    if (me == null || !me.alive) return _buildSpectator();
    final targets = engine.alive.where((p) => p.id != me.id).toList();
    return _PickTargetCard(
      title: 'Day ${engine.day} — vote to lynch',
      accent: Colors.amber.shade700,
      targets: targets,
      extraSkip: true,
      picked: _pickedTarget,
      onPick: (id) => setState(() => _pickedTarget = id),
      onConfirm: _hostDayVote,
    );
  }

  Widget _buildHunterShot(WerewolfEngine engine) {
    final me = engine.players[WerewolfServer.hostId];
    final shooterId = engine.pendingHunterShooter;
    if (me == null || shooterId != me.id) {
      final shooter = engine.players[shooterId];
      return Card(
        color: Colors.red.shade900.withValues(alpha: 0.4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(Icons.gps_fixed, size: 48),
              const SizedBox(height: 12),
              Text(
                '${shooter?.name ?? 'A hunter'} is choosing someone to take down…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
    }
    return _PickTargetCard(
      title: 'You died. Take one with you.',
      accent: Colors.red.shade700,
      targets: engine.alive.where((p) => p.id != me.id).toList(),
      picked: _pickedTarget,
      onPick: (id) => setState(() => _pickedTarget = id),
      onConfirm: _hostHunterShot,
      confirmLabel: 'Fire',
    );
  }

  Widget _buildSpectator() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.visibility_off, size: 48),
            SizedBox(height: 12),
            Text("You're out — watching the rest of the round."),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOver(WerewolfEngine engine) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                engine.winner == Winner.werewolves
                    ? 'Werewolves win'
                    : 'Village wins',
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
    this.confirmLabel = 'Confirm',
    this.footer,
  });

  final String title;
  final Color accent;
  final List<Player> targets;
  final String? picked;
  final void Function(String) onPick;
  final VoidCallback onConfirm;
  final bool extraSkip;
  final String confirmLabel;
  final Widget? footer;

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
              child: Text(confirmLabel),
            ),
            if (footer != null) footer!,
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
      color: selected
          ? accent
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
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
